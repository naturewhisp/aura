import 'dart:async';
import 'dart:convert';
import '../domain/activation_state.dart';
import '../domain/catalog_artifact_snapshot.dart';
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
