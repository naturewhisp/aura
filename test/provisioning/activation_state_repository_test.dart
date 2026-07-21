import 'dart:convert';
import 'package:aura_core/aura_core.dart';
import 'package:test/test.dart';
import 'installation_record_repository_test.dart';

void main() {
  group('ActivationStateRepository Tests -', () {
    late ProvisioningPathResolver pathResolver;
    late MemoryProvisioningFileSystem fileSystem;
    late TestProvisioningClock clock;
    late JsonActivationStateRepository repo;

    setUp(() {
      pathResolver = ProvisioningPathResolver(
        appManagedRoot: r'C:\AppManaged\Aura',
        bundledRoot: r'C:\Program Files\Aura',
      );
      fileSystem = MemoryProvisioningFileSystem();
      clock = TestProvisioningClock(DateTime.utc(2026, 7, 21, 21, 0, 0));
      repo = JsonActivationStateRepository(
        pathResolver: pathResolver,
        fileSystem: fileSystem,
        clock: clock,
      );
    });

    test('Restituisce stato vuoto se il file non esiste', () async {
      final state = await repo.readState();
      expect(state.schemaVersion, equals('1.0'));
      expect(state.activeRuntimeInstallationId, isNull);
      expect(state.activeModelInstallationId, isNull);
    });

    test('Scrive e legge l ActivationState basato su installationId stabili',
        () async {
      final stateToSave = ActivationState(
        updatedAt: '2026-07-21T21:00:00Z',
        activeRuntimeInstallationId: 'inst-llama-b3500-1',
        activeModelInstallationId: 'inst-ministral-3b-1',
        lastKnownGoodRuntimeInstallationId: 'inst-llama-b3500-1',
        lastKnownGoodModelInstallationId: 'inst-ministral-3b-1',
        runtimeSourcePreference: 'appManaged',
        fallbackPolicy: 'managedLlamaServerWithRuleBasedFallback',
        explicitUserSelection: true,
      );

      await repo.writeState(stateToSave);

      final loaded = await repo.readState();
      expect(loaded.activeRuntimeInstallationId, equals('inst-llama-b3500-1'));
      expect(loaded.activeModelInstallationId, equals('inst-ministral-3b-1'));
      expect(loaded.lastKnownGoodRuntimeInstallationId,
          equals('inst-llama-b3500-1'));
      expect(loaded.explicitUserSelection, isTrue);
    });

    test(
        'Esegue il recovery automatico da .bak se il file primario di active_state è corrotto',
        () async {
      final statePath = pathResolver.activeStatePath;
      final backupPath = '$statePath.bak';

      final validState = ActivationState(
        updatedAt: '2026-07-21T20:00:00Z',
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
      expect(fileSystem.files[statePath], isNotEmpty);
    });
  });
}
