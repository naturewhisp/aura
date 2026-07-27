import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';

import '../domain/catalog_artifact_snapshot.dart';
import '../domain/catalog_manifest.dart';
import '../domain/installation_record.dart';
import '../domain/provisioning_cancellation_token.dart';
import '../domain/provisioning_clock.dart';
import '../domain/provisioning_options.dart';
import 'provisioning_file_system.dart';
import 'provisioning_path_resolver.dart';

/// Specifica la natura del possesso della sorgente prima dell'ingestione nello store gestito.
enum ArtifactSourceOwnership {
  /// File `.part` gestito internamente dal motore di download nello staging.
  managedStaging,

  /// File locale di proprietà dell'utente che non deve mai essere eliminato o modificato.
  userOwnedFile,
}

/// Capability token immutabile che attesta l'avvenuta copia e verifica crittografica single-pass
/// nella directory temporanea dello store (`<targetPath>.installing-<operationId>\`), pronta per il commit atomico.
@immutable
final class PreparedArtifactInstallation {
  final String temporaryInstallPath;
  final String finalInstallPath;
  final String sourcePath;
  final ArtifactSourceOwnership sourceOwnership;
  final CatalogArtifactSnapshot provenance;
  final int verifiedSizeBytes;
  final String verifiedSha256;
  final DateTime verifiedAtUtc;

