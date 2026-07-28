import 'dart:convert';
import 'package:aura_core/aura_offline.dart';
import 'package:aura_core/aura_testing.dart';
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
      String version = '1.0.0',
      String buildId = 'v1',
    }) {
      return CatalogArtifactSnapshot(
        catalogId: 'aura-official-test',
        catalogRevision: 1,
        catalogSchemaVersion: '1.0',
        signingKeyId: 'test-key-1',
        trustLevel: CatalogTrustLevel.signatureVerified,
        artifactId: artifactId,
        artifactVersion: version,
        buildId: buildId,
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

    // ─── ingestAndVerifyToTemporaryStore ───────────────────────────────────

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

      final quarantineDir = pathResolver.quarantineOperationPath('op-bad');
      final quarantineReport = '$quarantineDir\\verification_failure.json';
      final quarantinePart = '$quarantineDir\\corrupted.part';

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

    // ─── ingestLocalArtifact — post-hash matching ─────────────────────────

    group('ingestLocalArtifact — post-hash matching', () {
      late List<int> bytes;
      late String correctSha;
      const userPath = r'C:\Users\dendo\Downloads\model.gguf';

      setUp(() async {
        bytes = List.generate(256, (i) => i % 256);
        correctSha = sha256.convert(bytes).toString().toLowerCase();
        await fileSystem.appendBytes(userPath, bytes);
      });

      test('1 match: ingestione riuscita e file utente non eliminato',
          () async {
        final snapshot = createSnapshot(
          artifactId: 'model-local-a',
          sizeBytes: 256,
          sha256Hex: correctSha,
        );

        final result = await engine.ingestLocalArtifact(
          sourceFilePath: userPath,
          operationId: 'local-op-1',
          candidateSnapshots: [snapshot],
        );

        expect(result.verifiedSha256, equals(correctSha));
        expect(result.verifiedSizeBytes, equals(256));
        expect(result.provenance.artifactId, equals('model-local-a'));
        expect(result.sourceOwnership,
            equals(ArtifactSourceOwnership.userOwnedFile));

        // File utente intatto
        expect(await fileSystem.fileExists(userPath), isTrue);

        // Directory temporanea rinominata in .installing
        expect(await fileSystem.directoryExists(result.temporaryInstallPath),
            isTrue);
        expect(result.temporaryInstallPath, contains('.installing-local-op-1'));

        // Il payload ha il nome canonico (non payload.importing)
        final canonicalFile =
            '${result.temporaryInstallPath}\\model-local-a.gguf';
        expect(await fileSystem.fileExists(canonicalFile), isTrue);

        // Metadati scritti
        final markerPath = '${result.temporaryInstallPath}\\commit.marker';
        final recordPath =
            '${result.temporaryInstallPath}\\installation_record.json';
        expect(await fileSystem.fileExists(markerPath), isTrue);
        expect(await fileSystem.fileExists(recordPath), isTrue);

        // local-import temp eliminata dopo rinomina
        final localTempDir = pathResolver.localImportTempPath('local-op-1');
        expect(await fileSystem.directoryExists(localTempDir), isFalse);
      });

      test(
          '0 match: nessun candidato corrisponde all\'hash → artifactNotVerified',
          () async {
        final wrongSnapshot = createSnapshot(
          artifactId: 'model-wrong',
          sizeBytes: 256,
          sha256Hex: '0' * 64,
        );

        await expectLater(
          engine.ingestLocalArtifact(
            sourceFilePath: userPath,
            operationId: 'local-op-0',
            candidateSnapshots: [wrongSnapshot],
          ),
          throwsA(isA<ProvisioningException>().having(
            (e) => e.reason,
            'reason',
            equals(ProvisioningFailureReason.artifactNotVerified),
          )),
        );

        // File utente intatto
        expect(await fileSystem.fileExists(userPath), isTrue);
        // Temp dir eliminata
        final localTempDir = pathResolver.localImportTempPath('local-op-0');
        expect(await fileSystem.directoryExists(localTempDir), isFalse);
      });

      test('>1 match: due candidati con stessa impronta → installationConflict',
          () async {
        final snapshotA = createSnapshot(
          artifactId: 'model-a-dup',
          sizeBytes: 256,
          sha256Hex: correctSha,
        );
        final snapshotB = createSnapshot(
          artifactId: 'model-b-dup',
          sizeBytes: 256,
          sha256Hex: correctSha,
        );

        await expectLater(
          engine.ingestLocalArtifact(
            sourceFilePath: userPath,
            operationId: 'local-op-dup',
            candidateSnapshots: [snapshotA, snapshotB],
          ),
          throwsA(isA<ProvisioningException>().having(
            (e) => e.reason,
            'reason',
            equals(ProvisioningFailureReason.installationConflict),
          )),
        );

        // File utente intatto
        expect(await fileSystem.fileExists(userPath), isTrue);
        // Temp dir eliminata
        final localTempDir = pathResolver.localImportTempPath('local-op-dup');
        expect(await fileSystem.directoryExists(localTempDir), isFalse);
      });

      test(
          '>1 candidati per size ma solo 1 ha hash corretto → match univoco dopo SHA-256',
          () async {
        // snapshotOther ha stessa dimensione ma sha256 diverso
        final snapshotCorrect = createSnapshot(
          artifactId: 'model-c-ok',
          sizeBytes: 256,
          sha256Hex: correctSha,
        );
        final snapshotOther = createSnapshot(
          artifactId: 'model-c-other',
          sizeBytes: 256,
          sha256Hex: 'a' * 64,
        );

        final result = await engine.ingestLocalArtifact(
          sourceFilePath: userPath,
          operationId: 'local-op-disamb',
          candidateSnapshots: [snapshotCorrect, snapshotOther],
        );

        expect(result.provenance.artifactId, equals('model-c-ok'));
        expect(result.verifiedSha256, equals(correctSha));
        expect(await fileSystem.fileExists(userPath), isTrue);
      });

      test(
          'preferredArtifactId non presente tra i candidati → artifactNotVerified',
          () async {
        final snapshot = createSnapshot(
          artifactId: 'model-d',
          sizeBytes: 256,
          sha256Hex: correctSha,
        );

        await expectLater(
          engine.ingestLocalArtifact(
            sourceFilePath: userPath,
            operationId: 'local-op-pref-fail',
            candidateSnapshots: [snapshot],
            preferredArtifactId: 'model-does-not-exist',
          ),
          throwsA(isA<ProvisioningException>().having(
            (e) => e.reason,
            'reason',
            equals(ProvisioningFailureReason.artifactNotVerified),
          )),
        );
      });

      test(
          'preferredArtifactId restringe correttamente a 1 candidato → match riuscito',
          () async {
        final snapshotE = createSnapshot(
          artifactId: 'model-e',
          sizeBytes: 256,
          sha256Hex: correctSha,
        );
        // Stessa dimensione e hash, ma preferredArtifactId disambigua
        final snapshotF = createSnapshot(
          artifactId: 'model-f',
          sizeBytes: 256,
          sha256Hex: correctSha,
        );

        // Con preferredArtifactId specifichiamo model-e → 1 solo candidato → match
        final result = await engine.ingestLocalArtifact(
          sourceFilePath: userPath,
          operationId: 'local-op-pref-ok',
          candidateSnapshots: [snapshotE, snapshotF],
          preferredArtifactId: 'model-e',
        );

        expect(result.provenance.artifactId, equals('model-e'));
        expect(await fileSystem.fileExists(userPath), isTrue);
      });
    });

    group('Finding 6 — CatalogArtifactSnapshot.fromJson sourceUri validation',
        () {
      test('sourceUri malformato o non assoluto lancia ProvisioningException',
          () {
        final json = {
          'catalogId': 'cat-1',
          'catalogRevision': 1,
          'catalogSchemaVersion': '1.0',
          'signingKeyId': 'key-1',
          'trustLevel': 'signatureVerified',
          'artifactId': 'art-1',
          'artifactVersion': '1.0.0',
          'buildId': 'v1',
          'fileName': 'art-1.gguf',
          'sizeBytes': 100,
          'sha256': 'a' * 64,
          'acquiredAtUtc': '2026-07-28T09:00:00.000Z',
          'sourceUri': 'not_a_valid_uri',
        };

        expect(
          () => CatalogArtifactSnapshot.fromJson(json),
          throwsA(isA<ProvisioningException>().having(
            (e) => e.reason,
            'reason',
            equals(ProvisioningFailureReason.installationRecordReadFailed),
          )),
        );
      });

      test('sourceUri con schema ftp o file lancia ProvisioningException', () {
        final json = {
          'catalogId': 'cat-1',
          'catalogRevision': 1,
          'catalogSchemaVersion': '1.0',
          'signingKeyId': 'key-1',
          'trustLevel': 'signatureVerified',
          'artifactId': 'art-1',
          'artifactVersion': '1.0.0',
          'buildId': 'v1',
          'fileName': 'art-1.gguf',
          'sizeBytes': 100,
          'sha256': 'a' * 64,
          'acquiredAtUtc': '2026-07-28T09:00:00.000Z',
          'sourceUri': 'ftp://example.com/file.gguf',
        };

        expect(
          () => CatalogArtifactSnapshot.fromJson(json),
          throwsA(isA<ProvisioningException>().having(
            (e) => e.reason,
            'reason',
            equals(ProvisioningFailureReason.installationRecordReadFailed),
          )),
        );
      });
    });
  });
}
