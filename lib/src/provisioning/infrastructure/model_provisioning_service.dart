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
import 'provisioning_file_system.dart';
import 'provisioning_path_resolver.dart';
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
///
/// Il chiamante non specifica l'artifact target: il matching avviene internamente
/// tramite il calcolo SHA-256 single-pass contro la lista dei candidati del manifesto.
/// [preferredArtifactId] può restringere i candidati preliminari ma non bypassa
/// la verifica crittografica.
@immutable
final class LocalArtifactImportRequest {
  final String operationId;
  final String localFilePath;
  final ValidatedCatalogCandidate candidate;

  /// Manifesto del catalogo usato per la pre-filtrazione per sizeBytes + magic.
  final CatalogManifest manifest;

  /// Hint opzionale per disambiguare tra più candidati compatibili per dimensione.
  /// Se specificato, restringe la lista dei candidati prima del calcolo SHA-256,
  /// ma il hash viene sempre verificato.
  final String? preferredArtifactId;

  const LocalArtifactImportRequest({
    required this.operationId,
    required this.localFilePath,
    required this.candidate,
    required this.manifest,
    this.preferredArtifactId,
  });
}

/// Aggregato pubblico delle dipendenze infrastrutturali necessarie per la costruzione
/// di [ModelProvisioningService] tramite factory.
///
/// Tutte le dipendenze sono di tipo pubblico — il [SinglePassArtifactIngestionEngine]
/// e l'[ArtifactImportInspector] sono creati internamente dall'implementazione privata.
@immutable
final class ProvisioningEnvironment {
  final ArtifactDownloadEngine downloadEngine;
  final ProvisioningCoordinator coordinator;
  final DownloadCheckpointRepository checkpointRepository;
  final ProvisioningPathResolver pathResolver;
  final ProvisioningFileSystem fileSystem;
  final ProvisioningClock clock;

  const ProvisioningEnvironment({
    required this.downloadEngine,
    required this.coordinator,
    required this.checkpointRepository,
    required this.pathResolver,
    required this.fileSystem,
    this.clock = const SystemProvisioningClock(),
  });
}

/// Interfaccia pubblica del servizio di orchestrazione per l'acquisizione,
/// la verifica ed il provisioning dei modelli GGUF.
///
/// I tipi infrastrutturali concreti ([SinglePassArtifactIngestionEngine],
/// [ArtifactSourceOwnership]) non compaiono mai nella firma pubblica.
///
/// Costruzione tramite factory:
/// ```dart
/// final service = ModelProvisioningService(environment: myEnvironment);
/// ```
abstract interface class ModelProvisioningService {
  /// Costruisce il servizio applicativo dall'aggregato [ProvisioningEnvironment].
  /// L'implementazione crea internamente l'engine di ingestione e l'inspector.
  factory ModelProvisioningService({
    required ProvisioningEnvironment environment,
  }) = _DefaultModelProvisioningService;

  /// Esegue la pipeline completa per un modello remoto:
  /// Download Range → Ingestione & Verifica Single-Pass → Commit Atomico.
  Future<ProvisioningResult> provisionRemoteModel({
    required ProvisioningRequest request,
    required ValidatedCatalogCandidate candidate,
    required CatalogArtifact artifact,
    ProvisioningCancellationToken? cancellationToken,
    void Function(double progressFraction)? onProgress,
  });

  /// Ispeziona ed importa un file GGUF locale dell'utente preservando il file sorgente.
  ///
  /// Il matching avviene in tre fasi:
  /// 1. Pre-filtro per `sizeBytes` + magic GGUF tramite inspector.
  /// 2. Single-pass: copia in staging temp + calcolo SHA-256.
  /// 3. Matching finale: selezione del candidato con `sha256` coincidente.
  ///
  /// Esiti:
  /// - `0 match` → [ProvisioningFailureReason.artifactNotVerified]
  /// - `>1 match` → [ProvisioningFailureReason.installationConflict]
  /// - `1 match` → commit atomico
  Future<ProvisioningResult> importLocalModel({
    required LocalArtifactImportRequest importRequest,
    ProvisioningCancellationToken? cancellationToken,
  });

  /// Ispeziona un file GGUF locale e restituisce i candidati compatibili per dimensione e formato.
  /// Metodo applicativo alternativo all'esposizione diretta dell'[ArtifactImportInspector].
  Future<LocalGgufInspectionResult> inspectLocalArtifact({
    required String filePath,
    required CatalogManifest manifest,
  });
}

