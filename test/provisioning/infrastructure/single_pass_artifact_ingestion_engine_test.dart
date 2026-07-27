import 'dart:convert';
import 'package:aura_core/aura_offline.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

import '../provisioning_test_helpers.dart';

void main() {
  group('Tranche 6.4d — SinglePassArtifactIngestionEngine Tests', () {
    late MemoryProvisioningFileSystem fileSystem;
    late ProvisioningPathResolver pathResolver;
    late MemoryProvisioningClock clock;
    late SinglePassArtifactIngestionEngine engine;

    final baseTime = DateTime.parse('2026-07-27T20:00:00Z');

    CatalogArtifactSnapshot createSnapshot({
      required String artifactId,
      required int sizeBytes,
      required String sha256Hex,
    }) {
      return CatalogArtifactSnapshot(
        catalogId: 'aura-official-test',
        catalogRevision: 1,
        catalogSchemaVersion: '1.0',
        signingKeyId: 'test-key-1',
        trustLevel: CatalogTrustLevel.signatureVerified,
        artifactId: artifactId,
        artifactVersion: '1.0.0',
        buildId: 'v1',
        fileName: '$artifactId.gguf',
        sizeBytes: sizeBytes,
        sha256: sha256Hex.toLowerCase(),
        acquiredAtUtc: baseTime,
      );
    }

    setUp(() {
      fileSystem = MemoryProvisioningFileSystem();
      pathResolver = ProvisioningPathResolver(
        appManagedRoot: r'C:\AURA\app_managed',
        bundledRoot: r'C:\AURA\bundled',
      );
      clock = MemoryProvisioningClock(baseTime);
      engine = SinglePassArtifactIngestionEngine(
        fileSystem: fileSystem,
        pathResolver: pathResolver,
        clock: clock,
      );
    });

    test(
        'Single-pass streaming copy and SHA-256 calculation succeeds on matching file',
        () async {
      final bytes = List.generate(200, (i) => i % 256);
      final expectedSha = sha256.convert(bytes).toString().toLowerCase();

      final sourcePath = pathResolver.stagingPartPath('op-1');
      await fileSystem.appendBytes(sourcePath, bytes);

      final snapshot = createSnapshot(
        artifactId: 'model-a',
        sizeBytes: 200,
        sha256Hex: expectedSha,
      );

      final result = await engine.ingestAndVerifyToTemporaryStore(
        sourceFilePath: sourcePath,
        operationId: 'op-1',
        provenanceSnapshot: snapshot,
        sourceOwnership: ArtifactSourceOwnership.managedStaging,
      );

      expect(result.verifiedSizeBytes, equals(200));
      expect(result.verifiedSha256, equals(expectedSha));
      expect(await fileSystem.directoryExists(result.temporaryInstallPath),
          isTrue);

      final recordFile =
          '${result.temporaryInstallPath}\\installation_record.json';
      final markerFile = '${result.temporaryInstallPath}\\commit.marker';

      expect(await fileSystem.fileExists(recordFile), isTrue);
      expect(await fileSystem.fileExists(markerFile), isTrue);

      final markerRaw = await fileSystem.readAsString(markerFile);
      final markerJson = jsonDecode(markerRaw) as Map<String, dynamic>;
      expect(markerJson['artifactId'], equals('model-a'));
      expect(markerJson['preparedAtUtc'], equals('2026-07-27T20:00:00.000Z'));
    });

    test(
        'Hash mismatch purges temporary store and quarantines managed staging file',
        () async {
      final bytes = List.generate(200, (i) => i % 256);
      final wrongSha =
          sha256.convert(List.generate(200, (i) => 0)).toString().toLowerCase();

      final sourcePath = pathResolver.stagingPartPath('op-bad');
      await fileSystem.appendBytes(sourcePath, bytes);

      final snapshot = createSnapshot(
        artifactId: 'model-bad',
        sizeBytes: 200,
        sha256Hex: wrongSha,
      );

      await expectLater(
        engine.ingestAndVerifyToTemporaryStore(
          sourceFilePath: sourcePath,
          operationId: 'op-bad',
          provenanceSnapshot: snapshot,
          sourceOwnership: ArtifactSourceOwnership.managedStaging,
        ),
        throwsA(isA<ProvisioningException>().having(
          (e) => e.reason,
          'reason',
          equals(ProvisioningFailureReason.hashMismatch),
        )),
      );

      // Staging .part file originale è stato rimosso dalla posizione iniziale e spostato in quarantena
      expect(await fileSystem.fileExists(sourcePath), isFalse);

      final stagingDir = pathResolver.resolveStagingDirectory('op-bad');
      final quarantineReport =
          '$stagingDir\\quarantine\\op-bad\\verification_failure.json';
      final quarantinePart = '$stagingDir\\quarantine\\op-bad\\corrupted.part';

      expect(await fileSystem.fileExists(quarantineReport), isTrue);
      expect(await fileSystem.fileExists(quarantinePart), isTrue);

      final reportRaw = await fileSystem.readAsString(quarantineReport);
      final reportJson = jsonDecode(reportRaw) as Map<String, dynamic>;
      expect(reportJson['operationId'], equals('op-bad'));
      expect(reportJson['expectedSha256'], equals(wrongSha));
    });

    test(
        'User local file is NEVER modified or deleted on checksum mismatch or success',
        () async {
      final bytes = List.generate(150, (i) => i);
      final wrongSha =
          '0000000000000000000000000000000000000000000000000000000000000000';

      const userPath = r'C:\Users\dendo\Downloads\my_local_model.gguf';
      await fileSystem.appendBytes(userPath, bytes);

      final snapshot = createSnapshot(
        artifactId: 'model-user',
        sizeBytes: 150,
        sha256Hex: wrongSha,
      );

      await expectLater(
        engine.ingestAndVerifyToTemporaryStore(
          sourceFilePath: userPath,
          operationId: 'op-user-import',
          provenanceSnapshot: snapshot,
          sourceOwnership: ArtifactSourceOwnership.userOwnedFile,
        ),
        throwsA(isA<ProvisioningException>()),
      );

      // Il file locale dell'utente è ancora integro e presente!
      expect(await fileSystem.fileExists(userPath), isTrue);
      final userBytes = await fileSystem.readAsBytes(userPath);
      expect(userBytes.length, equals(150));
    });

    test(
        'Cancellation token before/during copy purges temporary installation directory',
        () async {
      final bytes = List.generate(500, (i) => i % 256);
      final validSha = sha256.convert(bytes).toString().toLowerCase();

      final sourcePath = pathResolver.stagingPartPath('op-cancel');
      await fileSystem.appendBytes(sourcePath, bytes);

      final cancelToken = DefaultProvisioningCancellationToken();
      cancelToken.cancel();

      final snapshot = createSnapshot(
        artifactId: 'model-cancel',
        sizeBytes: 500,
        sha256Hex: validSha,
      );

      await expectLater(
        engine.ingestAndVerifyToTemporaryStore(
          sourceFilePath: sourcePath,
          operationId: 'op-cancel',
          provenanceSnapshot: snapshot,
          sourceOwnership: ArtifactSourceOwnership.managedStaging,
          cancellationToken: cancelToken,
        ),
        throwsA(isA<ProvisioningException>().having(
          (e) => e.reason,
          'reason',
          equals(ProvisioningFailureReason.operationCancelled),
        )),
      );

      // Il sorgente gestito rimane intatto poichè l'operazione è stata annullata prima del completamento
      expect(await fileSystem.fileExists(sourcePath), isTrue);
    });
  });
}
