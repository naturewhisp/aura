import '../domain/catalog_manifest.dart';
import '../domain/provisioning_cancellation_token.dart';
import '../domain/provisioning_options.dart';
import 'archive_extractor.dart';
import 'atomic_artifact_installer.dart';
import 'provisioning_file_system.dart';
import 'provisioning_http_client.dart';
import 'provisioning_path_resolver.dart';
import 'sha256_verifier.dart';

/// Motore di orchestrazione per l'ingestione, la verifica SHA-256, la decompressione e l'installazione fisica degli artefatti.
final class ArtifactIngestionEngine {
  final ProvisioningPathResolver _pathResolver;
  final ProvisioningHttpClient _httpClient;
  final Sha256Verifier _sha256Verifier;
  final ArchiveExtractor _archiveExtractor;
  final AtomicArtifactInstaller _installer;
  final ProvisioningFileSystem _fileSystem;

  ArtifactIngestionEngine({
    required ProvisioningPathResolver pathResolver,
    required ProvisioningHttpClient httpClient,
    Sha256Verifier sha256Verifier = const DefaultSha256Verifier(),
    ArchiveExtractor archiveExtractor = const ZipArchiveExtractor(),
    AtomicArtifactInstaller? installer,
    ProvisioningFileSystem fileSystem = const LocalProvisioningFileSystem(),
  })  : _pathResolver = pathResolver,
        _httpClient = httpClient,
        _sha256Verifier = sha256Verifier,
        _archiveExtractor = archiveExtractor,
        _fileSystem = fileSystem,
        _installer =
            installer ?? AtomicArtifactInstaller(fileSystem: fileSystem);

