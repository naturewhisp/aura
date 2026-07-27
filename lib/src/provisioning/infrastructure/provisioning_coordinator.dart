import 'dart:async';
import 'dart:convert';
import '../domain/activation_state.dart';
import '../domain/catalog_manifest.dart';
import '../domain/installation_record.dart';
import '../domain/provisioning_cancellation_token.dart';
import '../domain/provisioning_clock.dart';
import '../domain/provisioning_options.dart';
import '../validation/installed_artifact_verifier.dart';
import 'activation_state_repository.dart';
import 'artifact_ingestion_engine.dart';
import 'download_checkpoint_repository.dart';
import 'installation_id_generator.dart';
import 'installation_record_repository.dart';
import 'provisioning_file_system.dart';
import 'provisioning_lock.dart';
import 'provisioning_path_resolver.dart';
import 'single_pass_artifact_ingestion_engine.dart';

/// Coordinatore centrale per l'orchestrazione del provisioning, la verifica dell'integrità fisica/hash, l'attivazione per installationId ed i rollback verificati.
final class ProvisioningCoordinator {
  static const String _lockKey = 'provisioning_lifecycle';

  final ProvisioningLock _lock;
  final InstallationRecordRepository _recordRepository;
  final ActivationStateRepository _activationRepository;
  final ArtifactIngestionEngine _ingestionEngine;
  final ProvisioningPathResolver _pathResolver;
  final ProvisioningFileSystem _fileSystem;
  final ProvisioningClock _clock;
  final InstalledArtifactVerifier _verifier;
  final InstallationIdGenerator _idGenerator;

  ProvisioningCoordinator({
    required ProvisioningLock lock,
    required InstallationRecordRepository recordRepository,
    required ActivationStateRepository activationRepository,
    required ArtifactIngestionEngine ingestionEngine,
    required ProvisioningPathResolver pathResolver,
    ProvisioningFileSystem fileSystem = const LocalProvisioningFileSystem(),
    ProvisioningClock clock = const SystemProvisioningClock(),
    InstalledArtifactVerifier? verifier,
    InstallationIdGenerator? idGenerator,
  })  : _lock = lock,
        _recordRepository = recordRepository,
        _activationRepository = activationRepository,
        _ingestionEngine = ingestionEngine,
        _pathResolver = pathResolver,
        _fileSystem = fileSystem,
        _clock = clock,
        _verifier =
            verifier ?? LocalInstalledArtifactVerifier(fileSystem: fileSystem),
        _idGenerator = idGenerator ?? MonotonicInstallationIdGenerator();

