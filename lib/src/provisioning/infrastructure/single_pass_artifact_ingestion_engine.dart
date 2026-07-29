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

/// Stato dell'operazione di quarantena per uno staging gestito corrotto.
enum QuarantineStatus {
  /// File copiato in quarantena e sorgente eliminato con successo.
  quarantined,

  /// File copiato in quarantena ma il sorgente originale non è stato eliminato.
  sourceRetained,

  /// La copia in quarantena è fallita; il sorgente originale resta invariato.
  copyFailed,
}

/// Specifica la natura del possesso della sorgente prima dell'ingestione nello store gestito.
/// Rimane `library`-private: non è esposto dall'API pubblica di `aura_offline.dart`.
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
    void Function(int bytesRead, int totalBytes)? onIngestionProgress,
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

    // sourceKind derivato univocamente da sourceOwnership
    final artifactSourceKind = switch (sourceOwnership) {
      ArtifactSourceOwnership.managedStaging =>
        CatalogArtifactSourceKind.remoteHttps,
      ArtifactSourceOwnership.userOwnedFile =>
        CatalogArtifactSourceKind.localImport,
    };

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

      int lastReportMs = 0;
      await for (final chunk in inputStream) {
        cancellationToken?.throwIfCancelled();
        bytesRead += chunk.length;
        shaConversion.add(chunk);
        await _fileSystem.appendBytes(destinationFilePath, chunk);

        final nowMs = DateTime.now().millisecondsSinceEpoch;
        if (nowMs - lastReportMs >= 100 ||
            bytesRead == provenanceSnapshot.sizeBytes) {
          lastReportMs = nowMs;
          onIngestionProgress?.call(bytesRead, provenanceSnapshot.sizeBytes);
        }
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
        message: 'Errore di I/O durante la copia streaming dell\'artefatto.',
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

    // 4. Scrittura dei metadati nella directory temporanea con pulizia compensativa su errore
    try {
      await _writeInstallMetadata(
        temporaryInstallPath: temporaryInstallPath,
        relativeInstallPath: relativeInstallPath,
        operationId: operationId,
        provenanceSnapshot: provenanceSnapshot,
        calculatedSha256: calculatedSha256,
        bytesRead: bytesRead,
        artifactSourceKind: artifactSourceKind,
      );
    } catch (_) {
      await _fileSystem.deleteDirectoryBestEffort(temporaryInstallPath);
      rethrow;
    }

    return PreparedArtifactInstallation._internal(
      temporaryInstallPath: temporaryInstallPath,
      finalInstallPath: finalInstallPath,
      sourcePath: cleanSourcePath,
      sourceOwnership: sourceOwnership,
      provenance: provenanceSnapshot,
      verifiedSizeBytes: bytesRead,
      verifiedSha256: calculatedSha256,
      verifiedAtUtc: _clock.nowUtc(),
    );
  }

  /// Esegue la copia streaming + SHA-256 di un file locale dell'utente in un'unica scansione e
  /// seleziona automaticamente lo snapshot corrispondente dalla lista di candidati post-hash.
  ///
  /// Il file sorgente non viene mai modificato né cancellato.
  ///
  /// Pipeline:
  /// 1. Pre-filtro per `preferredArtifactId` se specificato (restringe candidati, NON bypassa l'hash).
  /// 2. Single-pass: copia in `staging/local-import/<operationId>/payload.importing`, calcolo SHA-256.
  /// 3. Matching finale: filtra candidati per `sizeBytes == bytesRead && sha256 == computedHash`.
  /// 4. 0 match → [ProvisioningFailureReason.artifactNotVerified]
  ///    >1 match → [ProvisioningFailureReason.installationConflict]
  ///    1 match → rename staging temp → `.installing-<operationId>`, scrittura metadati.
  Future<PreparedArtifactInstallation> ingestLocalArtifact({
    required String sourceFilePath,
    required String operationId,
    required List<CatalogArtifactSnapshot> candidateSnapshots,
    String? preferredArtifactId,
    ProvisioningCancellationToken? cancellationToken,
  }) async {
    final cleanSourcePath = sourceFilePath.trim();
    if (!await _fileSystem.fileExists(cleanSourcePath)) {
      throw ProvisioningException(
        reason: ProvisioningFailureReason.invalidSourceUri,
        message: 'File locale per l\'import non trovato: $cleanSourcePath',
      );
    }

    // 1. Pre-filtro per preferredArtifactId (solo restringe, non bypassa hash)
    final List<CatalogArtifactSnapshot> preFiltered;
    if (preferredArtifactId != null && preferredArtifactId.isNotEmpty) {
      preFiltered = candidateSnapshots
          .where((s) => s.artifactId == preferredArtifactId)
          .toList();
      if (preFiltered.isEmpty) {
        throw ProvisioningException(
          reason: ProvisioningFailureReason.artifactNotVerified,
          message:
              'preferredArtifactId "$preferredArtifactId" non presente tra i candidati compatibili per dimensione.',
        );
      }
    } else {
      preFiltered = List.of(candidateSnapshots);
    }

    if (preFiltered.isEmpty) {
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.artifactNotVerified,
        message:
            'Nessun artefatto compatibile trovato nel catalogo per questo file locale.',
      );
    }

    // 2. Copia in directory temporanea dedicata con placeholder fisso
    final localTempDir = _pathResolver.localImportTempPath(operationId);
    await _fileSystem.deleteDirectoryBestEffort(localTempDir);
    await _fileSystem.createDirectory(localTempDir);

    final placeholderPath = '$localTempDir\\payload.importing';

    int bytesRead = 0;
    String calculatedSha256 = '';

    try {
      cancellationToken?.throwIfCancelled();

      // Single-pass: copia streaming + SHA-256 in pipeline
      final inputStream = _fileSystem.openRead(cleanSourcePath);
      final digestSink = _DigestSink();
      final shaConversion = sha256.startChunkedConversion(digestSink);

      await for (final chunk in inputStream) {
        cancellationToken?.throwIfCancelled();
        bytesRead += chunk.length;
        shaConversion.add(chunk);
        await _fileSystem.appendBytes(placeholderPath, chunk);
      }
      shaConversion.close();

      calculatedSha256 = digestSink.digest?.toString().toLowerCase() ?? '';

      cancellationToken?.throwIfCancelled();
    } catch (e) {
      // Pulizia immediata del temp dir locale; file utente intatto
      await _fileSystem.deleteDirectoryBestEffort(localTempDir);

      if (e is ProvisioningException &&
          e.reason == ProvisioningFailureReason.operationCancelled) {
        rethrow;
      }
      throw ProvisioningException(
        reason: ProvisioningFailureReason.invalidSourceUri,
        message: 'Errore di I/O durante la copia locale single-pass.',
      );
    }

    // 3. Matching finale post-hash su sizeBytes + sha256
    final matched = preFiltered
        .where(
          (s) =>
              s.sizeBytes == bytesRead &&
              s.sha256.toLowerCase() == calculatedSha256.toLowerCase(),
        )
        .toList();

    if (matched.isEmpty) {
      await _fileSystem.deleteDirectoryBestEffort(localTempDir);
      throw ProvisioningException(
        reason: ProvisioningFailureReason.artifactNotVerified,
        message:
            'UnknownLocalArtifact: nessun artefatto del catalogo corrisponde a sizeBytes=$bytesRead sha256=$calculatedSha256.',
      );
    }

    if (matched.length > 1) {
      await _fileSystem.deleteDirectoryBestEffort(localTempDir);
      throw ProvisioningException(
        reason: ProvisioningFailureReason.installationConflict,
        message:
            'AmbiguousCatalogMatch: ${matched.length} artefatti corrispondono alla stessa impronta crittografica. Specificare preferredArtifactId.',
      );
    }

    final matchedSnapshot = matched.first;

    // 4. Calcola path finale e rename: staging/local-import/<opId>/ → <target>.installing-<opId>/
    final relativeInstallPath = _pathResolver.resolveRelativeInstallPath(
      artifactType: CatalogArtifactType.model,
      artifactId: matchedSnapshot.artifactId,
      buildOrVersionId:
          matchedSnapshot.artifactVersion == matchedSnapshot.buildId
              ? matchedSnapshot.artifactVersion
              : '${matchedSnapshot.artifactVersion}_${matchedSnapshot.buildId}',
    );

    final finalInstallPath =
        '${_pathResolver.appManagedRoot}\\$relativeInstallPath';
    final temporaryInstallPath = '$finalInstallPath.installing-$operationId';

    // Pulisce eventuale .installing residuo
    await _fileSystem.deleteDirectoryBestEffort(temporaryInstallPath);

    // 4. Scrittura metadati e rename con pulizia compensativa se qualsiasi operazione post-creazione .installing fallisce
    try {
      // Rename canonical della directory: local-temp → .installing
      await _fileSystem.renameDirectoryWithoutFallback(
          localTempDir, temporaryInstallPath);

      // Rename placeholder → nome canonico (avviene PRIMA della scrittura di record e marker)
      final canonicalFilePath =
          '$temporaryInstallPath\\${matchedSnapshot.fileName}';
      await _fileSystem.renameFile(
          placeholderPath.replaceFirst(localTempDir, temporaryInstallPath),
          canonicalFilePath);

      // Scrittura metadati
      await _writeInstallMetadata(
        temporaryInstallPath: temporaryInstallPath,
        relativeInstallPath: relativeInstallPath,
        operationId: operationId,
        provenanceSnapshot: matchedSnapshot,
        calculatedSha256: calculatedSha256,
        bytesRead: bytesRead,
        artifactSourceKind: CatalogArtifactSourceKind.localImport,
      );
    } catch (_) {
      await _fileSystem.deleteDirectoryBestEffort(temporaryInstallPath);
      rethrow;
    }

    return PreparedArtifactInstallation._internal(
      temporaryInstallPath: temporaryInstallPath,
      finalInstallPath: finalInstallPath,
      sourcePath: cleanSourcePath,
      sourceOwnership: ArtifactSourceOwnership.userOwnedFile,
      provenance: matchedSnapshot,
      verifiedSizeBytes: bytesRead,
      verifiedSha256: calculatedSha256,
      verifiedAtUtc: _clock.nowUtc(),
    );
  }

  /// Scrive `installation_record.json` e `commit.marker` nella directory temporanea.
  Future<void> _writeInstallMetadata({
    required String temporaryInstallPath,
    required String relativeInstallPath,
    required String operationId,
    required CatalogArtifactSnapshot provenanceSnapshot,
    required String calculatedSha256,
    required int bytesRead,
    required CatalogArtifactSourceKind artifactSourceKind,
  }) async {
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
      sourceKind: artifactSourceKind,
      status: InstallationStatus.verified,
    );

    final recordJsonPath = '$temporaryInstallPath\\installation_record.json';
    await _fileSystem.writeStringRecoverably(
      recordJsonPath,
      const JsonEncoder.withIndent('  ').convert(descriptor.toJson()),
    );

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
  }

  /// Sposta uno staging gestito corrotto nella cartella di quarantena con reporting differenziato.
  Future<void> _quarantineManagedStaging({
    required String operationId,
    required String sourceFilePath,
    required CatalogArtifactSnapshot provenance,
    required int actualSizeBytes,
    required String actualSha256,
  }) async {
    QuarantineStatus status = QuarantineStatus.copyFailed;
    try {
      final quarantineDir = _pathResolver.quarantineOperationPath(operationId);
      await _fileSystem.createDirectory(quarantineDir);

      final quarantinePartPath = '$quarantineDir\\corrupted.part';
      try {
        await _fileSystem.copyFile(sourceFilePath, quarantinePartPath);
        // Verifica post-condizione cancellazione sorgente
        await _fileSystem.deleteFileBestEffort(sourceFilePath);
        final stillExists = await _fileSystem.fileExists(sourceFilePath);
        status = stillExists
            ? QuarantineStatus.sourceRetained
            : QuarantineStatus.quarantined;
      } catch (_) {
        status = QuarantineStatus.copyFailed;
      }

      // Report scritto SEMPRE in best effort, indipendentemente dallo status
      final report = {
        'schemaVersion': '1.0',
        'operationId': operationId,
        'artifactId': provenance.artifactId,
        'expectedSizeBytes': provenance.sizeBytes,
        'actualSizeBytes': actualSizeBytes,
        'expectedSha256': provenance.sha256,
        'actualSha256': actualSha256,
        'quarantineStatus': status.name,
        'quarantinedAtUtc': _clock.nowUtc().toIso8601String(),
      };

      final reportPath = '$quarantineDir\\verification_failure.json';
      await _fileSystem.writeStringRecoverably(
        reportPath,
        const JsonEncoder.withIndent('  ').convert(report),
      );
    } catch (_) {
      // La quarantena non deve mai bloccare l'eccezione principale di hash mismatch
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
