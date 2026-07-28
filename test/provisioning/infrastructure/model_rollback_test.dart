import 'package:test/test.dart';
import 'package:aura_core/aura_offline.dart';

import '../provisioning_test_helpers.dart';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('Phase 6.4e — Model Rollback Infrastructure Tests', () {
    late MemoryProvisioningFileSystem fileSystem;
    late ProvisioningPathResolver pathResolver;
    late MemoryProvisioningClock clock;
    late InMemoryProvisioningLock lock;
    late JsonInstallationRecordRepository recordRepository;
    late JsonActivationStateRepository activationRepository;
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
        'rollbackInstallation restituisce staleCurrentActivation se l\'attivazione corrente differisce da quella attesa',
        () async {
      final state = ActivationState(
        updatedAt: '2026-07-28T10:00:00Z',
        activeActorModelInstallationId: 'inst_v1',
      );
      await activationRepository.replaceState(state);

      final res = await coordinator.rollbackInstallation(
        operationId: 'op_rollback_1',
        artifactId: 'actor-mod',
        modelRole: ModelActivationRole.actor,
        targetInstallationId: 'inst_v2',
        expectedCurrentInstallationId: 'inst_unexpected',
      );

      expect(res.status, equals(ModelRollbackStatus.staleCurrentActivation));
      expect(res.isSuccess, isFalse);
    });

    test(
        'rollbackInstallation restituisce alreadyActive se la destinazione è già attiva',
        () async {
      final state = ActivationState(
        updatedAt: '2026-07-28T10:00:00Z',
        activeActorModelInstallationId: 'inst_v2',
      );
      await activationRepository.replaceState(state);

      final res = await coordinator.rollbackInstallation(
        operationId: 'op_rollback_2',
        artifactId: 'actor-mod',
        modelRole: ModelActivationRole.actor,
        targetInstallationId: 'inst_v2',
      );

      expect(res.status, equals(ModelRollbackStatus.alreadyActive));
      expect(res.isSuccess, isTrue);
    });

    test(
        'rollbackInstallation esegue lo switch atomico se il target è verified e fisicamente sano',
        () async {
      final inst1 = InstalledArtifactDescriptor(
        installationId: 'inst_v1',
        artifactId: 'actor-mod',
        artifactType: CatalogArtifactType.model,
        displayName: 'Actor Model',
        platform: 'any',
        architecture: 'any',
        sourceKind: CatalogArtifactSourceKind.remoteHttps,
        version: '1.0.0',
        buildId: 'b1',
        sizeBytes: 3,
        sha256:
            '039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81',
        relativeInstallPath: 'models/actor-mod/1.0.0-b1',
        entryFileName: 'model.gguf',
        installedAt: '2026-07-28T10:00:00Z',
        status: InstallationStatus.verified,
        verifiedAt: '2026-07-28T10:00:00Z',
      );

      var record = InstallationRecord.empty(updatedAt: '2026-07-28T10:00:00Z');
      record = record.upsertArtifact(inst1);
      await recordRepository.writeRecord(record);

      final state = ActivationState(
        updatedAt: '2026-07-28T10:00:00Z',
        activeActorModelInstallationId: 'inst_v2',
      );
      await activationRepository.replaceState(state);

      final path1 =
          pathResolver.resolveAppManagedRelativePath(inst1.relativeInstallPath);
      await fileSystem.createDirectory(path1);
      await fileSystem.writeBytes('$path1\\model.gguf', [1, 2, 3]);

      final res = await coordinator.rollbackInstallation(
        operationId: 'op_rollback_3',
        artifactId: 'actor-mod',
        modelRole: ModelActivationRole.actor,
        targetInstallationId: 'inst_v1',
      );

      expect(res.status, equals(ModelRollbackStatus.rolledBack));
      expect(res.isSuccess, isTrue);

      final updatedState = await activationRepository.readState();
      expect(updatedState.activeActorModelInstallationId, equals('inst_v1'));
    });
  });
}