  /// Acquisisce ed installa un artefatto da catalogo, riconcilia lo stato fisico/registro ed aggiorna atomicamente il registro sotto lock.
  Future<ProvisioningResult> provisionArtifact({
    required ProvisioningRequest request,
    required CatalogManifest manifest,
    ProvisioningCancellationToken? cancellationToken,
  }) async {
    return _lock.synchronized(_lockKey, () async {
      cancellationToken?.throwIfCancelled();

      // 1. Risoluzione dell'artefatto nel catalogo
      final artifact = manifest.findArtifact(request.artifactId);
      if (artifact == null) {
        return ProvisioningResult.failure(
          operationId: request.operationId,
          artifactId: request.artifactId,
          sourceKind: ProvisioningSourceKind.bundled,
          failureReason: ProvisioningFailureReason.artifactIdNotFound,
          sanitizedMessage: 'Artefatto non trovato nel catalogo.',
        );
      }

      final sourceKind = switch (artifact.sourceKind) {
        CatalogArtifactSourceKind.bundled => ProvisioningSourceKind.bundled,
        CatalogArtifactSourceKind.remoteHttps =>
          ProvisioningSourceKind.remoteHttps,
        CatalogArtifactSourceKind.localImport =>
          ProvisioningSourceKind.localImport,
      };

      final targetInstallPath =
          _pathResolver.resolveInstalledArtifactPath(artifact);
      final relativeInstallPath = _pathResolver.resolveRelativeInstallPath(
        artifactType: artifact.artifactType,
        artifactId: artifact.artifactId,
        buildOrVersionId: artifact.version == artifact.buildId
            ? artifact.version
            : '${artifact.version}_${artifact.buildId}',
      );

      // 2. Controllo idempotenza congiunto: fingerprint completo (artifactId, version, buildId, sha256, sizeBytes) e verifica fisica
      final currentRecord = await _recordRepository.readRecord();
      final latestDescriptor =
          currentRecord.findLatestVerifiedInstallation(artifact.artifactId);

      if (latestDescriptor != null &&
          latestDescriptor.version == artifact.version &&
          !latestDescriptor.matchesArtifact(artifact)) {
        // Conflitto di fingerprint per la stessa versione: rifiuta invece di tentare l'ingestione su target occupato
        if (await _fileSystem.directoryExists(targetInstallPath) ||
            await _fileSystem.fileExists(targetInstallPath)) {
          return ProvisioningResult.failure(
            operationId: request.operationId,
            artifactId: artifact.artifactId,
            sourceKind: sourceKind,
            failureReason: ProvisioningFailureReason.installationConflict,
            sanitizedMessage:
                'Conflitto di identità nel catalogo: esiste già un\'installazione della stessa versione ma con fingerprint differente.',
          );
        }
      }

      if (latestDescriptor != null &&
          latestDescriptor.matchesArtifact(artifact) &&
          latestDescriptor.status == InstallationStatus.verified) {
        final isIntegrityValid = await _verifier.verifyPhysicalIntegrity(
          latestDescriptor,
          pathResolver: _pathResolver,
        );

        if (isIntegrityValid) {
          return ProvisioningResult.success(
            operationId: request.operationId,
            artifactId: artifact.artifactId,
            installationId: latestDescriptor.installationId,
            sourceKind: sourceKind,
            bytesProcessed: latestDescriptor.sizeBytes,
            alreadyInstalled: true,
          );
        } else {
          // File fisici o hash corrotti/assenti -> Pulizia fisica sicura prima della reinstallazione
          await _fileSystem.deleteDirectoryBestEffort(targetInstallPath);
          await _fileSystem.deleteFileBestEffort(targetInstallPath);

          final isPhysicallyClean =
              !await _fileSystem.directoryExists(targetInstallPath) &&
                  !await _fileSystem.fileExists(targetInstallPath);

          if (!isPhysicallyClean) {
            return ProvisioningResult.failure(
              operationId: request.operationId,
              artifactId: artifact.artifactId,
              sourceKind: sourceKind,
              failureReason: ProvisioningFailureReason.cleanupFailed,
              sanitizedMessage:
                  'Impossibile rimuovere l\'installazione fisica corrotta preesistente prima della reinstallazione.',
            );
          }

          // Riconciliazione nel registro marcando il vecchio descriptor come removed
          await _recordRepository.updateRecord(
            (record) =>
                record.removeInstallation(latestDescriptor.installationId),
          );
        }
      }

      cancellationToken?.throwIfCancelled();

      // 3. Esecuzione dell'ingestione fisica tramite ArtifactIngestionEngine
      final ingestionResult = await _ingestionEngine.ingestArtifact(
        request: request,
        manifest: manifest,
        cancellationToken: cancellationToken,
      );

      if (ingestionResult.status == ProvisioningStatus.failed) {
        return ingestionResult;
      }

      cancellationToken?.throwIfCancelled();

      // 4. Generazione monotona dell'installationId con clock letto una sola volta tramite _idGenerator
      final nowUtc = _clock.nowUtc().toUtc();
      final nowIso = nowUtc.toIso8601String();
      final installationId = _idGenerator.generateId(
        artifact: artifact,
        timestampUtc: nowUtc,
      );

      final newDescriptor = InstalledArtifactDescriptor(
        installationId: installationId,
        artifactId: artifact.artifactId,
        artifactType: artifact.artifactType,
        displayName: artifact.displayName,
        version: artifact.version,
        buildId: artifact.buildId,
        platform: artifact.platform,
        architecture: artifact.architecture,
        relativeInstallPath: relativeInstallPath,
        entryFileName: artifact.compression == CatalogCompressionFormat.none
            ? artifact.fileName
            : null,
        installedAt: nowIso,
        verifiedAt: nowIso,
        sizeBytes: artifact.sizeBytes,
        sha256: artifact.sha256,
        sourceKind: artifact.sourceKind,
        status: InstallationStatus.verified,
      );

      // 5. Scrittura transazionale nel registro sotto lock con compensazione fisica verificata su fallimento
      try {
        await _recordRepository.updateRecord(
          (record) => record.upsertArtifact(newDescriptor),
        );
      } catch (e) {
        final deletedDir =
            await _fileSystem.deleteDirectoryBestEffort(targetInstallPath);
        final deletedFile =
            await _fileSystem.deleteFileBestEffort(targetInstallPath);

        final isPhysicallyRemoved =
            !await _fileSystem.directoryExists(targetInstallPath) &&
                !await _fileSystem.fileExists(targetInstallPath);

        final String message = isPhysicallyRemoved
            ? ((deletedDir || deletedFile)
                ? 'Aggiornamento del registro fallito. Compensazione fisica completata con successo.'
                : 'Aggiornamento del registro fallito. Destinazione già priva di file fisici.')
            : 'Aggiornamento del registro fallito. Tentativo di compensazione fisica fallito; file orfani presenti su disco.';

        return ProvisioningResult.failure(
          operationId: request.operationId,
          artifactId: artifact.artifactId,
          sourceKind: sourceKind,
          failureReason: ProvisioningFailureReason.unexpectedState,
          sanitizedMessage: message,
          rollbackPerformed: isPhysicallyRemoved,
          cleanupSucceeded: isPhysicallyRemoved,
        );
      }

      return ProvisioningResult.success(
        operationId: request.operationId,
        artifactId: artifact.artifactId,
        installationId: installationId,
        sourceKind: sourceKind,
        bytesProcessed: ingestionResult.bytesProcessed,
        alreadyInstalled: false,
      );
    });
  }