/// Implementazione privata del servizio di orchestrazione del provisioning modelli.
/// Costruisce internamente [SinglePassArtifactIngestionEngine] e [ArtifactImportInspector].
final class _DefaultModelProvisioningService
    implements ModelProvisioningService {
  final ArtifactDownloadEngine _downloadEngine;
  final SinglePassArtifactIngestionEngine _ingestionEngine;
  final ProvisioningCoordinator _coordinator;
  final ArtifactImportInspector _importInspector;
  final DownloadCheckpointRepository _checkpointRepository;
  final ProvisioningClock _clock;

  _DefaultModelProvisioningService({
    required ProvisioningEnvironment environment,
  })  : _downloadEngine = environment.downloadEngine,
        _coordinator = environment.coordinator,
        _checkpointRepository = environment.checkpointRepository,
        _clock = environment.clock,
        _ingestionEngine = SinglePassArtifactIngestionEngine(
          fileSystem: environment.fileSystem,
          pathResolver: environment.pathResolver,
          clock: environment.clock,
        ),
        _importInspector = ArtifactImportInspector(
          fileSystem: environment.fileSystem,
        );

  @override
  Future<LocalGgufInspectionResult> inspectLocalArtifact({
    required String filePath,
    required CatalogManifest manifest,
  }) =>
      _importInspector.inspectLocalFile(
        filePath: filePath,
        manifest: manifest,
      );

  @override
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

  @override
  Future<ProvisioningResult> importLocalModel({
    required LocalArtifactImportRequest importRequest,
    ProvisioningCancellationToken? cancellationToken,
  }) async {
    // 1. Pre-filtro per sizeBytes + magic GGUF tramite inspector
    final inspectionResult = await _importInspector.inspectLocalFile(
      filePath: importRequest.localFilePath,
      manifest: importRequest.manifest,
    );

    if (!inspectionResult.isGgufHeaderValid) {
      return ProvisioningResult.failure(
        operationId: importRequest.operationId,
        artifactId: importRequest.preferredArtifactId ?? 'unknown',
        sourceKind: ProvisioningSourceKind.localImport,
        failureReason: ProvisioningFailureReason.artifactNotVerified,
        sanitizedMessage:
            'Il file non è un artefatto GGUF valido (magic header non riconosciuto).',
      );
    }

    if (inspectionResult.candidateArtifacts.isEmpty) {
      return ProvisioningResult.failure(
        operationId: importRequest.operationId,
        artifactId: importRequest.preferredArtifactId ?? 'unknown',
        sourceKind: ProvisioningSourceKind.localImport,
        failureReason: ProvisioningFailureReason.artifactNotVerified,
        sanitizedMessage:
            'Nessun artefatto del catalogo compatibile per dimensione (${inspectionResult.sizeBytes} B).',
      );
    }

    // 2. Converti candidati in snapshot di provenienza autenticati
    final candidateSnapshots = inspectionResult.candidateArtifacts
        .map(
          (a) => CatalogArtifactSnapshot.fromCandidate(
            candidate: importRequest.candidate,
            artifact: a,
            acquiredAtUtc: _clock.nowUtc(),
          ),
        )
        .toList();

    // 3. Single-pass con matching post-hash sulla lista di candidati
    try {
      cancellationToken?.throwIfCancelled();

      final preparedInstallation = await _ingestionEngine.ingestLocalArtifact(
        sourceFilePath: importRequest.localFilePath,
        operationId: importRequest.operationId,
        candidateSnapshots: candidateSnapshots,
        preferredArtifactId: importRequest.preferredArtifactId,
        cancellationToken: cancellationToken,
      );

      // 4. Commit atomico nel coordinator
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
          artifactId: importRequest.preferredArtifactId ?? 'unknown',
          sourceKind: ProvisioningSourceKind.localImport,
          failureReason: ProvisioningFailureReason.operationCancelled,
          sanitizedMessage: 'Importazione locale annullata.',
        );
      }
      if (e is ProvisioningException) {
        return ProvisioningResult.failure(
          operationId: importRequest.operationId,
          artifactId: importRequest.preferredArtifactId ?? 'unknown',
          sourceKind: ProvisioningSourceKind.localImport,
          failureReason: e.reason,
          sanitizedMessage: e.message,
        );
      }
      rethrow;
    }
  }
}
