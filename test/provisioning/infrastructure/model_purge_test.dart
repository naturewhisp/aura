import 'package:test/test.dart';
import 'package:aura_core/aura_offline.dart';

import '../provisioning_test_helpers.dart';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('Phase 6.4e — Model Purge Infrastructure Tests', () {
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
        'purgeInstallation con policy reject su installazione attiva rifiuta la rimozione',
        () async {
      final inst1 = InstalledArtifactDescriptor(
        installationId: 'inst_active',
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
        installedAt: '2026-07-28T10:00:00Z',
        status: InstallationStatus.verified,
        verifiedAt: '2026-07-28T10:00:00Z',
      );

      var record = InstallationRecord.empty(updatedAt: '2026-07-28T10:00:00Z');
      record = record.upsertArtifact(inst1);
      await recordRepository.writeRecord(record);

      final state = ActivationState(
        updatedAt: '2026-07-28T10:00:00Z',
        activeActorModelInstallationId: 'inst_active',
      );
      await activationRepository.replaceState(state);

      final res = await coordinator.purgeInstallation(
        operationId: 'op_purge_1',
        installationId: 'inst_active',
        activePurgePolicy: ActiveInstallationPurgePolicy.reject,
      );

      expect(res.status, equals(ModelPurgeStatus.purgeRejectedActive));
      expect(res.isSuccess, isFalse);
    });

    test(
        'purgeInstallation con policy fallbackToPreviousVerified commuta all\'installazione precedente e rimuove la target',
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

      final inst2 = InstalledArtifactDescriptor(
        installationId: 'inst_v2',
        artifactId: 'actor-mod',
        artifactType: CatalogArtifactType.model,
        displayName: 'Actor Model',
        platform: 'any',
        architecture: 'any',
        sourceKind: CatalogArtifactSourceKind.remoteHttps,
        version: '2.0.0',
        buildId: 'b2',
        sizeBytes: 3,
        sha256:
            '039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81',
        relativeInstallPath: 'models/actor-mod/2.0.0-b2',
        entryFileName: 'model.gguf',
        installedAt: '2026-07-28T10:05:00Z',
        status: InstallationStatus.verified,
        verifiedAt: '2026-07-28T10:05:00Z',
      );

      var record = InstallationRecord.empty(updatedAt: '2026-07-28T10:00:00Z');
      record = record.upsertArtifact(inst1).upsertArtifact(inst2);
      await recordRepository.writeRecord(record);

      final path1 =
          pathResolver.resolveAppManagedRelativePath(inst1.relativeInstallPath);
      await fileSystem.createDirectory(path1);
      await fileSystem.writeBytes('$path1\\model.gguf', [1, 2, 3]);

      final path2 =
          pathResolver.resolveAppManagedRelativePath(inst2.relativeInstallPath);
      await fileSystem.createDirectory(path2);
      await fileSystem.writeBytes('$path2\\model.gguf', [1, 2, 3]);

      final state = ActivationState(
        updatedAt: '2026-07-28T10:05:00Z',
        activeActorModelInstallationId: 'inst_v2',
      );
      await activationRepository.replaceState(state);

      final res = await coordinator.purgeInstallation(
        operationId: 'op_purge_2',
        installationId: 'inst_v2',
        activePurgePolicy:
            ActiveInstallationPurgePolicy.fallbackToPreviousVerified,
      );

      expect(res.isSuccess, isTrue);
      expect(res.fallbackInstallationId, equals('inst_v1'));

      final updatedState = await activationRepository.readState();
      expect(updatedState.activeActorModelInstallationId, equals('inst_v1'));

      final updatedRecord = await recordRepository.readRecord();
      expect(updatedRecord.findInstallation('inst_v2')?.status,
          equals(InstallationStatus.removed));
    });

    test(
        'purgeInstallation con fallbackToPreviousVerified RIFIUTA il fallback se esiste solo una versione SUCCESSIVA (non precedente)',
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

      final inst2 = InstalledArtifactDescriptor(
        installationId: 'inst_v2',
        artifactId: 'actor-mod',
        artifactType: CatalogArtifactType.model,
        displayName: 'Actor Model',
        platform: 'any',
        architecture: 'any',
        sourceKind: CatalogArtifactSourceKind.remoteHttps,
        version: '2.0.0',
        buildId: 'b2',
        sizeBytes: 3,
        sha256:
            '039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81',
        relativeInstallPath: 'models/actor-mod/2.0.0-b2',
        entryFileName: 'model.gguf',
        installedAt: '2026-07-28T10:05:00Z',
        status: InstallationStatus.verified,
        verifiedAt: '2026-07-28T10:05:00Z',
      );

      var record = InstallationRecord.empty(updatedAt: '2026-07-28T10:00:00Z');
      record = record.upsertArtifact(inst1).upsertArtifact(inst2);
      await recordRepository.writeRecord(record);

      final path1 =
          pathResolver.resolveAppManagedRelativePath(inst1.relativeInstallPath);
      await fileSystem.createDirectory(path1);
      await fileSystem.writeBytes('$path1\\model.gguf', [1, 2, 3]);

      final path2 =
          pathResolver.resolveAppManagedRelativePath(inst2.relativeInstallPath);
      await fileSystem.createDirectory(path2);
      await fileSystem.writeBytes('$path2\\model.gguf', [1, 2, 3]);

      // Attiviamo la versione v1
      final state = ActivationState(
        updatedAt: '2026-07-28T10:05:00Z',
        activeActorModelInstallationId: 'inst_v1',
      );
      await activationRepository.replaceState(state);

      final res = await coordinator.purgeInstallation(
        operationId: 'op_purge_3',
        installationId: 'inst_v1',
        activePurgePolicy:
            ActiveInstallationPurgePolicy.fallbackToPreviousVerified,
      );

      // Eliminando v1 (1.0.0), v2 (2.0.0) NON e una versione precedente: il fallback non e disponibile!
      expect(res.status, equals(ModelPurgeStatus.fallbackUnavailable));
      expect(res.isSuccess, isFalse);
    });
  });
}