  /// Registra ed installa atomicamente un artefatto già verificato in single-pass nello store gestito.
  Future<ProvisioningResult> registerVerifiedArtifact({
    required PreparedArtifactInstallation installation,
    required String operationId,
    DownloadCheckpointRepository? checkpointRepository,
    ProvisioningCancellationToken? cancellationToken,
  }) async {
    return _lock.synchronized(_lockKey, () async {
      final provenance = installation.provenance;
      final finalPath = installation.finalInstallPath;
      final tempPath = installation.temporaryInstallPath;

      final sourceKind =
          installation.sourceOwnership == ArtifactSourceOwnership.userOwnedFile
              ? ProvisioningSourceKind.localImport
              : ProvisioningSourceKind.remoteHttps;

      // 1. Controllo Idempotenza e Conflitti sulla destinazione finale
      final currentRecord = await _recordRepository.readRecord();
      final existingDescriptor =
          currentRecord.findLatestVerifiedInstallation(provenance.artifactId);

      if (existingDescriptor != null &&
          existingDescriptor.version == provenance.artifactVersion &&
          existingDescriptor.buildId == provenance.buildId) {
        if (existingDescriptor.sha256.toLowerCase() ==
                provenance.sha256.toLowerCase() &&
            existingDescriptor.sizeBytes == provenance.sizeBytes) {
          // Idempotente no-op: cancella temp e restituisce già installato
          await _fileSystem.deleteDirectoryBestEffort(tempPath);
          return ProvisioningResult.success(
            operationId: operationId,
            artifactId: provenance.artifactId,
            installationId: existingDescriptor.installationId,
            sourceKind: sourceKind,
            bytesProcessed: existingDescriptor.sizeBytes,
            alreadyInstalled: true,
          );
        } else {
          // Conflitto di fingerprint per la stessa versione
          await _fileSystem.deleteDirectoryBestEffort(tempPath);
          return ProvisioningResult.failure(
            operationId: operationId,
            artifactId: provenance.artifactId,
            sourceKind: sourceKind,
            failureReason: ProvisioningFailureReason.installationConflict,
            sanitizedMessage:
                'Conflitto di installazione: esiste già un\'installazione della stessa versione ma con fingerprint differente.',
          );
        }
      }

      // 2. Controllo del cancellation token tassativamente PRIMA dell'invocazione del rename atomico
      if (cancellationToken?.isCancellationRequested == true) {
        await _fileSystem.deleteDirectoryBestEffort(tempPath);
        return ProvisioningResult.failure(
          operationId: operationId,
          artifactId: provenance.artifactId,
          sourceKind: sourceKind,
          failureReason: ProvisioningFailureReason.operationCancelled,
          sanitizedMessage: 'Operazione annullata prima del rename atomico.',
        );
      }

      // 3. COMMIT POINT: Rename atomico della directory temporanea -> finale
      await _fileSystem.deleteDirectoryBestEffort(finalPath);
      await _fileSystem.renameDirectoryWithoutFallback(tempPath, finalPath);

      // Da questo punto l'installazione è irrevocabilmente COMMITTED.
      final nowUtc = _clock.nowUtc();
      final nowIso = nowUtc.toIso8601String();
      final installationId = _idGenerator.generateId(
        artifact: CatalogArtifact(
          artifactId: provenance.artifactId,
          artifactType: CatalogArtifactType.model,
          displayName: provenance.artifactId,
          version: provenance.artifactVersion,
          buildId: provenance.buildId,
          platform: 'all',
          architecture: 'gguf',
          fileName: provenance.fileName,
          sourceKind: CatalogArtifactSourceKind.remoteHttps,
          sizeBytes: provenance.sizeBytes,
          sha256: provenance.sha256,
          license: 'unknown',
        ),
        timestampUtc: nowUtc,
      );

      final relativeInstallPath = _pathResolver.resolveRelativeInstallPath(
        artifactType: CatalogArtifactType.model,
        artifactId: provenance.artifactId,
        buildOrVersionId: provenance.artifactVersion == provenance.buildId
            ? provenance.artifactVersion
            : '${provenance.artifactVersion}_${provenance.buildId}',
      );

      final newDescriptor = InstalledArtifactDescriptor(
        installationId: installationId,
        artifactId: provenance.artifactId,
        artifactType: CatalogArtifactType.model,
        displayName: provenance.artifactId,
        version: provenance.artifactVersion,
        buildId: provenance.buildId,
        platform: 'all',
        architecture: 'gguf',
        relativeInstallPath: relativeInstallPath,
        entryFileName: provenance.fileName,
        installedAt: nowIso,
        verifiedAt: nowIso,
        sizeBytes: provenance.sizeBytes,
        sha256: provenance.sha256,
        sourceKind: CatalogArtifactSourceKind.remoteHttps,
        status: InstallationStatus.verified,
      );

      bool indexUpdated = false;
      try {
        await _recordRepository.updateRecord(
          (record) => record.upsertArtifact(newDescriptor),
        );
        indexUpdated = true;
      } catch (_) {
        indexUpdated = false;
      }

      bool cleanupDone = true;
      if (installation.sourceOwnership ==
          ArtifactSourceOwnership.managedStaging) {
        try {
          await _fileSystem.deleteFileBestEffort(installation.sourcePath);
          if (checkpointRepository != null) {
            await checkpointRepository.deleteCheckpoint(operationId);
          }
        } catch (_) {
          cleanupDone = false;
        }
      }

      final Map<String, dynamic> diagnostics = {
        'indexUpdated': indexUpdated,
        'cleanupDone': cleanupDone,
      };

      return ProvisioningResult(
        operationId: operationId,
        artifactId: provenance.artifactId,
        status: ProvisioningStatus.success,
        installationId: installationId,
        installed: true,
        alreadyInstalled: false,
        activated: false,
        verified: true,
        bytesProcessed: provenance.sizeBytes,
        sourceKind: sourceKind,
        rollbackPerformed: false,
        cleanupSucceeded: cleanupDone,
        sanitizedDiagnostics: diagnostics,
      );
    });
  }

