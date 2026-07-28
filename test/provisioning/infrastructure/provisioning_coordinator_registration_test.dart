import 'dart:convert';
import 'package:aura_core/aura_offline.dart';
import 'package:aura_core/aura_testing.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import '../provisioning_test_helpers.dart';

void main() {
  group(
      'Tranche 6.4d — ProvisioningCoordinator Registration & Reconciliation Tests',
      () {
    late MemoryProvisioningFileSystem fileSystem;
    late ProvisioningPathResolver pathResolver;
    late MemoryProvisioningClock clock;
    late InMemoryProvisioningLock lock;
    late JsonInstallationRecordRepository recordRepository;
    late JsonActivationStateRepository activationRepository;
    late SinglePassArtifactIngestionEngine ingestionEngine;
    late ProvisioningCoordinator coordinator;

    final baseTime = DateTime.parse('2026-07-27T20:00:00Z');

    setUp(() async {
      fileSystem = MemoryProvisioningFileSystem();
      pathResolver = ProvisioningPathResolver(
        appManagedRoot: r'C:\AURA\app_managed',
        bundledRoot: r'C:\AURA\bundled',
      );
      clock = MemoryProvisioningClock(baseTime);
      lock = InMemoryProvisioningLock();

      recordRepository = JsonInstallationRecordRepository(
        fileSystem: fileSystem,
        pathResolver: pathResolver,
        lock: lock,
        clock: clock,
      );
      activationRepository = JsonActivationStateRepository(
        fileSystem: fileSystem,
        pathResolver: pathResolver,
        lock: lock,
        clock: clock,
      );

      ingestionEngine = SinglePassArtifactIngestionEngine(
        fileSystem: fileSystem,
        pathResolver: pathResolver,
        clock: clock,
      );

      final mockClient = MockClient((request) async => http.Response('', 200));

      coordinator = ProvisioningCoordinator(
        lock: lock,
        recordRepository: recordRepository,
        activationRepository: activationRepository,
        ingestionEngine: ArtifactIngestionEngine(
          pathResolver: pathResolver,
          httpClient: HttpProvisioningHttpClient(client: mockClient),
          fileSystem: fileSystem,
        ),
        pathResolver: pathResolver,
        fileSystem: fileSystem,
        clock: clock,
      );
    });

    test(
        'registerVerifiedArtifact completes atomic rename commit point and records installation',
        () async {
      final bytes = List.generate(100, (i) => i);
      const sha =
          'bce0aff19cf5aa6a7469a30d61d04e4376e4bbf6381052ee9e7f33925c954d52';

      final sourcePath = pathResolver.stagingPartPath('op-reg-1');
      await fileSystem.appendBytes(sourcePath, bytes);

      final snapshot = CatalogArtifactSnapshot(
        catalogId: 'aura-official-test',
        catalogRevision: 1,
        catalogSchemaVersion: '1.0',
        signingKeyId: 'test-key-1',
        trustLevel: CatalogTrustLevel.signatureVerified,
        artifactId: 'model-reg-1',
        artifactVersion: '1.0.0',
        buildId: 'v1',
        fileName: 'model_reg_1.gguf',
        sizeBytes: 100,
        sha256: sha,
        acquiredAtUtc: baseTime,
      );

      final preparedInstallation =
          await ingestionEngine.ingestAndVerifyToTemporaryStore(
        sourceFilePath: sourcePath,
        operationId: 'op-reg-1',
        provenanceSnapshot: snapshot,
        sourceOwnership: ArtifactSourceOwnership.managedStaging,
      );

      final result = await coordinator.registerVerifiedArtifact(
        installation: preparedInstallation,
        operationId: 'op-reg-1',
      );

      expect(result.isSuccess, isTrue);
      expect(result.status, equals(ProvisioningStatus.success));
      expect(
          await fileSystem
              .directoryExists(preparedInstallation.finalInstallPath),
          isTrue);

      final record = await recordRepository.readRecord();
      final descriptor = record.findLatestVerifiedInstallation('model-reg-1');
      expect(descriptor, isNotNull);
      expect(descriptor!.sha256.toLowerCase(), equals(sha));
    });

    test(
        'Idempotent registration returns alreadyInstalled on identical destination',
        () async {
      final bytes = List.generate(100, (i) => i);
      const sha =
          'bce0aff19cf5aa6a7469a30d61d04e4376e4bbf6381052ee9e7f33925c954d52';

      final sourcePath = pathResolver.stagingPartPath('op-idemp');
      await fileSystem.appendBytes(sourcePath, bytes);

      final snapshot = CatalogArtifactSnapshot(
        catalogId: 'aura-official-test',
        catalogRevision: 1,
        catalogSchemaVersion: '1.0',
        signingKeyId: 'test-key-1',
        trustLevel: CatalogTrustLevel.signatureVerified,
        artifactId: 'model-idemp',
        artifactVersion: '1.0.0',
        buildId: 'v1',
        fileName: 'model_idemp.gguf',
        sizeBytes: 100,
        sha256: sha,
        acquiredAtUtc: baseTime,
      );

      final prep1 = await ingestionEngine.ingestAndVerifyToTemporaryStore(
        sourceFilePath: sourcePath,
        operationId: 'op-idemp',
        provenanceSnapshot: snapshot,
        sourceOwnership: ArtifactSourceOwnership.managedStaging,
      );

      await coordinator.registerVerifiedArtifact(
        installation: prep1,
        operationId: 'op-idemp',
      );

      // Secondo tentativo con stesso payload
      final sourcePath2 = pathResolver.stagingPartPath('op-idemp-2');
      await fileSystem.appendBytes(sourcePath2, bytes);

      final prep2 = await ingestionEngine.ingestAndVerifyToTemporaryStore(
        sourceFilePath: sourcePath2,
        operationId: 'op-idemp-2',
        provenanceSnapshot: snapshot,
        sourceOwnership: ArtifactSourceOwnership.managedStaging,
      );

      final result2 = await coordinator.registerVerifiedArtifact(
        installation: prep2,
        operationId: 'op-idemp-2',
      );

      expect(result2.isSuccess, isTrue);
      expect(result2.alreadyInstalled, isTrue);
      expect(result2.status, equals(ProvisioningStatus.alreadyInstalled));
    });

    test(
        'reconcileUnindexedInstallations recovers committed installations with valid commit.marker JSON',
        () async {
      final relativePath = pathResolver.resolveRelativeInstallPath(
        artifactType: CatalogArtifactType.model,
        artifactId: 'model-orphan',
        buildOrVersionId: '1.0.0_v1',
      );
      final finalPath = '${pathResolver.appManagedRoot}\\$relativePath';
      await fileSystem.createDirectory(finalPath);

      final descriptor = InstalledArtifactDescriptor(
        installationId: 'inst-orphan-1',
        artifactId: 'model-orphan',
        artifactType: CatalogArtifactType.model,
        displayName: 'Orphan Model',
        version: '1.0.0',
        buildId: 'v1',
        platform: 'all',
        architecture: 'gguf',
        relativeInstallPath: relativePath,
        entryFileName: 'orphan.gguf',
        installedAt: '2026-07-27T20:00:00.000Z',
        verifiedAt: '2026-07-27T20:00:00.000Z',
        sizeBytes: 300,
        sha256:
            '9999999999999999999999999999999999999999999999999999999999999999',
        sourceKind: CatalogArtifactSourceKind.remoteHttps,
        status: InstallationStatus.verified,
      );

      await fileSystem.writeAsString(
        '$finalPath\\installation_record.json',
        const JsonEncoder.withIndent('  ').convert(descriptor.toJson()),
      );

      final markerPayload = {
        'schemaVersion': '1.0',
        'artifactId': 'model-orphan',
        'artifactVersion': '1.0.0',
        'buildId': 'v1',
        'sha256':
            '9999999999999999999999999999999999999999999999999999999999999999',
        'preparedAtUtc': '2026-07-27T20:00:00.000Z',
      };

      await fileSystem.writeAsString(
        '$finalPath\\commit.marker',
        const JsonEncoder.withIndent('  ').convert(markerPayload),
      );

      // Crea il file GGUF fisico con esattamente sizeBytes byte (invariante 11/12)
      await fileSystem.appendBytes(
        '$finalPath\\orphan.gguf',
        List.generate(300, (i) => i % 256),
      );

      // Prima della riconciliazione l'indice è vuoto
      var record = await recordRepository.readRecord();
      expect(record.findInstallation('inst-orphan-1'), isNull);

      // Esecuzione riconciliazione
      final reconciledCount =
          await coordinator.reconcileUnindexedInstallations();
      expect(reconciledCount, equals(1));

      // Dopo la riconciliazione l'installazione compare nel registro globale
      record = await recordRepository.readRecord();
      expect(record.findInstallation('inst-orphan-1'), isNotNull);
    });

    test(
        'B2 — registerVerifiedArtifact con target fisico identico → idempotent success senza delete',
        () async {
      final bytes = List.generate(100, (i) => i);
      const sha =
          'bce0aff19cf5aa6a7469a30d61d04e4376e4bbf6381052ee9e7f33925c954d52';

      final sourcePath = pathResolver.stagingPartPath('op-b2');
      await fileSystem.appendBytes(sourcePath, bytes);

      final snapshot = CatalogArtifactSnapshot(
        catalogId: 'aura-official-test',
        catalogRevision: 1,
        catalogSchemaVersion: '1.0',
        signingKeyId: 'test-key-1',
        trustLevel: CatalogTrustLevel.signatureVerified,
        artifactId: 'model-b2',
        artifactVersion: '1.0.0',
        buildId: 'v1',
        fileName: 'model_b2.gguf',
        sizeBytes: 100,
        sha256: sha,
        acquiredAtUtc: baseTime,
      );

      // Prima installazione riuscita
      final prepared1 = await ingestionEngine.ingestAndVerifyToTemporaryStore(
        sourceFilePath: sourcePath,
        operationId: 'op-b2',
        provenanceSnapshot: snapshot,
        sourceOwnership: ArtifactSourceOwnership.managedStaging,
      );
      final result1 = await coordinator.registerVerifiedArtifact(
        installation: prepared1,
        operationId: 'op-b2',
      );
      expect(result1.status, equals(ProvisioningStatus.success));
      expect(result1.alreadyInstalled, isFalse);

      // Seconda ingestione con stessa fingerprint (simulazione retry)
      await fileSystem.appendBytes(sourcePath, bytes);
      final prepared2 = await ingestionEngine.ingestAndVerifyToTemporaryStore(
        sourceFilePath: sourcePath,
        operationId: 'op-b2-retry',
        provenanceSnapshot: snapshot,
        sourceOwnership: ArtifactSourceOwnership.managedStaging,
      );

      // B2: il target finale esiste con stessa fingerprint → idempotent
      final result2 = await coordinator.registerVerifiedArtifact(
        installation: prepared2,
        operationId: 'op-b2-retry',
      );

      // Il coordinator risponde con alreadyInstalled (via record globale idempotency)
      expect(result2.status, equals(ProvisioningStatus.alreadyInstalled));
      expect(result2.alreadyInstalled, isTrue);
      // Il target finale NON viene eliminato: esiste ancora
      expect(
          await fileSystem.directoryExists(prepared1.finalInstallPath), isTrue);
    });

    test('Reconciliation ignora directory .installing-* residue', () async {
      // Crea una directory .installing residua nella gerarchia dei modelli
      final modelsRoot = r'C:\AURA\app_managed\models';
      final orphanInstalling =
          '$modelsRoot\\model-installing\\1.0.0.installing-op-stale';
      await fileSystem.createDirectory(orphanInstalling);

      // Anche con marker valido nella installing residua, non deve essere riconciliata
      await fileSystem.writeAsString(
        '$orphanInstalling\\commit.marker',
        '{"schemaVersion":"1.0","artifactId":"model-installing","artifactVersion":"1.0.0","buildId":"v1","sha256":"${'a' * 64}","preparedAtUtc":"2026-07-27T20:00:00.000Z"}',
      );

      final count = await coordinator.reconcileUnindexedInstallations();
      expect(count, equals(0));
    });

    test(
        'Finding 1 — Record globale presente ma target fisico assente → non restituisce già installato, procede con l\'installazione',
        () async {
      final bytes = List.generate(100, (i) => i);
      const sha =
          'bce0aff19cf5aa6a7469a30d61d04e4376e4bbf6381052ee9e7f33925c954d52';

      final sourcePath = pathResolver.stagingPartPath('op-f1');
      await fileSystem.appendBytes(sourcePath, bytes);

      final snapshot = CatalogArtifactSnapshot(
        catalogId: 'aura-official-test',
        catalogRevision: 1,
        catalogSchemaVersion: '1.0',
        signingKeyId: 'test-key-1',
        trustLevel: CatalogTrustLevel.signatureVerified,
        artifactId: 'model-f1',
        artifactVersion: '1.0.0',
        buildId: 'v1',
        fileName: 'model_f1.gguf',
        sizeBytes: 100,
        sha256: sha,
        acquiredAtUtc: baseTime,
      );

      // 1. Prima installazione
      final prepared1 = await ingestionEngine.ingestAndVerifyToTemporaryStore(
        sourceFilePath: sourcePath,
        operationId: 'op-f1-1',
        provenanceSnapshot: snapshot,
        sourceOwnership: ArtifactSourceOwnership.managedStaging,
      );
      final res1 = await coordinator.registerVerifiedArtifact(
        installation: prepared1,
        operationId: 'op-f1-1',
      );
      expect(res1.status, equals(ProvisioningStatus.success));

      // 2. Simuliamo la cancellazione fisica/corruzione accidentale del target su disco
      await fileSystem.deleteDirectory(prepared1.finalInstallPath);
      expect(await fileSystem.directoryExists(prepared1.finalInstallPath),
          isFalse);

      // 3. Nuova richiesta di installazione con stessa provenienza
      await fileSystem.appendBytes(sourcePath, bytes);
      final prepared2 = await ingestionEngine.ingestAndVerifyToTemporaryStore(
        sourceFilePath: sourcePath,
        operationId: 'op-f1-2',
        provenanceSnapshot: snapshot,
        sourceOwnership: ArtifactSourceOwnership.managedStaging,
      );

      // Il record globale dice "stessa versione e sha", ma il check FISICO fallisce (assente)
      // Pertanto NON deve restituire già installato, ma procedere con l'installazione!
      final res2 = await coordinator.registerVerifiedArtifact(
        installation: prepared2,
        operationId: 'op-f1-2',
      );

      expect(res2.status, equals(ProvisioningStatus.success));
      expect(res2.alreadyInstalled, isFalse);
      expect(
          await fileSystem.directoryExists(prepared1.finalInstallPath), isTrue);
    });

    test(
        'Finding 4 — finalPath presente come file ordinario → restituisce installationConflict',
        () async {
      final bytes = List.generate(100, (i) => i);
      const sha =
          'bce0aff19cf5aa6a7469a30d61d04e4376e4bbf6381052ee9e7f33925c954d52';

      final sourcePath = pathResolver.stagingPartPath('op-f4');
      await fileSystem.appendBytes(sourcePath, bytes);

      final snapshot = CatalogArtifactSnapshot(
        catalogId: 'aura-official-test',
        catalogRevision: 1,
        catalogSchemaVersion: '1.0',
        signingKeyId: 'test-key-1',
        trustLevel: CatalogTrustLevel.signatureVerified,
        artifactId: 'model-f4',
        artifactVersion: '1.0.0',
        buildId: 'v1',
        fileName: 'model_f4.gguf',
        sizeBytes: 100,
        sha256: sha,
        acquiredAtUtc: baseTime,
      );

      final prepared = await ingestionEngine.ingestAndVerifyToTemporaryStore(
        sourceFilePath: sourcePath,
        operationId: 'op-f4',
        provenanceSnapshot: snapshot,
        sourceOwnership: ArtifactSourceOwnership.managedStaging,
      );

      // Creiamo un file ordinario al percorso finalInstallPath anziché una directory
      await fileSystem.writeAsString(prepared.finalInstallPath, 'i am a file');

      final result = await coordinator.registerVerifiedArtifact(
        installation: prepared,
        operationId: 'op-f4',
      );

      expect(result.status, equals(ProvisioningStatus.failed));
      expect(result.failureReason,
          equals(ProvisioningFailureReason.installationConflict));

      expect(result.sanitizedMessage, contains('file anziché una directory'));
    });
  });
}
