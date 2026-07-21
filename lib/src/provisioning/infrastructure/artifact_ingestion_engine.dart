import 'dart:io';
import '../domain/catalog_manifest.dart';
import '../domain/provisioning_options.dart';
import 'archive_extractor.dart';
import 'atomic_artifact_installer.dart';
import 'provisioning_file_system.dart';
import 'provisioning_http_client.dart';
import 'provisioning_path_resolver.dart';
import 'sha256_verifier.dart';

/// Engine responsabile dell'acquisizione, verifica SHA-256, decompressione ed installazione fisica degli artefatti.
final class ArtifactIngestionEngine {
  final ProvisioningPathResolver _pathResolver;
  final ProvisioningFileSystem _fileSystem;
  final ProvisioningHttpClient _httpClient;
  final ArchiveExtractor _archiveExtractor;
  final Sha256Verifier _sha256Verifier;
  final AtomicArtifactInstaller _installer;

  ArtifactIngestionEngine({
    required ProvisioningPathResolver pathResolver,
    ProvisioningFileSystem fileSystem = const LocalProvisioningFileSystem(),
    ProvisioningHttpClient? httpClient,
    ArchiveExtractor archiveExtractor = const ZipArchiveExtractor(),
    Sha256Verifier sha256Verifier = const DefaultSha256Verifier(),
    AtomicArtifactInstaller? installer,
  })  : _pathResolver = pathResolver,
        _fileSystem = fileSystem,
        _httpClient = httpClient ?? HttpProvisioningHttpClient(),
        _archiveExtractor = archiveExtractor,
        _sha256Verifier = sha256Verifier,
        _installer =
            installer ?? AtomicArtifactInstaller(fileSystem: fileSystem);

