import 'package:meta/meta.dart';

import '../domain/catalog_artifact_snapshot.dart';
import '../domain/catalog_manifest.dart';
import '../domain/download_request.dart';
import '../domain/provisioning_cancellation_token.dart';
import '../domain/provisioning_clock.dart';
import '../domain/provisioning_options.dart';
import '../domain/validated_catalog_candidate.dart';
import '../validation/artifact_import_inspector.dart';
import 'artifact_download_engine.dart';
import 'download_checkpoint_repository.dart';
import 'provisioning_coordinator.dart';
import 'single_pass_artifact_ingestion_engine.dart';

/// Fase specifica del processo di provisioning di un modello.
enum ModelProvisioningPhase {
  download,
  verification,
  ingestion,
  commit,
  cleanup,
}

/// Richiesta di importazione per un file GGUF locale scelto dall'utente.
@immutable
final class LocalArtifactImportRequest {
  final String operationId;
  final String localFilePath;
  final ValidatedCatalogCandidate candidate;
  final CatalogArtifact targetArtifact;

  const LocalArtifactImportRequest({
    required this.operationId,
    required this.localFilePath,
    required this.candidate,
    required this.targetArtifact,
  });
}

/// Servizio di orchestrazione applicativa per l'acquisizione, la verifica ed il provisioning dei modelli.
final class ModelProvisioningService {
  final ArtifactDownloadEngine _downloadEngine;
  final SinglePassArtifactIngestionEngine _ingestionEngine;
  final ProvisioningCoordinator _coordinator;
  final ArtifactImportInspector _importInspector;
  final DownloadCheckpointRepository _checkpointRepository;
  final ProvisioningClock _clock;

  ModelProvisioningService({
    required ArtifactDownloadEngine downloadEngine,
    required SinglePassArtifactIngestionEngine ingestionEngine,
    required ProvisioningCoordinator coordinator,
    required ArtifactImportInspector importInspector,
    required DownloadCheckpointRepository checkpointRepository,
    ProvisioningClock clock = const SystemProvisioningClock(),
  })  : _downloadEngine = downloadEngine,
        _ingestionEngine = ingestionEngine,
        _coordinator = coordinator,
        _importInspector = importInspector,
        _checkpointRepository = checkpointRepository,
        _clock = clock;

  ArtifactImportInspector get importInspector => _importInspector;

  /// Esegue la pipeline completa per un modello remoto:
  /// Download Range -> Ingestione & Verifica Single-Pass -> Commit Atomico nel Coordinator.
  Future<ProvisioningResult> provisionRemoteModel({
    required ProvisioningRequest request,
    required ValidatedCatalogCandidate candidate,
    required CatalogArtifact artifact,
    ProvisioningCancellationToken? cancellationToken,
    void Function(double progressFraction)? onProgress,
  }) async {
    final provenanceSnapshot = CatalogArtifactSnapshot.fromCandidate(
      candidate: candidate,
      artifact: artifact,
      acquiredAtUtc: _clock.nowUtc(),
    );

    // 1. Download o Resume via HTTP Range nello staging gestito
    final downloadRequest = DownloadRequest(
      operationId: request.operationId,
      artifactId: artifact.artifactId,
      sourceUri: Uri.parse(artifact.downloadUri!),
      expectedSizeBytes: artifact.sizeBytes,
    );

    final downloadResult = await _downloadEngine.downloadArtifact(
      request: downloadRequest,
      cancellationToken: null,
      onProgress: (progress) {
        if (onProgress != null) {
          onProgress(progress.fraction);
        }
      },
    );

    if (downloadResult.isFailure) {
      return ProvisioningResult.failure(
        operationId: request.operationId,
        artifactId: artifact.artifactId,
        sourceKind: ProvisioningSourceKind.remoteHttps,
        failureReason: ProvisioningFailureReason.downloadNotAllowed,
        sanitizedMessage:
            downloadResult.message ?? 'Errore durante il download.',
      );
    }

    final stagingArtifact = downloadResult.stagingArtifact!;

    // 2. Ingestione e Verifica Single-Pass dal file .part alla directory .installing
    try {
      cancellationToken?.throwIfCancelled();

      final preparedInstallation =
          await _ingestionEngine.ingestAndVerifyToTemporaryStore(
        sourceFilePath: stagingArtifact.stagingPath,
        operationId: request.operationId,
        provenanceSnapshot: provenanceSnapshot,
        sourceOwnership: ArtifactSourceOwnership.managedStaging,
        cancellationToken: cancellationToken,
      );

      // 3. Registrazione e Commit Atomico nel Coordinator
      return await _coordinator.registerVerifiedArtifact(
        installation: preparedInstallation,
        operationId: request.operationId,
        checkpointRepository: _checkpointRepository,
        cancellationToken: cancellationToken,
      );
    } catch (e) {
      if (e is ProvisioningException &&
          e.reason == ProvisioningFailureReason.operationCancelled) {
        return ProvisioningResult.failure(
          operationId: request.operationId,
          artifactId: artifact.artifactId,
          sourceKind: ProvisioningSourceKind.remoteHttps,
          failureReason: ProvisioningFailureReason.operationCancelled,
          sanitizedMessage: 'Operazione annullata durante l\'ingestione.',
        );
      }
      if (e is ProvisioningException) {
        return ProvisioningResult.failure(
          operationId: request.operationId,
          artifactId: artifact.artifactId,
          sourceKind: ProvisioningSourceKind.remoteHttps,
          failureReason: e.reason,
          sanitizedMessage: e.message,
        );
      }
      rethrow;
    }
  }

  /// Ispeziona ed importa un file GGUF locale dell'utente preservando intatto il file sorgente originale.
  Future<ProvisioningResult> importLocalModel({
    required LocalArtifactImportRequest importRequest,
    ProvisioningCancellationToken? cancellationToken,
  }) async {
    final provenanceSnapshot = CatalogArtifactSnapshot.fromCandidate(
      candidate: importRequest.candidate,
      artifact: importRequest.targetArtifact,
      acquiredAtUtc: _clock.nowUtc(),
    );

    try {
      cancellationToken?.throwIfCancelled();

      // Ingestione Single-Pass con possesso sorgente userOwnedFile (sorgente mai cancellato)
      final preparedInstallation =
          await _ingestionEngine.ingestAndVerifyToTemporaryStore(
        sourceFilePath: importRequest.localFilePath,
        operationId: importRequest.operationId,
        provenanceSnapshot: provenanceSnapshot,
        sourceOwnership: ArtifactSourceOwnership.userOwnedFile,
        cancellationToken: cancellationToken,
      );

      return await _coordinator.registerVerifiedArtifact(
        installation: preparedInstallation,
        operationId: importRequest.operationId,
        cancellationToken: cancellationToken,
      );
    } catch (e) {
      if (e is ProvisioningException &&
          e.reason == ProvisioningFailureReason.operationCancelled) {
        return ProvisioningResult.failure(
          operationId: importRequest.operationId,
          artifactId: importRequest.targetArtifact.artifactId,
          sourceKind: ProvisioningSourceKind.localImport,
          failureReason: ProvisioningFailureReason.operationCancelled,
          sanitizedMessage: 'Importazione locale annullata.',
        );
      }
      if (e is ProvisioningException) {
        return ProvisioningResult.failure(
          operationId: importRequest.operationId,
          artifactId: importRequest.targetArtifact.artifactId,
          sourceKind: ProvisioningSourceKind.localImport,
          failureReason: e.reason,
          sanitizedMessage: e.message,
        );
      }
      rethrow;
    }
  }
}