  /// Esegue l'ingestione completa di un artefatto da catalogo.
  Future<ProvisioningResult> ingestArtifact({
    required ProvisioningRequest request,
    required CatalogManifest manifest,
    ProvisioningCancellationToken? cancellationToken,
  }) async {
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

    final sourceKind = _mapSourceKind(artifact.sourceKind);

    // Validazione Piattaforma ed Architettura (con supporto wildcard 'all' e 'any')
    if (!_isCompatibleValue(artifact.platform, request.expectedPlatform)) {
      return ProvisioningResult.failure(
        operationId: request.operationId,
        artifactId: artifact.artifactId,
        sourceKind: sourceKind,
        failureReason: ProvisioningFailureReason.unsupportedPlatform,
        sanitizedMessage:
            'Piattaforma dell\'artefatto non supportata o non corrispondente.',
      );
    }

    if (!_isCompatibleValue(
        artifact.architecture, request.expectedArchitecture)) {
      return ProvisioningResult.failure(
        operationId: request.operationId,
        artifactId: artifact.artifactId,
        sourceKind: sourceKind,
        failureReason: ProvisioningFailureReason.unsupportedArchitecture,
        sanitizedMessage:
            'Architettura dell\'artefatto non supportata o non corrispondente.',
      );
    }

    // Validazioni preventive delle policy e delle sorgenti PRIMA di creare lo staging
    try {
      if (artifact.sourceKind == CatalogArtifactSourceKind.remoteHttps) {
        if (request.downloadPolicy ==
            ProvisioningDownloadPolicy.neverDownload) {
          return ProvisioningResult.failure(
            operationId: request.operationId,
            artifactId: artifact.artifactId,
            sourceKind: sourceKind,
            failureReason: ProvisioningFailureReason.downloadNotAllowed,
            sanitizedMessage:
                'Download remoto non consentito dalla policy applicativa.',
          );
        }

        final downloadUri = artifact.downloadUri;
        if (downloadUri == null || downloadUri.trim().isEmpty) {
          return ProvisioningResult.failure(
            operationId: request.operationId,
            artifactId: artifact.artifactId,
            sourceKind: sourceKind,
            failureReason: ProvisioningFailureReason.invalidSourceUri,
            sanitizedMessage:
                'URI remota di download vuota o mancante nel catalogo.',
          );
        }

        if (request.consent == null ||
            !request.consent!.isValidFor(
              targetArtifactId: artifact.artifactId,
              targetSourceUri: downloadUri,
              targetSizeBytes: artifact.sizeBytes,
              targetOperationId: request.operationId,
            )) {
          return ProvisioningResult.failure(
            operationId: request.operationId,
            artifactId: artifact.artifactId,
            sourceKind: sourceKind,
            failureReason: ProvisioningFailureReason.consentMissing,
            sanitizedMessage:
                'Consenso esplicito al download mancante o non valido.',
          );
        }
      } else if (artifact.sourceKind == CatalogArtifactSourceKind.bundled) {
        final bundledFilePath =
            _pathResolver.resolveBundledArtifactPath(artifact);
        if (!await _fileSystem.fileExists(bundledFilePath)) {
          return ProvisioningResult.failure(
            operationId: request.operationId,
            artifactId: artifact.artifactId,
            sourceKind: sourceKind,
            failureReason: ProvisioningFailureReason.invalidSourceUri,
            sanitizedMessage:
                'Artefatto bundled non trovato nel percorso pre-impacchettato.',
          );
        }
        final size = await _fileSystem.getFileSize(bundledFilePath);
        if (size != artifact.sizeBytes) {
          return ProvisioningResult.failure(
            operationId: request.operationId,
            artifactId: artifact.artifactId,
            sourceKind: sourceKind,
            failureReason: ProvisioningFailureReason.sizeMismatch,
            sanitizedMessage:
                'Dimensione dell\'artefatto bundled non corrispondente al catalogo.',
          );
        }
      } else if (artifact.sourceKind == CatalogArtifactSourceKind.localImport) {
        final localPath = request.customSourcePath;
        if (localPath == null ||
            localPath.trim().isEmpty ||
            !await _fileSystem.fileExists(localPath)) {
          return ProvisioningResult.failure(
            operationId: request.operationId,
            artifactId: artifact.artifactId,
            sourceKind: sourceKind,
            failureReason: ProvisioningFailureReason.invalidSourceUri,
            sanitizedMessage:
                'File di sorgente locale per l\'importazione non trovato o non valido.',
          );
        }
        final size = await _fileSystem.getFileSize(localPath);
        if (size != artifact.sizeBytes) {
          return ProvisioningResult.failure(
            operationId: request.operationId,
            artifactId: artifact.artifactId,
            sourceKind: sourceKind,
            failureReason: ProvisioningFailureReason.sizeMismatch,
            sanitizedMessage:
                'Dimensione del file locale non corrispondente al catalogo.',
          );
        }
      }
    } catch (_) {
      return ProvisioningResult.failure(
        operationId: request.operationId,
        artifactId: artifact.artifactId,
        sourceKind: sourceKind,
        failureReason: ProvisioningFailureReason.invalidSourceUri,
        sanitizedMessage:
            'Errore di I/O durante la verifica della sorgente dell\'artefatto.',
      );
    }

    final targetInstallPath =
        _pathResolver.resolveInstalledArtifactPath(artifact);
    final intermediateInstallPath =
        _pathResolver.resolveIntermediateInstallPath(
      artifact: artifact,
      operationId: request.operationId,
    );
    final stagingPath =
        _pathResolver.resolveStagingDirectory(request.operationId);

    int bytesProcessed = 0;
    ProvisioningResult? result;

    try {
      cancellationToken?.throwIfCancelled();

      // Isolamento staging: pulizia preventiva
      await _fileSystem.deleteDirectoryBestEffort(stagingPath);
      await _fileSystem.createDirectory(stagingPath);

      // 2. Acquisizione dell'artefatto in staging
      final rawIngestedFilePath = '$stagingPath\\${artifact.fileName}';

      switch (artifact.sourceKind) {
        case CatalogArtifactSourceKind.remoteHttps:
          bytesProcessed = await _httpClient.downloadFile(
            uri: artifact.downloadUri!,
            targetPath: rawIngestedFilePath,
            expectedSizeBytes: artifact.sizeBytes,
            cancellationToken: cancellationToken,
          );

        case CatalogArtifactSourceKind.bundled:
          final bundledFilePath =
              _pathResolver.resolveBundledArtifactPath(artifact);
          await _fileSystem.copyFile(bundledFilePath, rawIngestedFilePath);
          bytesProcessed = await _fileSystem.getFileSize(rawIngestedFilePath);

        case CatalogArtifactSourceKind.localImport:
          await _fileSystem.copyFile(
              request.customSourcePath!, rawIngestedFilePath);
          bytesProcessed = await _fileSystem.getFileSize(rawIngestedFilePath);
      }

      cancellationToken?.throwIfCancelled();

      // 3. Verifica perentoria SHA-256 su file acquisito
      await _sha256Verifier.verifySha256(
        filePath: rawIngestedFilePath,
        expectedSha256: artifact.sha256,
        fileSystem: _fileSystem,
      );

      // 4. Decompressione o preparazione dello staging estratto
      final isZip = artifact.compression == CatalogCompressionFormat.zip ||
          rawIngestedFilePath.toLowerCase().endsWith('.zip');

      final extractedDir = '$stagingPath\\extracted';
      await _fileSystem.createDirectory(extractedDir);

      String stagingSourceForInstall;

      if (isZip) {
        final extractedBytes = await _archiveExtractor.extractZipArchive(
          archiveFilePath: rawIngestedFilePath,
          targetDirectoryPath: extractedDir,
          maxExpectedBytes: artifact.sizeBytes,
          cancellationToken: cancellationToken,
        );
        bytesProcessed = extractedBytes;
        stagingSourceForInstall = extractedDir;
      } else {
        stagingSourceForInstall = rawIngestedFilePath;
      }

      cancellationToken?.throwIfCancelled();

      // 5. Installazione fisica atomica tramite intermediate directory
      final installResult = await _installer.installArtifact(
        artifact: artifact,
        stagingSourcePath: stagingSourceForInstall,
        targetInstallPath: targetInstallPath,
        intermediateInstallPath: intermediateInstallPath,
        cancellationToken: cancellationToken,
      );

      result = ProvisioningResult(
        operationId: request.operationId,
        artifactId: artifact.artifactId,
        status: installResult.alreadyInstalled
            ? ProvisioningStatus.alreadyInstalled
            : ProvisioningStatus.success,
        installed: installResult.installed,
        alreadyInstalled: installResult.alreadyInstalled,
        verified: true,
        bytesProcessed: bytesProcessed,
        sourceKind: sourceKind,
        installationId: null,
      );
    } on ArtifactInstallationException catch (e) {
      result = ProvisioningResult.failure(
        operationId: request.operationId,
        artifactId: artifact.artifactId,
        sourceKind: sourceKind,
        failureReason: e.reason,
        sanitizedMessage: e.message,
        rollbackPerformed: e.rollbackPerformed,
      );
    } on ProvisioningException catch (e) {
      result = ProvisioningResult.failure(
        operationId: request.operationId,
        artifactId: artifact.artifactId,
        sourceKind: sourceKind,
        failureReason: e.reason,
        sanitizedMessage: e.message,
        rollbackPerformed: false,
      );
    } catch (_) {
      result = ProvisioningResult.failure(
        operationId: request.operationId,
        artifactId: artifact.artifactId,
        sourceKind: sourceKind,
        failureReason: ProvisioningFailureReason.unexpectedState,
        sanitizedMessage:
            'Errore imprevisto durante l\'ingestione dell\'artefatto.',
        rollbackPerformed: false,
      );
    } finally {
      // Pulizia incondizionata dello staging ed aggiornamento sicuro di cleanupSucceeded
      final cleanupOk =
          await _fileSystem.deleteDirectoryBestEffort(stagingPath);
      if (result != null) {
        result = result.copyWith(cleanupSucceeded: cleanupOk);
      } else {
        result = ProvisioningResult.failure(
          operationId: request.operationId,
          artifactId: artifact.artifactId,
          sourceKind: sourceKind,
          failureReason: ProvisioningFailureReason.unexpectedState,
          sanitizedMessage:
              'Errore imprevisto durante l\'ingestione dell\'artefatto.',
          cleanupSucceeded: cleanupOk,
        );
      }
    }

    return result;
  }

  static ProvisioningSourceKind _mapSourceKind(
      CatalogArtifactSourceKind sourceKind) {
    return switch (sourceKind) {
      CatalogArtifactSourceKind.bundled => ProvisioningSourceKind.bundled,
      CatalogArtifactSourceKind.remoteHttps =>
        ProvisioningSourceKind.remoteHttps,
      CatalogArtifactSourceKind.localImport =>
        ProvisioningSourceKind.localImport,
    };
  }

  static bool _isCompatibleValue(String artifactValue, String expectedValue) {
    final normArtifact = artifactValue.trim().toLowerCase();
    final normExpected = expectedValue.trim().toLowerCase();
    return normArtifact == 'all' ||
        normArtifact == 'any' ||
        normArtifact == normExpected;
  }
}