  /// Esegue l'ingestione fisica completa di un artefatto da qualsiasi sorgente supportata.
  Future<ProvisioningResult> ingestArtifact({
    required ProvisioningRequest request,
    required CatalogManifest manifest,
  }) async {
    CatalogArtifact? artifact;
    for (final item in manifest.artifacts) {
      if (item.artifactId == request.artifactId) {
        artifact = item;
        break;
      }
    }

    final mappedSourceKind = _mapSourceKind(
      artifact?.sourceKind ?? CatalogArtifactSourceKind.bundled,
    );

    if (artifact == null) {
      return ProvisioningResult.failure(
        operationId: request.operationId,
        artifactId: request.artifactId,
        sourceKind: mappedSourceKind,
        failureReason: ProvisioningFailureReason.artifactIdNotFound,
        sanitizedMessage: 'Artefatto non trovato nel manifest di catalogo.',
      );
    }

    if (artifact.platform.trim().toLowerCase() !=
        request.expectedPlatform.trim().toLowerCase()) {
      return ProvisioningResult.failure(
        operationId: request.operationId,
        artifactId: request.artifactId,
        sourceKind: mappedSourceKind,
        failureReason: ProvisioningFailureReason.unsupportedPlatform,
        sanitizedMessage: 'Piattaforma dell\'artefatto non supportata.',
      );
    }

    if (artifact.architecture.trim().toLowerCase() !=
        request.expectedArchitecture.trim().toLowerCase()) {
      return ProvisioningResult.failure(
        operationId: request.operationId,
        artifactId: request.artifactId,
        sourceKind: mappedSourceKind,
        failureReason: ProvisioningFailureReason.unsupportedArchitecture,
        sanitizedMessage: 'Architettura dell\'artefatto non supportata.',
      );
    }

    final stagingPath =
        _pathResolver.resolveStagingDirectory(request.operationId);
    bool rollbackPerformed = false;

    try {
      await _fileSystem.createDirectory(stagingPath);

      final rawIngestedFilePath = '$stagingPath\\artifact_ingested.tmp';

      // 1. Acquisizione da sorgente
      switch (artifact.sourceKind) {
        case CatalogArtifactSourceKind.remoteHttps:
          if (request.downloadPolicy ==
              ProvisioningDownloadPolicy.neverDownload) {
            return ProvisioningResult.failure(
              operationId: request.operationId,
              artifactId: request.artifactId,
              sourceKind: mappedSourceKind,
              failureReason: ProvisioningFailureReason.downloadNotAllowed,
              sanitizedMessage:
                  'Policy di download vieta l\'acquisizione remota.',
            );
          }

          final consent = request.consent;
          if (consent == null ||
              !consent.isValidFor(
                targetArtifactId: artifact.artifactId,
                targetSourceUri: artifact.downloadUri ?? '',
                targetSizeBytes: artifact.sizeBytes,
                targetOperationId: request.operationId,
              )) {
            return ProvisioningResult.failure(
              operationId: request.operationId,
              artifactId: request.artifactId,
              sourceKind: mappedSourceKind,
              failureReason: ProvisioningFailureReason.consentMissing,
              sanitizedMessage:
                  'Consenso al download remoto mancante o non valido.',
            );
          }

          await _httpClient.downloadFile(
            uri: artifact.downloadUri!,
            targetPath: rawIngestedFilePath,
            expectedSizeBytes: artifact.sizeBytes,
          );
          break;

        case CatalogArtifactSourceKind.bundled:
          final bundledPath =
              _pathResolver.resolveBundledArtifactPath(artifact);
          if (!await _fileSystem.fileExists(bundledPath) &&
              !await _fileSystem.directoryExists(bundledPath)) {
            return ProvisioningResult.failure(
              operationId: request.operationId,
              artifactId: request.artifactId,
              sourceKind: mappedSourceKind,
              failureReason: ProvisioningFailureReason.downloadFailed,
              sanitizedMessage: 'Artefatto bundled introvabile nel sistema.',
            );
          }

          if (await _fileSystem.fileExists(bundledPath)) {
            await _fileSystem.copyFile(bundledPath, rawIngestedFilePath);
          } else {
            // Se il bundled asset è una directory pre-estratta
            await _copyDirectory(bundledPath, '$stagingPath\\extracted');
          }
          break;

        case CatalogArtifactSourceKind.localImport:
          final customPath = request.customSourcePath;
          if (customPath == null || customPath.trim().isEmpty) {
            return ProvisioningResult.failure(
              operationId: request.operationId,
              artifactId: request.artifactId,
              sourceKind: mappedSourceKind,
              failureReason: ProvisioningFailureReason.invalidSourceUri,
              sanitizedMessage: 'Percorso di importazione locale mancante.',
            );
          }

          if (!await _fileSystem.fileExists(customPath) &&
              !await _fileSystem.directoryExists(customPath)) {
            return ProvisioningResult.failure(
              operationId: request.operationId,
              artifactId: request.artifactId,
              sourceKind: mappedSourceKind,
              failureReason: ProvisioningFailureReason.invalidSourceUri,
              sanitizedMessage: 'Sorgente di importazione locale introvabile.',
            );
          }

          if (await _fileSystem.fileExists(customPath)) {
            await _fileSystem.copyFile(customPath, rawIngestedFilePath);
          } else {
            await _copyDirectory(customPath, '$stagingPath\\extracted');
          }
          break;
      }

      // 2. Verifica di dimensione ed hash SHA-256 (se acquisito da file)
      if (await _fileSystem.fileExists(rawIngestedFilePath)) {
        await _sha256Verifier.verifySha256(
          filePath: rawIngestedFilePath,
          expectedSha256: artifact.sha256,
          fileSystem: _fileSystem,
        );

        // 3. Estrazione o preparazione dello staging finale
        final isZip = artifact.compression == CatalogCompressionFormat.zip ||
            rawIngestedFilePath.toLowerCase().endsWith('.zip');

        final extractedDir = '$stagingPath\\extracted';

        if (isZip) {
          await _archiveExtractor.extractZipArchive(
            archiveFilePath: rawIngestedFilePath,
            targetDirectoryPath: extractedDir,
          );
        } else {
          // File singolo non compresso
          final singleFileTargetDir = '$extractedDir\\${artifact.artifactId}';
          await _fileSystem.copyFile(
            rawIngestedFilePath,
            '$singleFileTargetDir\\${_getFileNameFromPath(rawIngestedFilePath)}',
          );
        }
      }

      // 4. Spostamento atomico nella destinazione finale
      final targetInstallPath =
          _pathResolver.resolveInstalledArtifactPath(artifact);
      final stagingSource = '$stagingPath\\extracted';

      final installRes = await _installer.installArtifact(
        artifact: artifact,
        stagingSourcePath: stagingSource,
        targetInstallPath: targetInstallPath,
        conflictPolicy: request.conflictPolicy,
      );

      // Cleanup dello staging
      await _cleanupStagingDirectory(stagingPath);

      if (installRes.alreadyInstalled) {
        return ProvisioningResult.success(
          operationId: request.operationId,
          artifactId: request.artifactId,
          installationId: 'inst-${artifact.artifactId}-${artifact.version}',
          sourceKind: mappedSourceKind,
          bytesProcessed: artifact.sizeBytes,
          alreadyInstalled: true,
        );
      }

      return ProvisioningResult.success(
        operationId: request.operationId,
        artifactId: request.artifactId,
        installationId: 'inst-${artifact.artifactId}-${artifact.version}',
        sourceKind: mappedSourceKind,
        bytesProcessed: artifact.sizeBytes,
        alreadyInstalled: false,
      );
    } on ProvisioningException catch (e) {
      rollbackPerformed = true;
      await _cleanupStagingDirectory(stagingPath);
      return ProvisioningResult.failure(
        operationId: request.operationId,
        artifactId: request.artifactId,
        sourceKind: mappedSourceKind,
        failureReason: e.reason,
        sanitizedMessage: e.message,
        rollbackPerformed: rollbackPerformed,
      );
    } catch (_) {
      rollbackPerformed = true;
      await _cleanupStagingDirectory(stagingPath);
      return ProvisioningResult.failure(
        operationId: request.operationId,
        artifactId: request.artifactId,
        sourceKind: mappedSourceKind,
        failureReason: ProvisioningFailureReason.downloadFailed,
        sanitizedMessage:
            'Fallimento imprevisto durante l\'ingestione dell\'artefatto.',
        rollbackPerformed: rollbackPerformed,
      );
    }
  }

