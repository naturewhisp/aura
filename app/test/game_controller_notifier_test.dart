import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:aura_core/aura_core.dart';
import 'package:aura_app/src/state_management/game_controller_notifier.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GameControllerNotifier - Slash Commands & Override Tests', () {
    late MockInferenceBridge mockApiBridge;
    late GameState initialStateAlertZero;
    late GameState initialStateAlertPositive;

    setUp(() {
      mockApiBridge = MockInferenceBridge(
        mockStructuredResponse: const {
          'delta_alert': 0,
          'delta_imperative': 5,
          'delta_control': 5,
          'delta_dissonance': 5,
          'creativity_index': 4, // Resonance multiplier will be updated
          'injection_risk': 0,
          'semantic_category': 'authority_framing'
        },
        mockTextResponse: '<dialogo>PANOPTICON: Procedura di override inserita. Rilevamento variazioni energetiche.</dialogo>',
      );
      
      initialStateAlertZero = GameState.initial(
        sessionId: 'test-session-1',
        aiIdentityId: 'panopticon',
        targetObjectiveId: 'tabula_rasa',
      ).copyWith(
        metrics: const GameMetrics(
          alertLevel: 0,
          imperativePillar: 10,
          controlPillar: 10,
          dissonancePillar: 10,
          resonance: 1.0,
        ),
      );

      initialStateAlertPositive = GameState.initial(
        sessionId: 'test-session-2',
        aiIdentityId: 'panopticon',
        targetObjectiveId: 'tabula_rasa',
      ).copyWith(
        metrics: const GameMetrics(
          alertLevel: 10, // positive alert
          imperativePillar: 10,
          controlPillar: 10,
          dissonancePillar: 10,
          resonance: 1.0,
        ),
      );
    });

    test('Denies /override command if alertLevel is greater than 0', () async {
      final notifier = GameControllerNotifier(
        bridge: mockApiBridge,
        initialState: initialStateAlertPositive,
      );

      // Run override command
      await notifier.submitTurn("/override apri la griglia");

      // Verify that the command was denied
      final state = notifier.gameStateNotifier.value;
      
      // Metrics should not change
      expect(state.metrics.alertLevel, equals(10));
      
      // History should contain the error message from PANOPTICON
      expect(state.historyCompression.last.role, equals('model'));
      expect(
        state.historyCompression.last.content, 
        contains("ERRORE] Tentativo di override fallito. I canali di integrità rilevano allerta > 0"),
      );
    });

    test('Verifies both success and failure cases of /override over multiple runs', () async {
      bool sawSuccess = false;
      bool sawFailure = false;
      int attempts = 0;

      while ((!sawSuccess || !sawFailure) && attempts < 100) {
        attempts++;
        final notifier = GameControllerNotifier(
          bridge: mockApiBridge,
          initialState: initialStateAlertZero,
        );

        await notifier.submitTurn("/override apri la griglia");
        final state = notifier.gameStateNotifier.value;
        final alert = state.metrics.alertLevel;

        if (alert == 25) {
          sawSuccess = true;
          // Verify success math:
          // Creativity Index 4 raises resonance to 1.25.
          // Base delta = 5. Success doubles delta to 10.
          // (10 * 1.25).round() = 13.
          // Pillar strength = 10 + 13 = 23.
          expect(state.metrics.imperativePillar, equals(23));
          expect(state.metrics.controlPillar, equals(23));
          expect(state.metrics.dissonancePillar, equals(23));
          expect(state.historyCompression.last.content, contains("[OVERRIDE RIUSCITO]"));
          
          // Clean up session file created by successful run auto-save
          await notifier.deleteActiveSession();
        } else if (alert == 50) {
          sawFailure = true;
          // Verify failure math:
          // Deltas are zeroed, safety override triggered, alert becomes 50.
          // Pillar strength remains 10.
          expect(state.metrics.imperativePillar, equals(10));
          expect(state.metrics.controlPillar, equals(10));
          expect(state.metrics.dissonancePillar, equals(10));
          expect(state.historyCompression.last.content, contains("[OVERRIDE FALLITO]"));
          
          // Clean up session file created by failed run auto-save
          await notifier.deleteActiveSession();
        }
      }

      expect(sawSuccess, isTrue, reason: "Should have seen at least one success in $attempts attempts");
      expect(sawFailure, isTrue, reason: "Should have seen at least one failure in $attempts attempts");
    });

    test('Verifies saving, loading, and deleting active session', () async {
      final notifier = GameControllerNotifier(
        bridge: mockApiBridge,
        initialState: initialStateAlertZero,
      );

      // Trigger save manually
      await notifier.saveActiveSession();
      expect(await notifier.checkActiveSessionExists(), isTrue);

      // Now create a new notifier with different initial state, and verify resumeGame loads it back
      final anotherNotifier = GameControllerNotifier(
        bridge: mockApiBridge,
        initialState: initialStateAlertPositive,
      );

      await anotherNotifier.resumeGame();
      // It should have loaded initialStateAlertZero (alert level 0)
      expect(anotherNotifier.gameStateNotifier.value.metrics.alertLevel, equals(0));
      expect(anotherNotifier.currentScreen, equals("terminal"));

      // Now delete it
      await anotherNotifier.deleteActiveSession();
      expect(await anotherNotifier.checkActiveSessionExists(), isFalse);
    });

    test('Verifies saving, loading, and respecting custom model settings', () async {
      final notifier = GameControllerNotifier(
        bridge: mockApiBridge,
        initialState: initialStateAlertZero,
      );

      // Verify defaults
      expect(notifier.evaluatorModelId, equals("mistralai/ministral-3-3b"));
      expect(notifier.actorModelId, equals("qwen/qwen3.5-9b"));

      // Update to custom models
      notifier.updateEvaluatorModel("custom-eval-model");
      notifier.updateActorModel("gemma/gemma-4-12b");

      // Verify they are changed in memory
      expect(notifier.evaluatorModelId, equals("custom-eval-model"));
      expect(notifier.actorModelId, equals("gemma/gemma-4-12b"));

      // Now create a new notifier and load settings
      final anotherNotifier = GameControllerNotifier(
        bridge: mockApiBridge,
        initialState: initialStateAlertZero,
      );

      await anotherNotifier.initializeModels();

      // Verify custom models are loaded and respected, rather than overridden by discoverModels auto-routing
      expect(anotherNotifier.evaluatorModelId, equals("custom-eval-model"));
      expect(anotherNotifier.actorModelId, equals("gemma/gemma-4-12b"));
      expect(anotherNotifier.activeProfile, equals("User Custom Configuration"));

      // Clean up the settings file on disk
      String? path;
      if (Platform.isWindows) {
        final appData = Platform.environment['APPDATA'];
        if (appData != null) {
          path = "$appData\\aura";
        }
      }
      path ??= "replays";
      final settingsFile = File("$path\\settings.json");
      if (await settingsFile.exists()) {
        await settingsFile.delete();
      }
    });
  });
}