  /// Scansiona lo store gestito (%LOCALAPPDATA%\AURA\models\) ed indicizza le installazioni committed con commit.marker che non compaiono nell'indice globale.
  Future<int> reconcileUnindexedInstallations() async {
    return _lock.synchronized(_lockKey, () async {
      final modelsRoot = '${_pathResolver.appManagedRoot}\\models';
      if (!await _fileSystem.directoryExists(modelsRoot)) return 0;

      int reconciledCount = 0;
      final currentRecord = await _recordRepository.readRecord();

      final artifactDirs = await _fileSystem.listDirectory(modelsRoot);
      for (final artifactSub in artifactDirs) {
        final artifactDir = '$modelsRoot\\$artifactSub';
        final versionDirs = await _fileSystem.listDirectory(artifactDir);
        for (final versionSub in versionDirs) {
          final versionDir = '$artifactDir\\$versionSub';
          final markerPath = '$versionDir\\commit.marker';
          final recordPath = '$versionDir\\installation_record.json';

          if (await _fileSystem.fileExists(markerPath) &&
              await _fileSystem.fileExists(recordPath)) {
            try {
              final markerRaw = await _fileSystem.readAsString(markerPath);
              final recordRaw = await _fileSystem.readAsString(recordPath);

              final markerJson = jsonDecode(markerRaw) as Map<String, dynamic>;
              final recordJson = jsonDecode(recordRaw) as Map<String, dynamic>;

              final descriptor =
                  InstalledArtifactDescriptor.fromJson(recordJson);

              final markerArtifactId = markerJson['artifactId'] as String?;
              final markerSha256 = markerJson['sha256'] as String?;

              if (markerArtifactId == descriptor.artifactId &&
                  markerSha256?.toLowerCase() ==
                      descriptor.sha256.toLowerCase()) {
                final existing =
                    currentRecord.findInstallation(descriptor.installationId);
                if (existing == null) {
                  await _recordRepository.updateRecord(
                    (r) => r.upsertArtifact(descriptor),
                  );
                  reconciledCount++;
                }
              }
            } catch (_) {
              // Ignora cartelle orfane malformate
            }
          }
        }
      }

      return reconciledCount;
    });
  }