  ProvisioningSourceKind _mapSourceKind(CatalogArtifactSourceKind sourceKind) {
    switch (sourceKind) {
      case CatalogArtifactSourceKind.bundled:
        return ProvisioningSourceKind.bundled;
      case CatalogArtifactSourceKind.remoteHttps:
        return ProvisioningSourceKind.remoteHttps;
      case CatalogArtifactSourceKind.localImport:
        return ProvisioningSourceKind.localImport;
    }
  }

  Future<void> _copyDirectory(String sourcePath, String targetPath) async {
    final sourceDir = Directory(sourcePath);
    final targetDir = Directory(targetPath);
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }
    await for (final entity in sourceDir.list(recursive: false)) {
      final name = entity.path.substring(sourceDir.path.length + 1);
      final dest = '${targetDir.path}\\$name';
      if (entity is Directory) {
        await _copyDirectory(entity.path, dest);
      } else if (entity is File) {
        await entity.copy(dest);
      }
    }
  }

  String _getFileNameFromPath(String path) {
    final normalized = path.replaceAll('/', r'\');
    final lastSep = normalized.lastIndexOf(r'\');
    if (lastSep != -1) {
      return normalized.substring(lastSep + 1);
    }
    return normalized;
  }

  Future<void> _cleanupStagingDirectory(String stagingPath) async {
    try {
      final dir = Directory(stagingPath);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {}
  }
}
