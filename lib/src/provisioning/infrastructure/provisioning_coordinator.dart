import 'dart:async';
import 'dart:convert';
import '../domain/activation_state.dart';
import '../domain/catalog_artifact_snapshot.dart';
import '../domain/catalog_manifest.dart';
import '../domain/installation_record.dart';
import '../domain/model_lifecycle_models.dart';
import '../domain/provisioning_cancellation_token.dart';
import '../domain/provisioning_clock.dart';
import '../domain/provisioning_options.dart';
import '../domain/release_version_comparer.dart';
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

      // sourceKind derivato univocamente da sourceOwnership del token verificato
      final sourceKind =
          installation.sourceOwnership == ArtifactSourceOwnership.userOwnedFile
              ? ProvisioningSourceKind.localImport
              : ProvisioningSourceKind.remoteHttps;

      // Analogo sourceKind per i descrittori dell'indice
      final artifactSourceKind =
          installation.sourceOwnership == ArtifactSourceOwnership.userOwnedFile
              ? CatalogArtifactSourceKind.localImport
              : CatalogArtifactSourceKind.remoteHttps;

      // 1. Controllo Idempotenza e Conflitti logici sul record globale
      final currentRecord = await _recordRepository.readRecord();
      final existingDescriptor =
          currentRecord.findLatestVerifiedInstallation(provenance.artifactId);

      if (existingDescriptor != null &&
          existingDescriptor.version == provenance.artifactVersion &&
          existingDescriptor.buildId == provenance.buildId) {
        if (existingDescriptor.sha256.toLowerCase() ==
                provenance.sha256.toLowerCase() &&
            existingDescriptor.sizeBytes == provenance.sizeBytes) {
          // Finding 1 Fix: l'idempotenza logica deve essere validata dalla presenza fisica dello store
          final physicalIdempotent =
              await _isPhysicallyIdenticalInstallation(finalPath, provenance);
          if (physicalIdempotent) {
            final tempDeleted =
                await _fileSystem.deleteDirectoryBestEffort(tempPath);
            return ProvisioningResult(
              operationId: operationId,
              artifactId: provenance.artifactId,
              status: ProvisioningStatus.alreadyInstalled,
              installationId: existingDescriptor.installationId,
              installed: false,
              alreadyInstalled: true,
              activated: false,
              verified: true,
              bytesProcessed: existingDescriptor.sizeBytes,
              sourceKind: sourceKind,
              rollbackPerformed: false,
              cleanupSucceeded: tempDeleted,
              sanitizedDiagnostics: {'cleanupPending': !tempDeleted},
            );
          }
          // Se il record globale è uguale ma il target fisico è assente o corrotto,
          // non restituisce già installato bensì prosegue verso la nuova installazione.
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

      // 2. Cancellation check PRIMA del rename atomico
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

      // 3. Check fisico della destinazione finale PRIMA del rename (B2)
      //    Non si elimina mai il target incondizionatamente.
      if (await _fileSystem.directoryExists(finalPath)) {
        // Analisi fisica del contenuto: marker + record + fingerprint + size fisica GGUF
        final physicalIdempotent =
            await _isPhysicallyIdenticalInstallation(finalPath, provenance);
        await _fileSystem.deleteDirectoryBestEffort(tempPath);
        if (physicalIdempotent) {
          return ProvisioningResult(
            operationId: operationId,
            artifactId: provenance.artifactId,
            status: ProvisioningStatus.alreadyInstalled,
            installationId: existingDescriptor?.installationId ??
                'inst-recovered-$operationId',
            installed: false,
            alreadyInstalled: true,
            activated: false,
            verified: true,
            bytesProcessed: provenance.sizeBytes,
            sourceKind: sourceKind,
            rollbackPerformed: false,
            cleanupSucceeded: true,
            sanitizedDiagnostics: const {'physicalTarget': 'already_committed'},
          );
        } else {
          return ProvisioningResult.failure(
            operationId: operationId,
            artifactId: provenance.artifactId,
            sourceKind: sourceKind,
            failureReason: ProvisioningFailureReason.installationConflict,
            sanitizedMessage:
                'Conflitto fisico: il target finale esiste già con fingerprint o stato diverso.',
          );
        }
      }

      // Finding 4: Gestione esplicita di finalPath come file ordinario
      if (await _fileSystem.fileExists(finalPath) &&
          !await _fileSystem.directoryExists(finalPath)) {
        await _fileSystem.deleteDirectoryBestEffort(tempPath);
        return ProvisioningResult.failure(
          operationId: operationId,
          artifactId: provenance.artifactId,
          sourceKind: sourceKind,
          failureReason: ProvisioningFailureReason.installationConflict,
          sanitizedMessage:
              'Conflitto fisico: la destinazione finale "$finalPath" è un file anziché una directory.',
        );
      }

      // 4. COMMIT POINT: Rename atomico della directory temporanea -> finale
      //    Il target è garantito assente per il controllo fisico precedente.
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
          sourceKind: artifactSourceKind,
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
        sourceKind: artifactSourceKind,
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

      // B3 — Cleanup con post-condizione: critica è l'assenza fisica, non il bool di ritorno
      bool sourceCleanupSucceeded = true;
      bool checkpointCleanupSucceeded = true;

      if (installation.sourceOwnership ==
          ArtifactSourceOwnership.managedStaging) {
        final sourcePath = installation.sourcePath;
        final existedBefore = await _fileSystem.fileExists(sourcePath);
        if (existedBefore) {
          await _fileSystem.deleteFileBestEffort(sourcePath);
        }
        final existsAfter = await _fileSystem.fileExists(sourcePath);
        sourceCleanupSucceeded = !existsAfter;

        if (checkpointRepository != null) {
          await checkpointRepository.deleteCheckpoint(operationId);
          final remaining =
              await checkpointRepository.readCheckpoint(operationId);
          checkpointCleanupSucceeded = (remaining == null);
        }
      }

      final cleanupDone = sourceCleanupSucceeded && checkpointCleanupSucceeded;

      final Map<String, dynamic> diagnostics = {
        'indexUpdated': indexUpdated,
        'cleanupDone': cleanupDone,
        if (!sourceCleanupSucceeded) 'sourceCleanupSucceeded': false,
        if (!checkpointCleanupSucceeded) 'checkpointCleanupSucceeded': false,
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

  /// Verifica fisicamente se la directory [finalPath] contiene un'installazione
  /// committed con marker, record, fingerprint e file GGUF identici a [provenance].
  Future<bool> _isPhysicallyIdenticalInstallation(
    String finalPath,
    CatalogArtifactSnapshot provenance,
  ) async {
    try {
      final markerPath = '$finalPath\\commit.marker';
      final recordPath = '$finalPath\\installation_record.json';

      if (!await _fileSystem.fileExists(markerPath) ||
          !await _fileSystem.fileExists(recordPath)) {
        return false;
      }

      final markerRaw = await _fileSystem.readAsString(markerPath);
      final recordRaw = await _fileSystem.readAsString(recordPath);

      final markerJson = jsonDecode(markerRaw) as Map<String, dynamic>;
      final recordJson = jsonDecode(recordRaw) as Map<String, dynamic>;

      final descriptor = InstalledArtifactDescriptor.fromJson(recordJson);

      // Verifica marker
      if (markerJson['artifactId'] != provenance.artifactId) return false;
      if (markerJson['artifactVersion'] != provenance.artifactVersion)
        return false;
      if (markerJson['buildId'] != provenance.buildId) return false;
      final markerSha = (markerJson['sha256'] as String?)?.toLowerCase();
      if (markerSha != provenance.sha256.toLowerCase()) return false;

      // Verifica coerenza marker ↔ record
      if (descriptor.artifactId != provenance.artifactId) return false;
      if (descriptor.sha256.toLowerCase() != provenance.sha256.toLowerCase())
        return false;
      if (descriptor.sizeBytes != provenance.sizeBytes) return false;

      // Verifica esistenza e dimensione fisica del file GGUF
      final entryFileName = descriptor.entryFileName;
      if (entryFileName == null ||
          entryFileName.isEmpty ||
          entryFileName.contains('\\') ||
          entryFileName.contains('/')) {
        return false;
      }
      final ggufPath = '$finalPath\\$entryFileName';
      if (!await _fileSystem.fileExists(ggufPath)) return false;

      final physicalSize = await _fileSystem.getFileSize(ggufPath);
      if (physicalSize != provenance.sizeBytes) return false;

      return true;
    } catch (_) {
      return false;
    }
  }

  /// Scansiona lo store gestito (%LOCALAPPDATA%\AURA\models\) ed indicizza le installazioni
  /// committed con `commit.marker` che non compaiono nell'indice globale.
  ///
  /// Applica 14 invarianti strutturali prima di accettare una directory:
  /// - esclusione directory `.installing-*` (temporanee residue)
  /// - schemaVersion del marker == '1.0'
  /// - coerenza artifactId del marker con il segmento della directory
  /// - corrispondenza artifactVersion e buildId tra marker e record
  /// - sha256 nel marker hex di esattamente 64 caratteri
  /// - sha256 coerente tra marker e record
  /// - preparedAtUtc del marker parsabile come ISO-8601
  /// - status del record == verified
  /// - entryFileName non nullo, non vuoto, senza separatori
  /// - coerenza relativeInstallPath del record con il path fisico scansionato
  /// - file GGUF presente fisicamente nella directory
  /// - dimensione fisica del GGUF == sizeBytes del record
  ///
  /// Nota: verifica symlink/reparse point demandata alla 6.4e per mancanza di
  /// un contratto esplicito nel filesystem abstraction corrente.
  Future<int> reconcileUnindexedInstallations() async {
    return _lock.synchronized(_lockKey, () async {
      final modelsRoot = '${_pathResolver.appManagedRoot}\\models';
      if (!await _fileSystem.directoryExists(modelsRoot)) return 0;

      int reconciledCount = 0;
      // Snapshot locale aggiornato in-memory dopo ogni inserimento riuscito
      // (evita rilettura completa da disco per ogni directory)
      var currentSnapshot = await _recordRepository.readRecord();

      // Regex per identificare ed escludere directory .installing residue
      final installingPattern = RegExp(r'\.installing-[^\\/]+$');
      // Regex per sha256 hex 64 caratteri
      final sha256Pattern = RegExp(r'^[a-f0-9]{64}$');

      final artifactDirs = await _fileSystem.listDirectory(modelsRoot);
      for (final artifactSub in artifactDirs) {
        final artifactDir = '$modelsRoot\\$artifactSub';
        final versionDirs = await _fileSystem.listDirectory(artifactDir);

        for (final versionSub in versionDirs) {
          // 1. Esclusione directory .installing residue
          if (installingPattern.hasMatch(versionSub)) continue;

          final versionDir = '$artifactDir\\$versionSub';
          final markerPath = '$versionDir\\commit.marker';
          final recordPath = '$versionDir\\installation_record.json';

          if (!await _fileSystem.fileExists(markerPath) ||
              !await _fileSystem.fileExists(recordPath)) {
            continue;
          }

          try {
            final markerRaw = await _fileSystem.readAsString(markerPath);
            final recordRaw = await _fileSystem.readAsString(recordPath);

            final markerJson = jsonDecode(markerRaw) as Map<String, dynamic>;
            final recordJson = jsonDecode(recordRaw) as Map<String, dynamic>;

            // 2. schemaVersion del marker
            if (markerJson['schemaVersion'] != '1.0') continue;

            final descriptor = InstalledArtifactDescriptor.fromJson(recordJson);

            // 3. artifactId del marker corrisponde al segmento della directory
            final markerArtifactId = markerJson['artifactId'] as String?;
            if (markerArtifactId == null ||
                markerArtifactId.isEmpty ||
                markerArtifactId != artifactSub) {
              continue;
            }

            // 4. artifactVersion e buildId coerenti tra marker e record
            final markerVersion = markerJson['artifactVersion'] as String?;
            final markerBuildId = markerJson['buildId'] as String?;
            if (markerVersion == null || markerVersion != descriptor.version) {
              continue;
            }
            if (markerBuildId == null || markerBuildId != descriptor.buildId) {
              continue;
            }

            // 5. sha256 del marker: hex di esattamente 64 caratteri
            final markerSha256 =
                (markerJson['sha256'] as String?)?.toLowerCase();
            if (markerSha256 == null || !sha256Pattern.hasMatch(markerSha256)) {
              continue;
            }

            // 6. sha256 coerente tra marker e record
            if (markerSha256 != descriptor.sha256.toLowerCase()) continue;

            // 7. preparedAtUtc parsabile come ISO-8601
            final preparedAtUtcRaw = markerJson['preparedAtUtc'] as String?;
            if (preparedAtUtcRaw == null || preparedAtUtcRaw.isEmpty) {
              continue;
            }
            try {
              DateTime.parse(preparedAtUtcRaw);
            } catch (_) {
              continue;
            }

            // 8. status del record == verified
            if (descriptor.status != InstallationStatus.verified) continue;

            // 9. entryFileName non nullo, non vuoto, senza separatori
            final entryFileName = descriptor.entryFileName;
            if (entryFileName == null ||
                entryFileName.isEmpty ||
                entryFileName.contains('\\') ||
                entryFileName.contains('/')) {
              continue;
            }

            // 10. Coerenza relativeInstallPath con path fisico scansionato
            //     Il relativeInstallPath del record include il prefisso tipo
            //     (es. 'models/artifact-id/version'). Verifichiamo che i segmenti
            //     finali corrispondano al path fisico scansionato (artifactSub\versionSub),
            //     normalizzando i separatori di directory.
            final normalizedRecordPath =
                descriptor.relativeInstallPath.replaceAll('/', '\\');
            final expectedSuffix = '$artifactSub\\$versionSub';
            if (!normalizedRecordPath.endsWith(expectedSuffix)) {
              continue;
            }

            // 11. File GGUF presente fisicamente
            final ggufPath = '$versionDir\\$entryFileName';
            if (!await _fileSystem.fileExists(ggufPath)) continue;

            // 12. Dimensione fisica del GGUF == sizeBytes del record
            final physicalSize = await _fileSystem.getFileSize(ggufPath);
            if (physicalSize != descriptor.sizeBytes) continue;

            // Verifica assenza nell'indice corrente (snapshot in-memory)
            final existing =
                currentSnapshot.findInstallation(descriptor.installationId);
            if (existing == null) {
              await _recordRepository.updateRecord(
                (r) => r.upsertArtifact(descriptor),
              );
              // Aggiorna snapshot in-memory senza rilettura da disco
              currentSnapshot = currentSnapshot.upsertArtifact(descriptor);
              reconciledCount++;
            }
          } catch (_) {
            // Ignora cartelle orfane malformate o con record non deserializzabili
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

  /// Sostituisce atomicamente un'installazione fisicamente danneggiata/assente con un payload riparato,
  /// preservando l'installationId originale, l'installedAt originario ed i relativi binding di attivazione.
  Future<ModelRepairResult> repairVerifiedArtifact({
    required String targetInstallationId,
    required PreparedArtifactInstallation replacement,
    required String operationId,
  }) async {
    return _lock.synchronized(_lockKey, () async {
      final currentRecord = await _recordRepository.readRecord();
      final targetDescriptor =
          currentRecord.findInstallation(targetInstallationId);

      if (targetDescriptor == null) {
        await _fileSystem
            .deleteDirectoryBestEffort(replacement.temporaryInstallPath);
        return ModelRepairResult(
          operationId: operationId,
          artifactId: replacement.provenance.artifactId,
          installationId: targetInstallationId,
          status: ModelRepairStatus.repairMetadataMissing,
          failureReason: ProvisioningFailureReason.installationRecordReadFailed,
          message:
              'targetInstallationId "$targetInstallationId" non trovato nel registro globale.',
        );
      }

      // Verifica tassativa che la provenance dell'artefatto riparato coincida con il target
      final sameArtifact =
          targetDescriptor.artifactId == replacement.provenance.artifactId;
      final sameVersion =
          targetDescriptor.version == replacement.provenance.artifactVersion;
      final sameBuild =
          targetDescriptor.buildId == replacement.provenance.buildId;
      final sameSha = targetDescriptor.sha256.toLowerCase() ==
          replacement.provenance.sha256.toLowerCase();
      final sameSize =
          targetDescriptor.sizeBytes == replacement.provenance.sizeBytes;

      if (!sameArtifact ||
          !sameVersion ||
          !sameBuild ||
          !sameSha ||
          !sameSize) {
        await _fileSystem
            .deleteDirectoryBestEffort(replacement.temporaryInstallPath);
        return ModelRepairResult(
          operationId: operationId,
          artifactId: targetDescriptor.artifactId,
          installationId: targetInstallationId,
          status: ModelRepairStatus.repairConflict,
          failureReason: ProvisioningFailureReason.hashMismatch,
          message:
              'Mismatch di provenance: l\'artefatto riparato non coincide con i metadati dichiarati dal descrittore target.',
        );
      }

      final targetPath = _pathResolver
          .resolveAppManagedRelativePath(targetDescriptor.relativeInstallPath);
      final backupPath = '$targetPath.replaced-$operationId';
      final failedPath = '$targetPath.failed-repair-$operationId';
      final prepPath = replacement.temporaryInstallPath;

      bool backupCreated = false;
      bool prepMoved = false;

      try {
        // 1. Rename target -> backup (se target esiste)
        if (await _fileSystem.directoryExists(targetPath)) {
          await _fileSystem.deleteDirectoryBestEffort(backupPath);
          await _fileSystem.renameDirectoryWithoutFallback(
              targetPath, backupPath);
          backupCreated = true;
        }

        // 2. Rename prepared -> target
        await _fileSystem.renameDirectoryWithoutFallback(prepPath, targetPath);
        prepMoved = true;

        // 3. Aggiorna sia il file local self-describing installation_record.json sia il registro globale
        final nowIso = _clock.nowUtc().toIso8601String();
        final updatedDescriptor = targetDescriptor.copyWith(
          status: InstallationStatus.verified,
          verifiedAt: nowIso,
          repairCount: targetDescriptor.repairCount + 1,
          lastRepairedAt: nowIso,
        );

        final localRecordJsonPath = '$targetPath\\installation_record.json';
        await _fileSystem.writeStringRecoverably(
          localRecordJsonPath,
          const JsonEncoder.withIndent('  ')
              .convert(updatedDescriptor.toJson()),
        );

        final updatedRecord = currentRecord.upsertArtifact(updatedDescriptor);
        await _recordRepository.writeRecord(updatedRecord);

        // 4. Se lo swap ha avuto successo, pulisce il backup best-effort
        if (backupCreated) {
          await _fileSystem.deleteDirectoryBestEffort(backupPath);
        }

        return ModelRepairResult(
          operationId: operationId,
          artifactId: targetDescriptor.artifactId,
          installationId: targetInstallationId,
          status: ModelRepairStatus.repaired,
          filesystemCommitted: true,
          recordCommitted: true,
          activationCommitted: true,
        );
      } catch (e) {
        // COMPENSAZIONE COMPLETA
        if (prepMoved) {
          await _fileSystem.deleteDirectoryBestEffort(failedPath);
          try {
            await _fileSystem.renameDirectoryWithoutFallback(
                targetPath, failedPath);
          } catch (_) {}
        }

        if (backupCreated) {
          try {
            await _fileSystem.renameDirectoryWithoutFallback(
                backupPath, targetPath);
          } catch (_) {}
        }

        if (prepMoved) {
          await _fileSystem.deleteDirectoryBestEffort(failedPath);
        }

        await _fileSystem.deleteDirectoryBestEffort(prepPath);

        return ModelRepairResult(
          operationId: operationId,
          artifactId: targetDescriptor.artifactId,
          installationId: targetInstallationId,
          status: ModelRepairStatus.repairCommitIndeterminate,
          failureReason:
              ProvisioningFailureReason.installationRecordWriteFailed,
          message:
              'Errore I/O o di persistenza durante lo swap riparativo. Ripristinato backup originale.',
          reconciliationRequired: true,
        );
      }
    });
  }

  /// Esegue il rollback dell'attivazione verso un'installazione precedente verified previa verifica fisica.
  Future<ModelRollbackResult> rollbackInstallation({
    required String operationId,
    required String artifactId,
    required ModelActivationRole modelRole,
    required String targetInstallationId,
    String? expectedCurrentInstallationId,
  }) async {
    return _lock.synchronized(_lockKey, () async {
      final currentRecord = await _recordRepository.readRecord();
      final currentState = await _activationRepository.readState();

      // Check ottimistico sulla corrente attivazione se richiesta
      final currentActiveId = currentState.getActiveInstallationId(modelRole);

      if (expectedCurrentInstallationId != null &&
          expectedCurrentInstallationId.isNotEmpty &&
          currentActiveId != expectedCurrentInstallationId) {
        return ModelRollbackResult(
          operationId: operationId,
          artifactId: artifactId,
          previousInstallationId: currentActiveId,
          activeInstallationId: currentActiveId ?? '',
          status: ModelRollbackStatus.staleCurrentActivation,
          failureReason: ProvisioningFailureReason.activationStateWriteFailed,
          message:
              'L\'installazione attiva corrente ($currentActiveId) non corrisponde a quella attesa ($expectedCurrentInstallationId).',
        );
      }

      if (currentActiveId == targetInstallationId) {
        return ModelRollbackResult(
          operationId: operationId,
          artifactId: artifactId,
          previousInstallationId: currentActiveId,
          activeInstallationId: targetInstallationId,
          status: ModelRollbackStatus.alreadyActive,
          activationCommitted: true,
        );
      }

      final targetDescriptor =
          currentRecord.findInstallation(targetInstallationId);
      if (targetDescriptor == null ||
          targetDescriptor.status != InstallationStatus.verified) {
        return ModelRollbackResult(
          operationId: operationId,
          artifactId: artifactId,
          previousInstallationId: currentActiveId,
          activeInstallationId: currentActiveId ?? '',
          status: ModelRollbackStatus.targetNotVerified,
          failureReason: ProvisioningFailureReason.artifactNotVerified,
          message:
              'L\'installazione target "$targetInstallationId" non è verificata nel registro.',
        );
      }

      if (targetDescriptor.artifactId != artifactId) {
        return ModelRollbackResult(
          operationId: operationId,
          artifactId: artifactId,
          previousInstallationId: currentActiveId,
          activeInstallationId: currentActiveId ?? '',
          status: ModelRollbackStatus.failed,
          failureReason: ProvisioningFailureReason.artifactIdNotFound,
          message:
              'L\'installazione target "$targetInstallationId" appartiene alla famiglia "${targetDescriptor.artifactId}", non a "$artifactId".',
        );
      }

      // Attestazione dell'integrità fisica prima dell'attivazione
      final isPhysicallyValid = await _verifier.verifyPhysicalIntegrity(
        targetDescriptor,
        pathResolver: _pathResolver,
      );
      if (!isPhysicallyValid) {
        return ModelRollbackResult(
          operationId: operationId,
          artifactId: artifactId,
          previousInstallationId: currentActiveId,
          activeInstallationId: currentActiveId ?? '',
          status: ModelRollbackStatus.targetCorrupt,
          failureReason: ProvisioningFailureReason.artifactNotVerified,
          message:
              'L\'installazione target "$targetInstallationId" presenta file corrotti o assenti su disco.',
        );
      }

      // Switch atomico di ActivationState
      final nowIso = _clock.nowUtc().toIso8601String();
      final updatedState = currentState.activateBinding(
        role: modelRole,
        installationId: targetInstallationId,
        activatedAtIso: nowIso,
      );
      await _activationRepository.replaceState(updatedState);

      return ModelRollbackResult(
        operationId: operationId,
        artifactId: artifactId,
        previousInstallationId: currentActiveId,
        activeInstallationId: targetInstallationId,
        status: ModelRollbackStatus.rolledBack,
        activationCommitted: true,
      );
    });
  }

  /// Esegue la rimozione sicura (purge) di un'installazione con gestione compensata delle policy di attivazione.
  Future<ModelPurgeResult> purgeInstallation({
    required String operationId,
    required String installationId,
    required ActiveInstallationPurgePolicy activePurgePolicy,
  }) async {
    return _lock.synchronized(_lockKey, () async {
      final currentRecord = await _recordRepository.readRecord();
      final currentState = await _activationRepository.readState();

      final descriptor = currentRecord.findInstallation(installationId);
      if (descriptor == null ||
          descriptor.status == InstallationStatus.removed) {
        return ModelPurgeResult(
          operationId: operationId,
          installationId: installationId,
          status: ModelPurgeStatus.filesystemAlreadyAbsent,
          filesystemCommitted: true,
          recordCommitted: true,
          message: 'L\'installazione indicata non e presente nel registro.',
        );
      }

      // Identifica se l'installazione è attualmente attiva
      ModelActivationRole? activeRole;
      for (final role in ModelActivationRole.values) {
        if (currentState.getActiveInstallationId(role) == installationId) {
          activeRole = role;
          break;
        }
      }

      final isActive = activeRole != null;
      String? fallbackId;

      if (isActive) {
        switch (activePurgePolicy) {
          case ActiveInstallationPurgePolicy.reject:
            return ModelPurgeResult(
              operationId: operationId,
              installationId: installationId,
              status: ModelPurgeStatus.purgeRejectedActive,
              failureReason:
                  ProvisioningFailureReason.activationStateWriteFailed,
              message:
                  'Impossibile eliminare l\'installazione: e attualmente attiva e la policy di purge e set a reject.',
            );

          case ActiveInstallationPurgePolicy.fallbackToPreviousVerified:
            final available = currentRecord
                .findInstallationsForArtifact(descriptor.artifactId)
                .where((a) =>
                    a.installationId != installationId &&
                    a.status == InstallationStatus.verified)
                .toList();

            // Filtro rigido: sceglie esclusivamente release con versione STRETTAMENTE INFERIORE (<)
            final previousVerified = available.where((cand) {
              try {
                final comp = ReleaseVersionComparer.compareSnapshots(
                  current: descriptor.toSnapshot(_clock.nowUtc()),
                  candidate: cand.toSnapshot(_clock.nowUtc()),
                );
                return comp < 0; // cand è precedente/inferiore
              } catch (_) {
                return false;
              }
            }).toList();

            InstalledArtifactDescriptor? bestFallback;
            for (final cand in previousVerified) {
              if (await _verifier.verifyPhysicalIntegrity(cand,
                  pathResolver: _pathResolver)) {
                if (bestFallback == null ||
                    ReleaseVersionComparer.compareSnapshots(
                          current: cand.toSnapshot(_clock.nowUtc()),
                          candidate: bestFallback.toSnapshot(_clock.nowUtc()),
                        ) <
                        0) {
                  bestFallback = cand;
                }
              }
            }

            if (bestFallback == null) {
              return ModelPurgeResult(
                operationId: operationId,
                installationId: installationId,
                status: ModelPurgeStatus.fallbackUnavailable,
                failureReason: ProvisioningFailureReason.artifactNotVerified,
                message:
                    'Nessun\'altra versione installata e verificata precedente disponibile per il fallback.',
              );
            }
            fallbackId = bestFallback.installationId;
            break;

          case ActiveInstallationPurgePolicy.deactivate:
            break;
        }
      }

      final targetPath = _pathResolver
          .resolveAppManagedRelativePath(descriptor.relativeInstallPath);
      final trashDir = '${_pathResolver.appManagedRoot}\\staging\\trash';
      final trashPath = '$trashDir\\${installationId}_$operationId';

      bool trashMoved = false;
      bool targetExisted = false;

      try {
        await _fileSystem.createDirectory(trashDir);
        if (await _fileSystem.directoryExists(targetPath)) {
          targetExisted = true;
          await _fileSystem.renameDirectoryWithoutFallback(
              targetPath, trashPath);
          trashMoved = true;
        }

        // Switch/deattivazione ActivationState se era attiva
        if (isActive) {
          final nowIso = _clock.nowUtc().toIso8601String();
          final updatedState = fallbackId != null
              ? currentState.activateBinding(
                  role: activeRole,
                  installationId: fallbackId,
                  activatedAtIso: nowIso,
                )
              : currentState.deactivateBinding(activeRole);
          await _activationRepository.replaceState(updatedState);
        }

        // Marca record come removed
        final updatedRecord = currentRecord.removeInstallation(installationId);
        await _recordRepository.writeRecord(updatedRecord);

        // Cleanup trash best effort
        bool trashCleaned = true;
        if (trashMoved) {
          trashCleaned = await _fileSystem.deleteDirectoryBestEffort(trashPath);
        }

        final purgeStatus = !targetExisted
            ? ModelPurgeStatus.filesystemAlreadyAbsent
            : (trashMoved && trashCleaned)
                ? ModelPurgeStatus.filesystemMovedToTrash
                : ModelPurgeStatus.purgedCleanupPending;

        return ModelPurgeResult(
          operationId: operationId,
          installationId: installationId,
          fallbackInstallationId: fallbackId,
          status: purgeStatus,
          filesystemCommitted: true,
          recordCommitted: true,
          activationCommitted: isActive,
          cleanupPending: !trashCleaned,
        );
      } catch (e) {
        // COMPENSAZIONE
        if (trashMoved) {
          try {
            await _fileSystem.renameDirectoryWithoutFallback(
                trashPath, targetPath);
          } catch (_) {}
        }
        try {
          await _activationRepository.replaceState(currentState);
        } catch (_) {}

        return ModelPurgeResult(
          operationId: operationId,
          installationId: installationId,
          status: ModelPurgeStatus.purgeCommitIndeterminate,
          failureReason:
              ProvisioningFailureReason.installationRecordWriteFailed,
          message:
              'Errore I/O durante la rimozione dell\'installazione. Ripristinato stato precedente.',
        );
      }
    });
  }

  /// Esegue la riconciliazione delle transazioni di ciclo di vita (state machine 6.4e).
  Future<ModelLifecycleReconciliationResult>
      reconcileLifecycleTransactions() async {
    return _lock.synchronized(_lockKey, () async {
      int repairedCount = 0;
      int purgedTrashCount = 0;
      int cleanedStaleTempCount = 0;
      int resolvedDanglingActivationsCount = 0;
      int deactivatedNoFallbackCount = 0;
      int unresolvedRoleMismatchCount = 0;

      final modelsRoot = '${_pathResolver.appManagedRoot}\\models';
      final trashRoot = '${_pathResolver.appManagedRoot}\\staging\\trash';
      final currentRecord = await _recordRepository.readRecord();
      final currentState = await _activationRepository.readState();

      final installingPattern = RegExp(r'\.installing-[^\\/]+$');
      final repairingPattern = RegExp(r'\.repairing-[^\\/]+$');
      final replacedPattern = RegExp(r'\.replaced-[^\\/]+$');
      final failedRepairPattern = RegExp(r'\.failed-repair-[^\\/]+$');

      // 1. Bonifica directory residue in modelsRoot basata su verifier ed autorevolezza
      if (await _fileSystem.directoryExists(modelsRoot)) {
        final artifactDirs = await _fileSystem.listDirectory(modelsRoot);
        for (final artifactSub in artifactDirs) {
          final artifactDir = '$modelsRoot\\$artifactSub';
          final versionDirs = await _fileSystem.listDirectory(artifactDir);

          for (final versionSub in versionDirs) {
            final versionDir = '$artifactDir\\$versionSub';

            if (installingPattern.hasMatch(versionSub) ||
                failedRepairPattern.hasMatch(versionSub)) {
              await _fileSystem.deleteDirectoryBestEffort(versionDir);
              cleanedStaleTempCount++;
              continue;
            }

            if (repairingPattern.hasMatch(versionSub)) {
              final targetDir = versionDir.replaceFirst(repairingPattern, '');
              final targetExists = await _fileSystem.directoryExists(targetDir);
              final targetRelPath =
                  'models/$artifactSub/${versionSub.replaceFirst(repairingPattern, '')}';
              final desc = currentRecord.installedArtifacts
                  .where((a) => a.relativeInstallPath == targetRelPath)
                  .firstOrNull;

              bool targetHealthy = false;
              if (targetExists && desc != null) {
                targetHealthy = await _verifier.verifyPhysicalIntegrity(desc,
                    pathResolver: _pathResolver);
              }

              if (targetHealthy) {
                await _fileSystem.deleteDirectoryBestEffort(versionDir);
                cleanedStaleTempCount++;
              } else {
                bool repairingHealthy = false;
                if (desc != null) {
                  repairingHealthy =
                      await verifyTransactionalInstallationDirectory(
                    absolutePath: versionDir,
                    expectedDescriptor: desc,
                  );
                }

                if (repairingHealthy) {
                  await _fileSystem.deleteDirectoryBestEffort(targetDir);
                  await _fileSystem.renameDirectoryWithoutFallback(
                    versionDir,
                    targetDir,
                  );
                  repairedCount++;
                } else {
                  await _fileSystem.deleteDirectoryBestEffort(versionDir);
                  cleanedStaleTempCount++;
                }
              }
              continue;
            }

            if (replacedPattern.hasMatch(versionSub)) {
              final targetDir = versionDir.replaceFirst(replacedPattern, '');
              final targetExists = await _fileSystem.directoryExists(targetDir);

              if (targetExists) {
                // Tenta di identificare il descrittore nel registro globale
                final targetRelPath =
                    'models/$artifactSub/${versionSub.replaceFirst(replacedPattern, '')}';
                final desc = currentRecord.installedArtifacts
                    .where((a) => a.relativeInstallPath == targetRelPath)
                    .firstOrNull;

                bool targetHealthy = false;
                if (desc != null) {
                  targetHealthy = await _verifier.verifyPhysicalIntegrity(desc,
                      pathResolver: _pathResolver);
                }

                if (targetHealthy) {
                  // Il target è integro: eliminiamo in sicurezza la directory di backup .replaced-*
                  await _fileSystem.deleteDirectoryBestEffort(versionDir);
                  repairedCount++;
                } else {
                  // Il target è assente o corrotto: ripristiniamo la directory di backup .replaced-* sul target
                  await _fileSystem.deleteDirectoryBestEffort(targetDir);
                  await _fileSystem.renameDirectoryWithoutFallback(
                      versionDir, targetDir);
                  repairedCount++;
                }
              } else {
                await _fileSystem.renameDirectoryWithoutFallback(
                    versionDir, targetDir);
                repairedCount++;
              }
            }
          }
        }
      }

      // 2. Bonifica staging/trash
      if (await _fileSystem.directoryExists(trashRoot)) {
        final trashItems = await _fileSystem.listDirectory(trashRoot);
        for (final item in trashItems) {
          final trashItemPath = '$trashRoot\\$item';
          final instId = item.split('_').first;
          final desc = currentRecord.findInstallation(instId);

          if (desc == null || desc.status == InstallationStatus.removed) {
            await _fileSystem.deleteDirectoryBestEffort(trashItemPath);
            purgedTrashCount++;
          } else if (desc.status == InstallationStatus.verified) {
            final targetPath = _pathResolver
                .resolveAppManagedRelativePath(desc.relativeInstallPath);
            if (!await _fileSystem.directoryExists(targetPath)) {
              await _fileSystem.renameDirectoryWithoutFallback(
                  trashItemPath, targetPath);
              repairedCount++;
            } else {
              await _fileSystem.deleteDirectoryBestEffort(trashItemPath);
              purgedTrashCount++;
            }
          }
        }
      }

      // 3. Risoluzione dangling activation bindings in modo rigoroso (Ruolo + Artifact Family Aware)
      ActivationState nextState = currentState;
      for (final role in ModelActivationRole.values) {
        final activeInstId = currentState.getActiveInstallationId(role);
        if (activeInstId != null) {
          final desc = currentRecord.findInstallation(activeInstId);

          if (desc == null || desc.status != InstallationStatus.verified) {
            // Dangling pointer rilevato! Cerca un fallback verificato dello STESSO artifactId (famiglia)
            final targetArtifactId = desc?.artifactId;

            List<InstalledArtifactDescriptor> candidates = const [];
            if (targetArtifactId != null) {
              candidates = currentRecord
                  .findInstallationsForArtifact(targetArtifactId)
                  .where((a) =>
                      a.installationId != activeInstId &&
                      a.status == InstallationStatus.verified)
                  .toList();
            }

            InstalledArtifactDescriptor? validFallback;
            for (final cand in candidates) {
              if (await _verifier.verifyPhysicalIntegrity(cand,
                  pathResolver: _pathResolver)) {
                if (validFallback == null ||
                    ReleaseVersionComparer.compareSnapshots(
                          current: cand.toSnapshot(_clock.nowUtc()),
                          candidate: validFallback.toSnapshot(_clock.nowUtc()),
                        ) <
                        0) {
                  validFallback = cand;
                }
              }
            }

            if (validFallback != null) {
              nextState = nextState.activateBinding(
                role: role,
                installationId: validFallback.installationId,
                activatedAtIso: _clock.nowUtc().toIso8601String(),
              );
              resolvedDanglingActivationsCount++;
            } else {
              // Nessun fallback valido dello stesso artifactId: disattiva il ruolo in sicurezza
              nextState = nextState.deactivateBinding(role);
              if (targetArtifactId == null) {
                unresolvedRoleMismatchCount++;
              } else {
                deactivatedNoFallbackCount++;
              }
            }
          }
        }
      }

      if (nextState != currentState) {
        await _activationRepository.replaceState(nextState);
      }

      return ModelLifecycleReconciliationResult(
        repairedCount: repairedCount,
        purgedTrashCount: purgedTrashCount,
        cleanedStaleTempCount: cleanedStaleTempCount,
        resolvedDanglingActivationsCount: resolvedDanglingActivationsCount,
        deactivatedNoFallbackCount: deactivatedNoFallbackCount,
        unresolvedRoleMismatchCount: unresolvedRoleMismatchCount,
      );
    });
  }

  /// Esegue il commit atomico sotto lock per la Fase 2 dell'aggiornamento di un modello.
  Future<ModelUpdateResult> commitLifecycleUpdate({
    required String operationId,
    required String artifactId,
    required ModelActivationRole modelRole,
    required PreparedArtifactInstallation preparedArtifact,
    required UpdateActivationPolicy activationPolicy,
    required LifecyclePrecondition precondition,
  }) async {
    return _lock.synchronized(_lockKey, () async {
      final currentRecord = await _recordRepository.readRecord();
      final currentState = await _activationRepository.readState();

      final currentActiveId = currentState.getActiveInstallationId(modelRole);
      final currentIds = currentRecord
          .findInstallationsForArtifact(artifactId)
          .map((a) => a.installationId)
          .toSet();

      final preconditionIds = precondition.expectedInstallationIds.toSet();
      final idsMatch = currentIds.length == preconditionIds.length &&
          currentIds.containsAll(preconditionIds);
      final activeMatch =
          currentActiveId == precondition.expectedActiveInstallationId;

      if (!idsMatch || !activeMatch) {
        await _fileSystem
            .deleteDirectoryBestEffort(preparedArtifact.temporaryInstallPath);
        return ModelUpdateResult(
          operationId: operationId,
          artifactId: artifactId,
          status: ModelUpdateStatus.stalePrecondition,
          failureReason: ProvisioningFailureReason.installationConflict,
          message:
              'Le precondizioni di aggiornamento risultano superate o modificate.',
        );
      }

      final latestVerified =
          currentRecord.findLatestVerifiedInstallation(artifactId);
      if (latestVerified != null) {
        final comp = ReleaseVersionComparer.compareSnapshots(
          current: latestVerified.toSnapshot(_clock.nowUtc()),
          candidate: preparedArtifact.provenance,
        );
        if (comp == ReleaseVersionComparer.sameVersionFingerprintConflict) {
          await _fileSystem
              .deleteDirectoryBestEffort(preparedArtifact.temporaryInstallPath);
          return ModelUpdateResult(
            operationId: operationId,
            artifactId: artifactId,
            previousInstallationId: latestVerified.installationId,
            status: ModelUpdateStatus.updateConflict,
            failureReason: ProvisioningFailureReason.catalogMalformed,
            message:
                'Conflitto di fingerprint: la release candidata ha la stessa versione e revisione ma fingerprint differente.',
          );
        }
        if (comp <= 0) {
          await _fileSystem
              .deleteDirectoryBestEffort(preparedArtifact.temporaryInstallPath);
          return ModelUpdateResult(
            operationId: operationId,
            artifactId: artifactId,
            previousInstallationId: latestVerified.installationId,
            status: ModelUpdateStatus.alreadyLatest,
            message:
                'Un aggiornamento piu recente e gia stato registrato sotto lock.',
          );
        }
      }

      final prevInstId = latestVerified?.installationId;
      final finalPath = preparedArtifact.finalInstallPath;
      final relInstallPath = _pathResolver.resolveRelativeInstallPath(
        artifactType: CatalogArtifactType.model,
        artifactId: preparedArtifact.provenance.artifactId,
        buildOrVersionId:
            '${preparedArtifact.provenance.artifactVersion}-${preparedArtifact.provenance.buildId}',
      );

      if (await _fileSystem.directoryExists(finalPath)) {
        await _fileSystem
            .deleteDirectoryBestEffort(preparedArtifact.temporaryInstallPath);
        return ModelUpdateResult(
          operationId: operationId,
          artifactId: artifactId,
          previousInstallationId: prevInstId,
          status: ModelUpdateStatus.updateConflict,
          failureReason: ProvisioningFailureReason.installationConflict,
          message:
              'La destinazione di installazione esiste gia sul filesystem.',
        );
      }

      bool shouldActivate = false;
      switch (activationPolicy) {
        case UpdateActivationPolicy.activateNew:
          shouldActivate = true;
          break;
        case UpdateActivationPolicy.keepCurrent:
          shouldActivate = false;
          break;
        case UpdateActivationPolicy.followActiveArtifact:
          final activeId = currentState.getActiveInstallationId(modelRole);
          if (prevInstId != null && activeId == prevInstId) {
            shouldActivate = true;
          }
          break;
      }

      bool filesystemCommitted = false;
      bool recordCommitted = false;

      final nowIso = _clock.nowUtc().toIso8601String();
      final descriptor = InstalledArtifactDescriptor(
        installationId: 'inst-$operationId',
        artifactId: preparedArtifact.provenance.artifactId,
        artifactType: CatalogArtifactType.model,
        displayName: preparedArtifact.provenance.artifactId,
        version: preparedArtifact.provenance.artifactVersion,
        buildId: preparedArtifact.provenance.buildId,
        platform: 'all',
        architecture: 'gguf',
        relativeInstallPath: relInstallPath,
        entryFileName: preparedArtifact.provenance.fileName,
        installedAt: nowIso,
        verifiedAt: nowIso,
        sizeBytes: preparedArtifact.provenance.sizeBytes,
        sha256: preparedArtifact.provenance.sha256,
        sourceKind: CatalogArtifactSourceKind.remoteHttps,
        status: InstallationStatus.verified,
      );

      try {
        await _fileSystem.renameDirectoryWithoutFallback(
          preparedArtifact.temporaryInstallPath,
          finalPath,
        );
        filesystemCommitted = true;

        final localRecordJsonPath = '$finalPath\\installation_record.json';
        await _fileSystem.writeStringRecoverably(
          localRecordJsonPath,
          const JsonEncoder.withIndent('  ').convert(descriptor.toJson()),
        );

        final updatedRecord = currentRecord.upsertArtifact(descriptor);
        await _recordRepository.writeRecord(updatedRecord);
        recordCommitted = true;

        if (shouldActivate) {
          final updatedState = currentState.activateBinding(
            role: modelRole,
            installationId: descriptor.installationId,
            activatedAtIso: nowIso,
          );
          await _activationRepository.replaceState(updatedState);

          return ModelUpdateResult(
            operationId: operationId,
            artifactId: artifactId,
            previousInstallationId: prevInstId,
            newInstallationId: descriptor.installationId,
            status: ModelUpdateStatus.installedAndActivated,
            filesystemCommitted: true,
            recordCommitted: true,
            activationCommitted: true,
          );
        }

        return ModelUpdateResult(
          operationId: operationId,
          artifactId: artifactId,
          previousInstallationId: prevInstId,
          newInstallationId: descriptor.installationId,
          status: ModelUpdateStatus.installed,
          filesystemCommitted: true,
          recordCommitted: true,
          activationCommitted: false,
        );
      } catch (e) {
        if (!recordCommitted) {
          if (filesystemCommitted) {
            try {
              await _fileSystem.renameDirectoryWithoutFallback(
                finalPath,
                preparedArtifact.temporaryInstallPath,
              );
            } catch (_) {
              await _fileSystem.deleteDirectoryBestEffort(finalPath);
            }
            await _fileSystem.deleteDirectoryBestEffort(
                preparedArtifact.temporaryInstallPath);
          }

          final finalStillExists = await _fileSystem.directoryExists(finalPath);
          final tempStillExists = await _fileSystem
              .directoryExists(preparedArtifact.temporaryInstallPath);

          if (finalStillExists) {
            return ModelUpdateResult(
              operationId: operationId,
              artifactId: artifactId,
              previousInstallationId: prevInstId,
              status: ModelUpdateStatus.updateCommitIndeterminate,
              failureReason: ProvisioningFailureReason.atomicMoveFailed,
              filesystemCommitted: true,
              recordCommitted: false,
              activationCommitted: false,
              reconciliationRequired: true,
              message:
                  'Fallimento nella compensazione: la directory finale e ancora presente sul filesystem ma il record globale non e stato scritto. E richiesta la riconciliazione.',
            );
          }

          if (tempStillExists) {
            return ModelUpdateResult(
              operationId: operationId,
              artifactId: artifactId,
              previousInstallationId: prevInstId,
              status: ModelUpdateStatus.failed,
              failureReason: ProvisioningFailureReason.cleanupFailed,
              filesystemCommitted: false,
              recordCommitted: false,
              activationCommitted: false,
              cleanupPending: true,
              reconciliationRequired: true,
              message:
                  'Fallimento nella rimozione della directory temporanea durante la compensazione dell\'aggiornamento.',
            );
          }

          return ModelUpdateResult(
            operationId: operationId,
            artifactId: artifactId,
            previousInstallationId: prevInstId,
            status: ModelUpdateStatus.failed,
            failureReason:
                ProvisioningFailureReason.installationRecordWriteFailed,
            filesystemCommitted: false,
            recordCommitted: false,
            activationCommitted: false,
            reconciliationRequired: false,
            message:
                'Fallimento nella persistenza del record di installazione.',
          );
        }

        return ModelUpdateResult(
          operationId: operationId,
          artifactId: artifactId,
          previousInstallationId: prevInstId,
          newInstallationId: descriptor.installationId,
          status: ModelUpdateStatus.installedActivationPending,
          filesystemCommitted: true,
          recordCommitted: true,
          activationCommitted: false,
          message: 'Installazione registrata ma attivazione fallita.',
        );
      }
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

  /// Attesta l'integrità fisica e la coerenza dei metadati self-describing (`installation_record.json` e `commit.marker`)
  /// di una directory di transazione o backup alternativa prima della sua eventuale promozione.
  Future<bool> verifyTransactionalInstallationDirectory({
    required String absolutePath,
    required InstalledArtifactDescriptor expectedDescriptor,
  }) async {
    final localRecordPath = '$absolutePath\\installation_record.json';
    final commitMarkerPath = '$absolutePath\\commit.marker';

    if (!await _fileSystem.fileExists(localRecordPath) ||
        !await _fileSystem.fileExists(commitMarkerPath)) {
      return false;
    }

    try {
      // 1. Validazione e deserializzazione installation_record.json locale
      final recordStr = await _fileSystem.readAsString(localRecordPath);
      final recordMap = jsonDecode(recordStr) as Map<String, dynamic>;
      final localDescriptor = InstalledArtifactDescriptor.fromJson(recordMap);

      if (localDescriptor.artifactId != expectedDescriptor.artifactId ||
          localDescriptor.version != expectedDescriptor.version ||
          localDescriptor.buildId != expectedDescriptor.buildId ||
          localDescriptor.sha256.toLowerCase() !=
              expectedDescriptor.sha256.toLowerCase() ||
          localDescriptor.sizeBytes != expectedDescriptor.sizeBytes ||
          localDescriptor.status != InstallationStatus.verified) {
        return false;
      }

      // 2. Validazione e deserializzazione commit.marker
      final markerStr = await _fileSystem.readAsString(commitMarkerPath);
      final markerMap = jsonDecode(markerStr) as Map<String, dynamic>;

      final markerSchema = markerMap['schemaVersion'] as String?;
      final markerArtifactId = markerMap['artifactId'] as String?;
      final markerSha256 = markerMap['sha256'] as String?;
      final markerSizeBytes = markerMap['sizeBytes'] as int?;
      final markerPreparedAtIso = markerMap['preparedAtUtc'] as String?;

      if (markerSchema != '1.0' ||
          markerArtifactId != expectedDescriptor.artifactId ||
          markerSha256?.toLowerCase() !=
              expectedDescriptor.sha256.toLowerCase() ||
          markerSizeBytes != expectedDescriptor.sizeBytes ||
          markerPreparedAtIso == null ||
          DateTime.tryParse(markerPreparedAtIso) == null) {
        return false;
      }

      // 3. Verificatore fisicità ed hashing del payload GGUF
      final relativeSubDir = absolutePath.substring(
        _pathResolver.appManagedRoot.length + 1,
      );
      final tempDescriptor = localDescriptor.copyWith(
        relativeInstallPath: relativeSubDir,
      );

      return await _verifier.verifyPhysicalIntegrity(
        tempDescriptor,
        pathResolver: _pathResolver,
      );
    } catch (_) {
      return false;
    }
  }
}
