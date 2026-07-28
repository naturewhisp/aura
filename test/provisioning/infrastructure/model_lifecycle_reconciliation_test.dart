import 'package:test/test.dart';
import 'package:aura_core/aura_offline.dart';
import 'package:aura_core/aura_testing.dart';

import '../provisioning_test_helpers.dart';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('Phase 6.4e — Model Lifecycle Reconciliation Infrastructure Tests', () {
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
        'reconcileLifecycleTransactions rimuove residui .repairing-*, trash ed aggiusta dangling pointers',
        () async {
      final repairDir = r'C:\AURA\app_managed\staging\op_1.repairing-inst_x';
      final trashDir = r'C:\AURA\app_managed\staging\trash\inst_y_op2';

      await fileSystem.createDirectory(repairDir);
      await fileSystem.createDirectory(trashDir);
      await fileSystem.writeBytes('$repairDir\\file.tmp', [1, 2, 3]);
      await fileSystem.writeBytes('$trashDir\\file.tmp', [1, 2, 3]);

      // Attivazione che punta ad un'installazione inesistente nel record
      final state = ActivationState(
        updatedAt: '2026-07-28T10:00:00Z',
        activeActorModelInstallationId: 'dangling_inst',
      );
      await activationRepository.replaceState(state);

      final reconResult = await coordinator.reconcileLifecycleTransactions();

      expect(reconResult.purgedTrashCount, equals(1));
      expect(
          reconResult.unresolvedRoleMismatchCount +
              reconResult.resolvedDanglingActivationsCount,
          equals(1));
      expect(reconResult.totalActionsPerformed, greaterThan(0));

      final updatedState = await activationRepository.readState();
      expect(updatedState.activeActorModelInstallationId, isNull);
    });

    test(
        'reconcileLifecycleTransactions non attiva MAI un modello evaluator per un ruolo actor dangling',
        () async {
      final evaluatorDesc = InstalledArtifactDescriptor(
        installationId: 'inst_evaluator_only',
        artifactId: 'evaluator-mod',
        artifactType: CatalogArtifactType.model,
        displayName: 'Evaluator Model',
        platform: 'any',
        architecture: 'any',
        sourceKind: CatalogArtifactSourceKind.remoteHttps,
        version: '1.0.0',
        buildId: 'b1',
        sizeBytes: 3,
        sha256:
            '039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81',
        relativeInstallPath: 'models/evaluator-mod/1.0.0-b1',
        entryFileName: 'model.gguf',
        installedAt: '2026-07-28T10:00:00Z',
        status: InstallationStatus.verified,
        verifiedAt: '2026-07-28T10:00:00Z',
      );

      var record = InstallationRecord.empty(updatedAt: '2026-07-28T10:00:00Z');
      record = record.upsertArtifact(evaluatorDesc);
      await recordRepository.writeRecord(record);

      final path1 = pathResolver
          .resolveAppManagedRelativePath(evaluatorDesc.relativeInstallPath);
      await fileSystem.createDirectory(path1);
      await fileSystem.writeBytes('$path1\\model.gguf', [1, 2, 3]);

      final state = ActivationState(
        updatedAt: '2026-07-28T10:00:00Z',
        activeActorModelInstallationId: 'dangling_actor_inst',
      );
      await activationRepository.replaceState(state);

      final reconResult = await coordinator.reconcileLifecycleTransactions();

      final updatedState = await activationRepository.readState();
      expect(updatedState.activeActorModelInstallationId, isNull,
          reason: 'Il ruolo actor non deve ereditare un modello evaluator.');
      expect(
          reconResult.unresolvedRoleMismatchCount +
              reconResult.deactivatedNoFallbackCount,
          equals(1));
    });

    test(
        'reconcileLifecycleTransactions rifiuta la promozione di una .repairing-* se i metadati locale o marker sono incoerenti',
        () async {
      final desc = InstalledArtifactDescriptor(
        installationId: 'inst_repair_test',
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
      record = record.upsertArtifact(desc);
      await recordRepository.writeRecord(record);

      final targetPath =
          pathResolver.resolveAppManagedRelativePath(desc.relativeInstallPath);
      // Non creiamo il targetPath (o creiamo un target fisicamente corrotto)
      await fileSystem.createDirectory(targetPath);
      await fileSystem
          .writeBytes('$targetPath\\model.gguf', [9, 9, 9]); // Corrotto!

      final repairingDir = '${targetPath}.repairing-op1';
      await fileSystem.createDirectory(repairingDir);
      await fileSystem
          .writeBytes('$repairingDir\\model.gguf', [1, 2, 3]); // GGUF valido

      // Ma lasciamo marker o record con artifactId INCOERENTE!
      await fileSystem.writeStringRecoverably(
        '$repairingDir\\installation_record.json',
        '{"artifactId": "WRONG_ID", "version": "1.0.0"}',
      );
      await fileSystem.writeStringRecoverably(
        '$repairingDir\\commit.marker',
        '{"schemaVersion": "1.0", "artifactId": "WRONG_ID"}',
      );

      final reconResult = await coordinator.reconcileLifecycleTransactions();

      // Poiche i metadati della .repairing-* sono incoerenti, NON viene promossa!
      final repairingExists = await fileSystem.directoryExists(repairingDir);
      expect(repairingExists, isFalse,
          reason: 'La directory .repairing-* non valida viene eliminata.');
      expect(reconResult.cleanedStaleTempCount, greaterThan(0));
    });
  });
}
