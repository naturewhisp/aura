import 'dart:io';
import 'package:aura_core/aura_core.dart';
import 'package:test/test.dart';

void main() {
  group('ActivationStateRepository Tests -', () {
    late Directory tempAppRoot;
    late Directory tempBundledRoot;
    late ProvisioningPathResolver pathResolver;
    late JsonActivationStateRepository repo;

    setUp(() async {
      tempAppRoot =
          await Directory.systemTemp.createTemp('aura_act_state_test_app_');
      tempBundledRoot =
          await Directory.systemTemp.createTemp('aura_act_state_test_bundled_');
      pathResolver = ProvisioningPathResolver(
        appManagedRoot: tempAppRoot.path,
        bundledRoot: tempBundledRoot.path,
      );
      repo = JsonActivationStateRepository(pathResolver: pathResolver);
    });

    tearDown(() async {
      if (await tempAppRoot.exists()) {
        await tempAppRoot.delete(recursive: true);
      }
      if (await tempBundledRoot.exists()) {
        await tempBundledRoot.delete(recursive: true);
      }
    });

    test('Restituisce stato vuoto se il file non esiste', () async {
      final state = await repo.readState();
      expect(state.schemaVersion, equals('1.0'));
      expect(state.activeRuntimeId, isNull);
      expect(state.activeModelId, isNull);
    });

    test('Scrive atomicamente e rilegge correttamente l ActivationState',
        () async {
      final stateToSave = ActivationState(
        schemaVersion: '1.0',
        updatedAt: '2026-07-21T21:00:00Z',
        activeRuntimeId: 'llama-b3500',
        activeRuntimeVersion: 'b3500',
        activeModelId: 'ministral-3b',
        activeModelVersion: 'q4_k_m',
      );

      await repo.writeState(stateToSave);

      final loaded = await repo.readState();
      expect(loaded.schemaVersion, equals('1.0'));
      expect(loaded.activeRuntimeId, equals('llama-b3500'));
      expect(loaded.activeRuntimeVersion, equals('b3500'));
      expect(loaded.activeModelId, equals('ministral-3b'));
      expect(loaded.activeModelVersion, equals('q4_k_m'));
    });

    test('Supporta l azzeramento esplicito dei campi tramite copyWith sentinel',
        () {
      final state = ActivationState(
        updatedAt: '2026-07-21T21:00:00Z',
        activeRuntimeId: 'rt-1',
        activeModelId: 'm-1',
      );

      final cleared = state.copyWith(
        activeRuntimeId: null,
        activeModelId: null,
      );

      expect(cleared.activeRuntimeId, isNull);
      expect(cleared.activeModelId, isNull);
    });
  });
}