  /// Attiva un'installazione specifica riferita dal suo `installationId` sotto lock.
  /// Per gli artefatti di modello, richiede obbligatoriamente il parametro [modelRole] (actor o evaluator).
  Future<ActivationResult> activateInstallation({
    required String installationId,
    required String operationId,
    ModelActivationRole? modelRole,
    ProvisioningCancellationToken? cancellationToken,
  }) async {
    return _lock.synchronized(_lockKey, () async {
      if (cancellationToken?.isCancellationRequested == true) {
        return ActivationResult.failure(
          operationId: operationId,
          installationId: installationId,
          failureReason: ActivationFailureReason.operationCancelled,
          sanitizedMessage: 'Operazione di attivazione annullata.',
        );
      }

      final record = await _recordRepository.readRecord();
      final descriptor = record.findInstallation(installationId);

      if (descriptor == null) {
        return ActivationResult.failure(
          operationId: operationId,
          installationId: installationId,
          failureReason: ActivationFailureReason.installationNotFound,
          sanitizedMessage:
              'Installazione "$installationId" non trovata nel registro.',
        );
      }

      if (descriptor.status != InstallationStatus.verified) {
        return ActivationResult.failure(
          operationId: operationId,
          installationId: installationId,
          failureReason: ActivationFailureReason.installationNotVerified,
          sanitizedMessage: 'L\'installazione non è in stato verified.',
        );
      }

      final isIntegrityValid = await _verifier.verifyPhysicalIntegrity(
        descriptor,
        pathResolver: _pathResolver,
      );

      if (!isIntegrityValid) {
        return ActivationResult.failure(
          operationId: operationId,
          installationId: installationId,
          failureReason: ActivationFailureReason.integrityVerificationFailed,
          sanitizedMessage:
              'Verifica dell\'integrità fisica o dell\'hash fallita per il payload.',
        );
      }

      final isRuntime = descriptor.artifactType == CatalogArtifactType.runtime;

      if (isRuntime && modelRole != null) {
        return ActivationResult.failure(
          operationId: operationId,
          installationId: installationId,
          failureReason: ActivationFailureReason.invalidRole,
          sanitizedMessage:
              'Non è possibile specificare un modelRole per l\'attivazione di un runtime.',
        );
      }

      if (!isRuntime && modelRole == null) {
        return ActivationResult.failure(
          operationId: operationId,
          installationId: installationId,
          failureReason: ActivationFailureReason.roleRequired,
          sanitizedMessage:
              'Per attivare un artefatto di modello è necessario specificare modelRole (actor o evaluator).',
        );
      }

      final nowIso = _clock.nowUtc().toUtc().toIso8601String();
      final currentState = await _activationRepository.readState();

      ActivationState updatedState;
      if (isRuntime) {
        updatedState = currentState.copyWith(
          activeRuntimeInstallationId: descriptor.installationId,
          lastKnownGoodRuntimeInstallationId:
              currentState.activeRuntimeInstallationId ??
                  currentState.lastKnownGoodRuntimeInstallationId,
          updatedAt: nowIso,
        );
      } else if (modelRole == ModelActivationRole.actor) {
        updatedState = currentState.copyWith(
          activeActorModelInstallationId: descriptor.installationId,
          lastKnownGoodActorModelInstallationId:
              currentState.activeActorModelInstallationId ??
                  currentState.lastKnownGoodActorModelInstallationId,
          updatedAt: nowIso,
        );
      } else {
        updatedState = currentState.copyWith(
          activeEvaluatorModelInstallationId: descriptor.installationId,
          lastKnownGoodEvaluatorModelInstallationId:
              currentState.activeEvaluatorModelInstallationId ??
                  currentState.lastKnownGoodEvaluatorModelInstallationId,
          updatedAt: nowIso,
        );
      }

      try {
        await _activationRepository.replaceState(updatedState);
      } catch (e) {
        return ActivationResult.failure(
          operationId: operationId,
          installationId: installationId,
          failureReason: ActivationFailureReason.activationPersistenceFailed,
          sanitizedMessage: 'Scrittura dello stato di attivazione fallita.',
        );
      }

      return ActivationResult.success(
        operationId: operationId,
        installationId: installationId,
        activatedAt: nowIso,
      );
    });
  }

