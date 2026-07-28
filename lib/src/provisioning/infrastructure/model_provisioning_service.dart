import 'package:meta/meta.dart';

import '../domain/catalog_artifact_snapshot.dart';
import '../domain/catalog_manifest.dart';
import '../domain/download_cancellation_token.dart';
import '../domain/download_request.dart';
import '../domain/installation_record.dart';
import '../domain/model_lifecycle_models.dart';
import '../domain/provisioning_cancellation_token.dart';
import '../domain/provisioning_clock.dart';
import '../domain/provisioning_options.dart';
import '../domain/release_version_comparer.dart';
import '../domain/validated_catalog_candidate.dart';
import '../validation/artifact_import_inspector.dart';
import '../validation/installed_artifact_verifier.dart';
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

  /// Hint opzionale per disambiguare tra più candidati compatibili per dimensione.
  /// Se specificato, restringe la lista dei candidati prima del calcolo SHA-256,
  /// ma il hash viene sempre verificato.
  final String? preferredArtifactId;

  const LocalArtifactImportRequest({
    required this.operationId,
    required this.localFilePath,
    required this.candidate,
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

  /// Ripara un'installazione esistente preservando l'installationId originale.
  Future<ModelRepairResult> repairModel({
    required RepairModelRequest request,
    ProvisioningCancellationToken? cancellationToken,
    void Function(double progressFraction)? onProgress,
  });

  /// Verifica ed aggiorna un modello rispetto ad un candidato di catalogo,
  /// conservando l'installazione precedente per consentire il rollback.
  Future<ModelUpdateResult> updateModel({
    required UpdateModelRequest request,
    ProvisioningCancellationToken? cancellationToken,
    void Function(double progressFraction)? onProgress,
  });

  /// Esegue il rollback dell'attivazione verso un'installazione precedente verified.
  Future<ModelRollbackResult> rollbackModel({
    required RollbackModelRequest request,
  });

  /// Esegue la rimozione sicura (purge) di un'installazione con gestione compensata delle policy attive.
  Future<ModelPurgeResult> purgeInstallation({
    required PurgeInstallationRequest request,
  });

  /// Esegue la riconciliazione delle transazioni di ciclo di vita (state machine 6.4e).
  Future<ModelLifecycleReconciliationResult> reconcileLifecycleTransactions();
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
  final ProvisioningFileSystem _fileSystem;
  final ProvisioningPathResolver _pathResolver;

  _DefaultModelProvisioningService({
    required ProvisioningEnvironment environment,
  })  : _downloadEngine = environment.downloadEngine,
        _coordinator = environment.coordinator,
        _checkpointRepository = environment.checkpointRepository,
        _clock = environment.clock,
        _fileSystem = environment.fileSystem,
        _pathResolver = environment.pathResolver,
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

    // Conversione ed addebito del token di cancellazione per l'engine di download
    DownloadCancellationToken? downloadCancellationToken;
    if (cancellationToken != null) {
      downloadCancellationToken = DownloadCancellationToken();
      if (cancellationToken.isCancellationRequested) {
        downloadCancellationToken
            .cancel('Operazione di provisioning annullata.');
      } else {
        cancellationToken.whenCancelled.then((_) {
          downloadCancellationToken
              ?.cancel('Operazione di provisioning annullata.');
        });
      }
    }

    final downloadResult = await _downloadEngine.downloadArtifact(
      request: downloadRequest,
      cancellationToken: downloadCancellationToken,
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
      manifest: importRequest.candidate.manifest,
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
      return ProvisioningResult.failure(
        operationId: importRequest.operationId,
        artifactId: importRequest.preferredArtifactId ?? 'unknown',
        sourceKind: ProvisioningSourceKind.localImport,
        failureReason: ProvisioningFailureReason.installationRecordWriteFailed,
        sanitizedMessage: 'Errore imprevisto durante l\'importazione locale.',
      );
    }
  }

  @override
  Future<ModelRepairResult> repairModel({
    required RepairModelRequest request,
    ProvisioningCancellationToken? cancellationToken,
    void Function(double progressFraction)? onProgress,
  }) async {
    final record = await _coordinator.getInstallationRecord();
    final targetDescriptor =
        record.findInstallation(request.targetInstallationId);

    if (targetDescriptor == null) {
      return ModelRepairResult(
        operationId: request.operationId,
        artifactId: 'unknown',
        installationId: request.targetInstallationId,
        status: ModelRepairStatus.repairMetadataMissing,
        failureReason: ProvisioningFailureReason.installationRecordReadFailed,
        message:
            'Installazione target "${request.targetInstallationId}" non trovata nel registro.',
      );
    }

    final verifier = LocalInstalledArtifactVerifier(fileSystem: _fileSystem);
    final isHealthy = await verifier.verifyPhysicalIntegrity(
      targetDescriptor,
      pathResolver: _pathResolver,
    );

    if (isHealthy) {
      return ModelRepairResult(
        operationId: request.operationId,
        artifactId: targetDescriptor.artifactId,
        installationId: request.targetInstallationId,
        status: ModelRepairStatus.noRepairNeeded,
        filesystemCommitted: true,
        recordCommitted: true,
        activationCommitted: true,
      );
    }

    if (request.candidate == null) {
      return ModelRepairResult(
        operationId: request.operationId,
        artifactId: targetDescriptor.artifactId,
        installationId: request.targetInstallationId,
        status: ModelRepairStatus.repairSourceUnavailable,
        failureReason: ProvisioningFailureReason.invalidSourceUri,
        message:
            'Candidato di catalogo non fornito per riscaricare l\'artefatto danneggiato.',
      );
    }

    CatalogArtifact? catalogArtifact;
    if (request.candidate != null) {
      for (final candArt in request.candidate!.manifest.artifacts) {
        if (candArt.artifactId == targetDescriptor.artifactId &&
            candArt.version == targetDescriptor.version &&
            candArt.buildId == targetDescriptor.buildId &&
            candArt.sha256.toLowerCase() ==
                targetDescriptor.sha256.toLowerCase() &&
            candArt.sizeBytes == targetDescriptor.sizeBytes) {
          catalogArtifact = candArt;
          break;
        }
      }
      catalogArtifact ??=
          request.candidate!.manifest.findArtifact(targetDescriptor.artifactId);
    }

    if (catalogArtifact == null || catalogArtifact.downloadUri == null) {
      return ModelRepairResult(
        operationId: request.operationId,
        artifactId: targetDescriptor.artifactId,
        installationId: request.targetInstallationId,
        status: ModelRepairStatus.repairSourceUnavailable,
        failureReason: ProvisioningFailureReason.artifactIdNotFound,
        message:
            'URI di download non disponibile nel manifesto per la riparazione.',
      );
    }

    final downloadRequest = DownloadRequest(
      operationId: request.operationId,
      artifactId: catalogArtifact.artifactId,
      sourceUri: Uri.parse(catalogArtifact.downloadUri!),
      expectedSizeBytes: catalogArtifact.sizeBytes,
    );

    DownloadCancellationToken? downloadToken;
    if (cancellationToken != null) {
      downloadToken = DownloadCancellationToken();
      if (cancellationToken.isCancellationRequested) {
        downloadToken.cancel('Riparazione annullata.');
      } else {
        cancellationToken.whenCancelled.then((_) {
          downloadToken?.cancel('Riparazione annullata.');
        });
      }
    }

    final downloadResult = await _downloadEngine.downloadArtifact(
      request: downloadRequest,
      cancellationToken: downloadToken,
      onProgress: (p) => onProgress?.call(p.fraction),
    );

    if (downloadResult.isFailure) {
      return ModelRepairResult(
        operationId: request.operationId,
        artifactId: targetDescriptor.artifactId,
        installationId: request.targetInstallationId,
        status: ModelRepairStatus.failed,
        failureReason: ProvisioningFailureReason.downloadNotAllowed,
        message: downloadResult.message ??
            'Errore durante il download per riparazione.',
      );
    }

    final provenanceSnapshot = CatalogArtifactSnapshot.fromCandidate(
      candidate: request.candidate!,
      artifact: catalogArtifact,
      acquiredAtUtc: _clock.nowUtc(),
    );

    final prepared = await _ingestionEngine.ingestAndVerifyToTemporaryStore(
      sourceFilePath: downloadResult.stagingArtifact!.stagingPath,
      operationId: request.operationId,
      provenanceSnapshot: provenanceSnapshot,
      sourceOwnership: ArtifactSourceOwnership.managedStaging,
      cancellationToken: cancellationToken,
    );

    return await _coordinator.repairVerifiedArtifact(
      targetInstallationId: request.targetInstallationId,
      replacement: prepared,
      operationId: request.operationId,
    );
  }

  @override
  Future<ModelUpdateResult> updateModel({
    required UpdateModelRequest request,
    ProvisioningCancellationToken? cancellationToken,
    void Function(double progressFraction)? onProgress,
  }) async {
    // ------------------------------------------------------------------------
    // FASE 1 (UN-LOCKED): Lettura snapshot, verifica SemVer e Ingestione Staging
    // ------------------------------------------------------------------------
    final record = await _coordinator.getInstallationRecord();
    final activationState = await _coordinator.getActivationState();

    final precondition = LifecyclePrecondition.capture(
      artifactId: request.artifactId,
      record: record,
      activationState: activationState,
      role: request.modelRole,
    );

    final installedList =
        record.findInstallationsForArtifact(request.artifactId);

    CatalogArtifactSnapshot? latestInstalledSnapshot;
    for (final inst in installedList) {
      if (inst.status == InstallationStatus.verified) {
        final snap = inst.toSnapshot(_clock.nowUtc());
        if (latestInstalledSnapshot == null ||
            ReleaseVersionComparer.compareSnapshots(
                  current: latestInstalledSnapshot,
                  candidate: snap,
                ) <
                0) {
          latestInstalledSnapshot = snap;
        }
      }
    }

    final candidateArtifact =
        request.candidate.manifest.findArtifact(request.artifactId);
    if (candidateArtifact == null || candidateArtifact.downloadUri == null) {
      return ModelUpdateResult(
        operationId: request.operationId,
        artifactId: request.artifactId,
        status: ModelUpdateStatus.updateConflict,
        failureReason: ProvisioningFailureReason.artifactIdNotFound,
        message:
            'Artefatto per l\'aggiornamento non trovato nel candidato catalogo.',
      );
    }

    if (latestInstalledSnapshot != null) {
      final isNewer = ReleaseVersionComparer.compareSnapshotWithArtifact(
        current: latestInstalledSnapshot,
        candidateArtifact: candidateArtifact,
        candidateCatalogRevision: request.candidate.catalogRevision,
      );

      if (isNewer <= 0) {
        return ModelUpdateResult(
          operationId: request.operationId,
          artifactId: request.artifactId,
          status: ModelUpdateStatus.alreadyLatest,
          message:
              'L\'installazione corrente è già aggiornata alla release più recente.',
        );
      }
    }

    // Download in streaming sbloccato (Phase 1)
    final downloadRequest = DownloadRequest(
      operationId: request.operationId,
      artifactId: candidateArtifact.artifactId,
      sourceUri: Uri.parse(candidateArtifact.downloadUri!),
      expectedSizeBytes: candidateArtifact.sizeBytes,
    );

    DownloadCancellationToken? downloadToken;
    if (cancellationToken != null) {
      downloadToken = DownloadCancellationToken();
      if (cancellationToken.isCancellationRequested) {
        downloadToken.cancel('Aggiornamento annullato.');
      } else {
        cancellationToken.whenCancelled.then((_) {
          downloadToken?.cancel('Aggiornamento annullato.');
        });
      }
    }

    final downloadResult = await _downloadEngine.downloadArtifact(
      request: downloadRequest,
      cancellationToken: downloadToken,
      onProgress: (p) => onProgress?.call(p.fraction),
    );

    if (downloadResult.isFailure) {
      return ModelUpdateResult(
        operationId: request.operationId,
        artifactId: request.artifactId,
        status: ModelUpdateStatus.failed,
        failureReason: ProvisioningFailureReason.downloadNotAllowed,
        message: downloadResult.message ??
            'Errore durante il download dell\'aggiornamento.',
      );
    }

    final provenanceSnapshot = CatalogArtifactSnapshot.fromCandidate(
      candidate: request.candidate,
      artifact: candidateArtifact,
      acquiredAtUtc: _clock.nowUtc(),
    );

    final preparedArtifact =
        await _ingestionEngine.ingestAndVerifyToTemporaryStore(
      sourceFilePath: downloadResult.stagingArtifact!.stagingPath,
      operationId: request.operationId,
      provenanceSnapshot: provenanceSnapshot,
      sourceOwnership: ArtifactSourceOwnership.managedStaging,
      cancellationToken: cancellationToken,
    );

    // ------------------------------------------------------------------------
    // FASE 2 (LOCKED): Commit atomico e verifica delle LifecyclePrecondition
    // ------------------------------------------------------------------------
    return await _coordinator.commitLifecycleUpdate(
      operationId: request.operationId,
      artifactId: request.artifactId,
      modelRole: request.modelRole,
      preparedArtifact: preparedArtifact,
      activationPolicy: request.activationPolicy,
      precondition: precondition,
    );
  }

  @override
  Future<ModelRollbackResult> rollbackModel({
    required RollbackModelRequest request,
  }) =>
      _coordinator.rollbackInstallation(
        operationId: request.operationId,
        artifactId: request.artifactId,
        modelRole: request.modelRole,
        targetInstallationId: request.targetInstallationId,
        expectedCurrentInstallationId: request.expectedCurrentInstallationId,
      );

  @override
  Future<ModelPurgeResult> purgeInstallation({
    required PurgeInstallationRequest request,
  }) =>
      _coordinator.purgeInstallation(
        operationId: request.operationId,
        installationId: request.installationId,
        activePurgePolicy: request.activePurgePolicy,
      );

  @override
  Future<ModelLifecycleReconciliationResult> reconcileLifecycleTransactions() =>
      _coordinator.reconcileLifecycleTransactions();
}