  /// Costruttore privato accessibile esclusivamente all'interno della library di ingestione.
  const PreparedArtifactInstallation._internal({
    required this.temporaryInstallPath,
    required this.finalInstallPath,
    required this.sourcePath,
    required this.sourceOwnership,
    required this.provenance,
    required this.verifiedSizeBytes,
    required this.verifiedSha256,
    required this.verifiedAtUtc,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PreparedArtifactInstallation &&
          runtimeType == other.runtimeType &&
          temporaryInstallPath == other.temporaryInstallPath &&
          finalInstallPath == other.finalInstallPath &&
          sourcePath == other.sourcePath &&
          sourceOwnership == other.sourceOwnership &&
          provenance == other.provenance &&
          verifiedSizeBytes == other.verifiedSizeBytes &&
          verifiedSha256 == other.verifiedSha256 &&
          verifiedAtUtc == other.verifiedAtUtc;

  @override
  int get hashCode => Object.hash(
        temporaryInstallPath,
        finalInstallPath,
        sourcePath,
        sourceOwnership,
        provenance,
        verifiedSizeBytes,
        verifiedSha256,
        verifiedAtUtc,
      );
}

/// Motore di ingestione single-pass che esegue la lettura, copia e verifica SHA-256 in un'unica scansione streaming.
final class SinglePassArtifactIngestionEngine {
  final ProvisioningFileSystem _fileSystem;
  final ProvisioningPathResolver _pathResolver;
  final ProvisioningClock _clock;

  SinglePassArtifactIngestionEngine({
    required ProvisioningFileSystem fileSystem,
    required ProvisioningPathResolver pathResolver,
    ProvisioningClock clock = const SystemProvisioningClock(),
  })  : _fileSystem = fileSystem,
        _pathResolver = pathResolver,
        _clock = clock;

  /// Esegue la copia streaming ed il calcolo SHA-256 in un'unica scansione dal file sorgente
  /// verso la directory temporanea dello store (`.installing-<operationId>`).
  Future<PreparedArtifactInstallation> ingestAndVerifyToTemporaryStore({
    required String sourceFilePath,
    required String operationId,
    required CatalogArtifactSnapshot provenanceSnapshot,
    required ArtifactSourceOwnership sourceOwnership,
    ProvisioningCancellationToken? cancellationToken,
  }) async {
    final cleanSourcePath = sourceFilePath.trim();
    if (!await _fileSystem.fileExists(cleanSourcePath)) {
      throw ProvisioningException(
        reason: ProvisioningFailureReason.invalidSourceUri,
        message:
            'File sorgente per l\'ingestione non trovato: $cleanSourcePath',
      );
    }

    final relativeInstallPath = _pathResolver.resolveRelativeInstallPath(
      artifactType: CatalogArtifactType.model,
      artifactId: provenanceSnapshot.artifactId,
      buildOrVersionId: provenanceSnapshot.artifactVersion ==
              provenanceSnapshot.buildId
          ? provenanceSnapshot.artifactVersion
          : '${provenanceSnapshot.artifactVersion}_${provenanceSnapshot.buildId}',
    );

    final finalInstallPath =
        '${_pathResolver.appManagedRoot}\\$relativeInstallPath';
    final temporaryInstallPath = '$finalInstallPath.installing-$operationId';

    // 1. Isolamento della directory temporanea dello store
    await _fileSystem.deleteDirectoryBestEffort(temporaryInstallPath);
    await _fileSystem.createDirectory(temporaryInstallPath);

    final destinationFilePath =
        '$temporaryInstallPath\\${provenanceSnapshot.fileName}';

    int bytesRead = 0;
    String calculatedSha256 = '';

    try {
      cancellationToken?.throwIfCancelled();

      // 2. Lettura, Scrittura e Hashing in UN'UNICA scansione streaming (Single-Pass)
      final inputStream = _fileSystem.openRead(cleanSourcePath);
      final digestSink = _DigestSink();
      final shaConversion = sha256.startChunkedConversion(digestSink);

      await for (final chunk in inputStream) {
        cancellationToken?.throwIfCancelled();
        bytesRead += chunk.length;
        shaConversion.add(chunk);
        await _fileSystem.appendBytes(destinationFilePath, chunk);
      }
      shaConversion.close();

      calculatedSha256 = digestSink.digest?.toString().toLowerCase() ?? '';

      cancellationToken?.throwIfCancelled();
    } catch (e) {
      // Pulizia immediata della directory temporanea su fallimento o cancellazione
      await _fileSystem.deleteDirectoryBestEffort(temporaryInstallPath);

      if (e is ProvisioningException &&
          e.reason == ProvisioningFailureReason.operationCancelled) {
        rethrow;
      }
      throw ProvisioningException(
        reason: ProvisioningFailureReason.invalidSourceUri,
        message: 'Errore di I/O durante la copia streaming dell\'artefatto: $e',
      );
    }

    // 3. Verifica perentoria di dimensione ed hash SHA-256
    final expectedSha256 = provenanceSnapshot.sha256.toLowerCase();
    final isSizeValid = bytesRead == provenanceSnapshot.sizeBytes;
    final isHashValid = calculatedSha256.toLowerCase() == expectedSha256;

    if (!isSizeValid || !isHashValid) {
      // Rimuove immediatamente i file temporanei non validi
      await _fileSystem.deleteDirectoryBestEffort(temporaryInstallPath);

      // Se il sorgente è uno staging gestito, sposta in quarantena
      if (sourceOwnership == ArtifactSourceOwnership.managedStaging) {
        await _quarantineManagedStaging(
          operationId: operationId,
          sourceFilePath: cleanSourcePath,
          provenance: provenanceSnapshot,
          actualSizeBytes: bytesRead,
          actualSha256: calculatedSha256,
        );
      }

      final failureMsg = !isSizeValid
          ? 'Dimensione dell\'artefatto difforme (attesi ${provenanceSnapshot.sizeBytes} B, letti $bytesRead B).'
          : 'Checksum SHA-256 difforme (atteso $expectedSha256, calcolato $calculatedSha256).';

      throw ProvisioningException(
        reason: ProvisioningFailureReason.hashMismatch,
        message: failureMsg,
      );
    }

    // 4. Scrittura del file installation_record.json nella directory temporanea
    final nowUtc = _clock.nowUtc();
    final nowIso = nowUtc.toIso8601String();

    final descriptor = InstalledArtifactDescriptor(
      installationId: 'inst-$operationId',
      artifactId: provenanceSnapshot.artifactId,
      artifactType: CatalogArtifactType.model,
      displayName: provenanceSnapshot.artifactId,
      version: provenanceSnapshot.artifactVersion,
      buildId: provenanceSnapshot.buildId,
      platform: 'all',
      architecture: 'gguf',
      relativeInstallPath: relativeInstallPath,
      entryFileName: provenanceSnapshot.fileName,
      installedAt: nowIso,
      verifiedAt: nowIso,
      sizeBytes: bytesRead,
      sha256: calculatedSha256,
      sourceKind: CatalogArtifactSourceKind.remoteHttps,
      status: InstallationStatus.verified,
    );

    final recordJsonPath = '$temporaryInstallPath\\installation_record.json';
    await _fileSystem.writeStringRecoverably(
      recordJsonPath,
      const JsonEncoder.withIndent('  ').convert(descriptor.toJson()),
    );

    // 5. Scrittura del commit.marker JSON strutturato nella directory temporanea
    final markerPayload = {
      'schemaVersion': '1.0',
      'artifactId': provenanceSnapshot.artifactId,
      'artifactVersion': provenanceSnapshot.artifactVersion,
      'buildId': provenanceSnapshot.buildId,
      'sha256': calculatedSha256,
      'preparedAtUtc': nowIso,
    };
    final markerJsonPath = '$temporaryInstallPath\\commit.marker';
    await _fileSystem.writeStringRecoverably(
      markerJsonPath,
      const JsonEncoder.withIndent('  ').convert(markerPayload),
    );

    return PreparedArtifactInstallation._internal(
      temporaryInstallPath: temporaryInstallPath,
      finalInstallPath: finalInstallPath,
      sourcePath: cleanSourcePath,
      sourceOwnership: sourceOwnership,
      provenance: provenanceSnapshot,
      verifiedSizeBytes: bytesRead,
      verifiedSha256: calculatedSha256,
      verifiedAtUtc: nowUtc,
    );
  }

  /// Sposta uno staging gestito corretto o corrotto nella cartella di quarantena.
  Future<void> _quarantineManagedStaging({
    required String operationId,
    required String sourceFilePath,
    required CatalogArtifactSnapshot provenance,
    required int actualSizeBytes,
    required String actualSha256,
  }) async {
    try {
      final stagingRoot = _pathResolver.resolveStagingDirectory(operationId);
      final quarantineDir = '$stagingRoot\\quarantine\\$operationId';
      await _fileSystem.createDirectory(quarantineDir);

      final quarantinePartPath = '$quarantineDir\\corrupted.part';
      await _fileSystem.copyFile(sourceFilePath, quarantinePartPath);
      await _fileSystem.deleteFileBestEffort(sourceFilePath);

      final report = {
        'schemaVersion': '1.0',
        'operationId': operationId,
        'artifactId': provenance.artifactId,
        'expectedSizeBytes': provenance.sizeBytes,
        'actualSizeBytes': actualSizeBytes,
        'expectedSha256': provenance.sha256,
        'actualSha256': actualSha256,
        'quarantinedAtUtc': _clock.nowUtc().toIso8601String(),
      };

      final reportPath = '$quarantineDir\\verification_failure.json';
      await _fileSystem.writeStringRecoverably(
        reportPath,
        const JsonEncoder.withIndent('  ').convert(report),
      );
    } catch (_) {
      // Pulizia best-effort: la quarantena non deve mai bloccare l'eccezione principale di hash mismatch
    }
  }
}

final class _DigestSink implements Sink<Digest> {
  Digest? digest;

  @override
  void add(Digest data) {
    digest = data;
  }

  @override
  void close() {}
}
