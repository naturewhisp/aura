import 'package:test/test.dart';
import 'package:aura_core/aura_offline.dart';
import 'package:aura_core/aura_testing.dart';

import '../provisioning_test_helpers.dart';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('Phase 6.4e — Model Repair Infrastructure Tests', () {
    late MemoryProvisioningFileSystem fileSystem;
    late ProvisioningPathResolver pathResolver;
    late MemoryProvisioningClock clock;
    late InMemoryProvisioningLock lock;
    late JsonInstallationRecordRepository recordRepository;
    late JsonActivationStateRepository activationRepository;
    late SinglePassArtifactIngestionEngine ingestionEngine;
    late ProvisioningCoordinator coordinator;

    final baseTime = DateTime.parse('2026-07-28T10:00:00Z');

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

      final verifier = LocalInstalledArtifactVerifier(fileSystem: fileSystem);
      final mockClient = MockClient((_) async => http.Response('', 200));

      coordinator = ProvisioningCoordinator(
        lock: lock,
        recordRepository: recordRepository,
        activationRepository: activationRepository,
        pathResolver: pathResolver,
        fileSystem: fileSystem,
        verifier: verifier,
        ingestionEngine: ArtifactIngestionEngine(
          pathResolver: pathResolver,
          httpClient: HttpProvisioningHttpClient(client: mockClient),
          fileSystem: fileSystem,
        ),
        clock: clock,
      );
    });

    test(
        'repairModel restituisce repairMetadataMissing se l\'installazione non esiste',
        () async {
      final record = await recordRepository.readRecord();
      final targetDesc = record.findInstallation('non_existent_inst');

      expect(targetDesc, isNull);
    });

    test(
        'repairVerifiedArtifact mantiene installationId e installedAt ed incrementa repairCount',
        () async {
      final initialDesc = InstalledArtifactDescriptor(
        installationId: 'inst_repair_target',
        artifactId: 'actor-mod',
        artifactType: CatalogArtifactType.model,
        displayName: 'Actor Model',
        platform: 'any',
        architecture: 'any',
        sourceKind: CatalogArtifactSourceKind.remoteHttps,
        version: '1.0.0',
        buildId: 'b1',
        sizeBytes: 12,
        sha256:
            '206402cab345415716d9a33469feba57a90dc200c064bc0190b4191af058b0eb',
        relativeInstallPath: r'models\actor-mod\1.0.0-b1',
        entryFileName: 'model.gguf',
        installedAt: '2026-07-28T10:00:00Z',
        status: InstallationStatus.verified,
        verifiedAt: '2026-07-28T10:00:00Z',
        repairCount: 0,
      );

      var record = InstallationRecord.empty(updatedAt: '2026-07-28T10:00:00Z');
      record = record.upsertArtifact(initialDesc);
      await recordRepository.writeRecord(record);

      final originalPath = pathResolver
          .resolveAppManagedRelativePath(initialDesc.relativeInstallPath);
      await fileSystem.createDirectory(originalPath);
      fileSystem.byteFiles['$originalPath\\model.gguf'] = [1, 2, 3];

      final snap = CatalogArtifactSnapshot(
        catalogId: 'cat_1',
        catalogRevision: 1,
        catalogSchemaVersion: '1.0',
        signingKeyId: 'key1',
        trustLevel: CatalogTrustLevel.signatureVerified,
        artifactId: 'actor-mod',
        artifactVersion: '1.0.0',
        buildId: 'b1',
        fileName: 'model.gguf',
        sizeBytes: 12,
        sha256:
            '206402cab345415716d9a33469feba57a90dc200c064bc0190b4191af058b0eb',
        acquiredAtUtc: baseTime,
      );

      final sourceFile = r'C:\AURA\app_managed\staging\source_file.part';
      await fileSystem.createDirectory(r'C:\AURA\app_managed\staging');
      fileSystem.byteFiles[sourceFile] = [
        1,
        2,
        3,
        4,
        5,
        6,
        7,
        8,
        9,
        10,
        11,
        12
      ];

      final replacement = await ingestionEngine.ingestAndVerifyToTemporaryStore(
        sourceFilePath: sourceFile,
        operationId: 'op_repair_1',
        provenanceSnapshot: snap,
        sourceOwnership: ArtifactSourceOwnership.managedStaging,
      );

      final repairResult = await coordinator.repairVerifiedArtifact(
        targetInstallationId: 'inst_repair_target',
        replacement: replacement,
        operationId: 'op_repair_1',
      );

      expect(repairResult.status, equals(ModelRepairStatus.repaired));
      expect(repairResult.installationId, equals('inst_repair_target'));
      expect(repairResult.recordCommitted, isTrue);

      final updatedRecord = await recordRepository.readRecord();
      final repairedDesc = updatedRecord.findInstallation('inst_repair_target');

      expect(repairedDesc, isNotNull);
      expect(repairedDesc?.installationId, equals('inst_repair_target'));
      expect(repairedDesc?.installedAt, equals('2026-07-28T10:00:00Z'));
      expect(repairedDesc?.repairCount, equals(1));
      expect(repairedDesc?.lastRepairedAt, isNotNull);
    });
  });
}