  /// Rimuove un'installazione specifica dal filesystem e dal registro di installazione sotto lock.
  /// Rifiuta tassativamente la rimozione diretta di un'installazione attualmente attiva per qualsiasi ruolo.
  Future<ProvisioningResult> removeInstallation({
    required String installationId,
    required String operationId,
  }) async {
    return _lock.synchronized(_lockKey, () async {
      final record = await _recordRepository.readRecord();
      final descriptor = record.findInstallation(installationId);

      if (descriptor == null) {
        return ProvisioningResult.failure(
          operationId: operationId,
          artifactId: installationId,
          sourceKind: ProvisioningSourceKind.bundled,
          failureReason: ProvisioningFailureReason.artifactIdNotFound,
          sanitizedMessage: 'Installazione non trovata nel registro.',
        );
      }

      // 1. Rifiuta la rimozione se l'installazione è attualmente attiva per qualsiasi ruolo (Actor, Evaluator o Runtime)
      final currentState = await _activationRepository.readState();
      if (currentState.activeRuntimeInstallationId ==
              descriptor.installationId ||
          currentState.activeActorModelInstallationId ==
              descriptor.installationId ||
          currentState.activeEvaluatorModelInstallationId ==
              descriptor.installationId) {
        return ProvisioningResult.failure(
          operationId: operationId,
          artifactId: descriptor.artifactId,
          sourceKind: ProvisioningSourceKind.bundled,
          failureReason: ProvisioningFailureReason.installationConflict,
          sanitizedMessage:
              'Impossibile rimuovere un\'installazione attualmente attiva. Disattivarla o selezionare un altro modello prima di rimuoverla.',
        );
      }

      final absolutePath = _pathResolver
          .resolveAppManagedRelativePath(descriptor.relativeInstallPath);

      // 2. Cancellazione fisica e verifica dell'effettiva assenza
      await _fileSystem.deleteDirectoryBestEffort(absolutePath);
      await _fileSystem.deleteFileBestEffort(absolutePath);

      final isPhysicallyRemoved =
          !await _fileSystem.directoryExists(absolutePath) &&
              !await _fileSystem.fileExists(absolutePath);

      if (!isPhysicallyRemoved) {
        return ProvisioningResult.failure(
          operationId: operationId,
          artifactId: descriptor.artifactId,
          sourceKind: ProvisioningSourceKind.bundled,
          failureReason: ProvisioningFailureReason.cleanupFailed,
          sanitizedMessage:
              'Impossibile rimuovere fisicamente i file dell\'installazione dal disco.',
        );
      }

      // 3. Aggiornamento del registro di installazione marcando lo stato removed
      try {
        await _recordRepository.updateRecord(
          (rec) => rec.removeInstallation(installationId),
        );
      } catch (e) {
        return ProvisioningResult.failure(
          operationId: operationId,
          artifactId: descriptor.artifactId,
          sourceKind: ProvisioningSourceKind.bundled,
          failureReason:
              ProvisioningFailureReason.installationRecordWriteFailed,
          sanitizedMessage:
              'Cancellazione fisica completata ma aggiornamento del registro di installazione fallito.',
          cleanupSucceeded: true,
          rollbackPerformed: true,
        );
      }

      // 4. Riconciliazione di ActivationState (pulizia di lastKnownGood se puntava all'installazione rimossa per ciascun ruolo)
      final needsLkgRuntimeClean =
          currentState.lastKnownGoodRuntimeInstallationId ==
              descriptor.installationId;
      final needsLkgActorClean =
          currentState.lastKnownGoodActorModelInstallationId ==
              descriptor.installationId;
      final needsLkgEvaluatorClean =
          currentState.lastKnownGoodEvaluatorModelInstallationId ==
              descriptor.installationId;

      if (needsLkgRuntimeClean ||
          needsLkgActorClean ||
          needsLkgEvaluatorClean) {
        final reconciledState = currentState.copyWith(
          lastKnownGoodRuntimeInstallationId: needsLkgRuntimeClean
              ? null
              : currentState.lastKnownGoodRuntimeInstallationId,
          lastKnownGoodActorModelInstallationId: needsLkgActorClean
              ? null
              : currentState.lastKnownGoodActorModelInstallationId,
          lastKnownGoodEvaluatorModelInstallationId: needsLkgEvaluatorClean
              ? null
              : currentState.lastKnownGoodEvaluatorModelInstallationId,
          updatedAt: _clock.nowUtc().toUtc().toIso8601String(),
        );
        try {
          await _activationRepository.replaceState(reconciledState);
        } catch (e) {
          return ProvisioningResult.failure(
            operationId: operationId,
            artifactId: descriptor.artifactId,
            sourceKind: ProvisioningSourceKind.bundled,
            failureReason: ProvisioningFailureReason.activationStateWriteFailed,
            sanitizedMessage:
                'Registro aggiornato ma pulizia dello stato di attivazione last-known-good fallita.',
            cleanupSucceeded: true,
            rollbackPerformed: true,
          );
        }
      }

      return ProvisioningResult(
        operationId: operationId,
        artifactId: descriptor.artifactId,
        installationId: installationId,
        status: ProvisioningStatus.success,
        sourceKind: ProvisioningSourceKind.bundled,
        installed: false,
        cleanupSucceeded: true,
      );
    });
  }

  /// Restituisce lo stato attuale del registro di installazione sotto lock.
  Future<InstallationRecord> getInstallationRecord() async {
    return _lock.synchronized(_lockKey, () async {
      return _recordRepository.readRecord();
    });
  }

  /// Restituisce lo stato attuale di attivazione sotto lock.
  Future<ActivationState> getActivationState() async {
    return _lock.synchronized(_lockKey, () async {
      return _activationRepository.readState();
    });
  }
}
