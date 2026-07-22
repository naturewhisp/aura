import 'dart:convert';
import 'package:aura_core/aura_core.dart';
import 'package:test/test.dart';
import 'installation_record_repository_test.dart';

void main() {
  group('ActivationStateRepository Tests -', () {
    late ProvisioningPathResolver pathResolver;
    late MemoryProvisioningFileSystem fileSystem;
    late TestProvisioningClock clock;
    late ProvisioningLock sharedLock;
    late JsonActivationStateRepository repo;

    setUp(() {
      pathResolver = ProvisioningPathResolver(
        appManagedRoot: r'C:\AppManaged\Aura',
        bundledRoot: r'C:\Program Files\Aura',
      );
      fileSystem = MemoryProvisioningFileSystem();
      clock = TestProvisioningClock(DateTime.utc(2026, 7, 21, 21, 0, 0));
      sharedLock = InMemoryProvisioningLock();
      repo = JsonActivationStateRepository(
        pathResolver: pathResolver,
        lock: sharedLock,
        fileSystem: fileSystem,
        clock: clock,
      );
    });

    test('Restituisce stato vuoto se il file non esiste', () async {
      final state = await repo.readState();
      expect(state.schemaVersion, equals('1.1'));
      expect(state.activeRuntimeInstallationId, isNull);
      expect(state.activeModelInstallationId, isNull);
    });

    test(
        'Scrive e legge l ActivationState basato su installationId stabili ed enum tipizzati',
        () async {
      final stateToSave = ActivationState(
        updatedAt: '2026-07-21T21:00:00.000Z',
        activeRuntimeInstallationId: 'inst-llama-b3500-1',
        activeModelInstallationId: 'inst-ministral-3b-1',
        lastKnownGoodRuntimeInstallationId: 'inst-llama-b3500-1',
        lastKnownGoodModelInstallationId: 'inst-ministral-3b-1',
        runtimeSourcePreference: RuntimeSourcePreference.appManaged,
        fallbackPolicy:
            ProvisionedFallbackPolicy.managedLlamaServerWithRuleBasedFallback,
        explicitUserSelection: true,
      );

      final saved = await repo.replaceState(stateToSave);
      expect(saved.updatedAt, equals('2026-07-21T21:00:00.000Z'));

      final loaded = await repo.readState();
      expect(loaded.activeRuntimeInstallationId, equals('inst-llama-b3500-1'));
      expect(loaded.activeModelInstallationId, equals('inst-ministral-3b-1'));
      expect(loaded.runtimeSourcePreference,
          equals(RuntimeSourcePreference.appManaged));
      expect(
          loaded.fallbackPolicy,
          equals(ProvisionedFallbackPolicy
              .managedLlamaServerWithRuleBasedFallback));
      expect(loaded.explicitUserSelection, isTrue);
    });

    test(
        'updateState serializza transazionalmente le modifiche restituendo l istanza persistita',
        () async {
      final result = await repo.updateState((current) {
        return current.copyWith(
          activeRuntimeInstallationId: 'inst-runtime-2',
        );
      });

      expect(result.activeRuntimeInstallationId, equals('inst-runtime-2'));
      expect(result.updatedAt, equals('2026-07-21T21:00:00.000Z'));

      final updated = await repo.readState();
      expect(updated.activeRuntimeInstallationId, equals('inst-runtime-2'));
    });

    test(
        'Esegue il recovery da .bak per active_state corrotto senza sovrascrivere il backup valido',
        () async {
      final statePath = pathResolver.activeStatePath;
      final backupPath = '$statePath.bak';

      final validState = ActivationState(
        updatedAt: '2026-07-21T20:00:00.000Z',
        activeRuntimeInstallationId: 'inst-recovered-rt',
        activeModelInstallationId: 'inst-recovered-model',
      );

      fileSystem.files[backupPath] = jsonEncode(validState.toJson());
      fileSystem.files[statePath] = ''; // file vuoto corrotto

      final recovered = await repo.readState();
      expect(
          recovered.activeRuntimeInstallationId, equals('inst-recovered-rt'));
      expect(
          recovered.activeModelInstallationId, equals('inst-recovered-model'));
      expect(fileSystem.files[backupPath], contains('inst-recovered-rt'));
    });
  });
}
