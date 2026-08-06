import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aura_core/aura_testing.dart';
import 'package:aura_core/aura_offline.dart';
import 'package:aura_app/src/screens/app_startup_gate.dart';
import 'package:aura_app/src/screens/boot_menu_screen.dart';
import 'package:aura_app/src/screens/first_run_model_setup_screen.dart';
import 'package:aura_app/src/state_management/game_controller_notifier.dart';

class FakeFirstRunFacade implements FirstRunModelSetupFacade {
  FirstRunSetupState stateToReturn;
  Object? errorToThrow;
  int evaluateCalls = 0;

  FakeFirstRunFacade({
    required this.stateToReturn,
    this.errorToThrow,
  });

  @override
  Future<FirstRunSetupState> evaluateInitialState() async {
    evaluateCalls++;
    if (errorToThrow != null) {
      throw errorToThrow!;
    }
    return stateToReturn;
  }

  @override
  Future<FirstRunSetupState> configureRuntime(String executablePath) async =>
      stateToReturn;

  @override
  Future<FirstRunSetupState> selectActorModel(
          ConfiguredModelReference ref) async =>
      stateToReturn;

  @override
  Future<FirstRunSetupState> selectEvaluatorModel(
          ConfiguredModelReference ref) async =>
      stateToReturn;

  @override
  Future<FirstRunSetupState> acceptConsentAndBindActor(
          ExternalModelReference reference) async =>
      stateToReturn;

  @override
  Future<FirstRunSetupState> acceptConsentAndBindEvaluator(
          ExternalModelReference reference) async =>
      stateToReturn;

  @override
  Future<FirstRunSetupState> acceptConsentAndRetry({
    required ModelActivationRole role,
    required ExternalModelReference reference,
  }) async =>
      stateToReturn;

  @override
  Future<FirstRunSetupState> downloadAndProvisionCatalogArtifact({
    required CatalogArtifact artifact,
    required ModelActivationRole role,
    ProvisioningCancellationToken? cancellationToken,
    void Function(DownloadProgress progress)? onProgress,
  }) async =>
      stateToReturn;

  @override
  Future<FirstRunSetupState> runFinalPreflight() async => stateToReturn;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GameControllerNotifier notifier;
  late GameState testState;

  setUp(() {
    final bridge = MockInferenceBridge();
    testState = GameState.initial(
      sessionId: 'gate-test-session',
      aiIdentityId: 'panopticon',
      targetObjectiveId: 'containment_grid_override',
    );
    notifier = GameControllerNotifier(
      bridge: bridge,
      initialState: testState,
    );
  });

  group('AppStartupGate Widget Tests', () {
    testWidgets(
        'Incomplete setup automatically routes to FirstRunModelSetupScreen (onboarding)',
        (WidgetTester tester) async {
      final fakeFacade = FakeFirstRunFacade(
        stateToReturn: const FirstRunSetupState(
          step: FirstRunSetupStep.runtimeSelection,
        ),
      );

      await tester.pumpWidget(
        GameControllerProvider(
          notifier: notifier,
          child: MaterialApp(
            home: AppStartupGate(
              notifier: notifier,
              firstRunFacade: fakeFacade,
              dependencyService: const FakeLlamaServerDependencyService(),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(FirstRunModelSetupScreen), findsOneWidget);
      expect(find.byType(BootMenuScreen), findsNothing);
      expect(fakeFacade.evaluateCalls, greaterThanOrEqualTo(1));
    });

    testWidgets('Complete setup automatically routes to BootMenuScreen',
        (WidgetTester tester) async {
      final fakeFacade = FakeFirstRunFacade(
        stateToReturn: const FirstRunSetupState(
          step: FirstRunSetupStep.complete,
          preflightResult: LocalInferencePreflightResult.ready(),
        ),
      );

      await tester.pumpWidget(
        GameControllerProvider(
          notifier: notifier,
          child: MaterialApp(
            home: AppStartupGate(
              notifier: notifier,
              firstRunFacade: fakeFacade,
              dependencyService: const FakeLlamaServerDependencyService(),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(BootMenuScreen), findsOneWidget);
      expect(find.byType(FirstRunModelSetupScreen), findsNothing);
    });

    testWidgets(
        'Evaluation error routes to StartupDestination.error recovery screen',
        (WidgetTester tester) async {
      final fakeFacade = FakeFirstRunFacade(
        stateToReturn: const FirstRunSetupState(
          step: FirstRunSetupStep.failed,
        ),
        errorToThrow: StateError('Access denied reading config lock'),
      );

      await tester.pumpWidget(
        GameControllerProvider(
          notifier: notifier,
          child: MaterialApp(
            home: AppStartupGate(
              notifier: notifier,
              firstRunFacade: fakeFacade,
              dependencyService: const FakeLlamaServerDependencyService(),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('IMPOSSIBILE VERIFICARE LA CONFIGURAZIONE LOCALE'),
          findsOneWidget);
      expect(find.text('RIPROVA'), findsOneWidget);
      expect(find.text('AVVIA CONFIGURAZIONE GUIDATA'), findsOneWidget);
      expect(find.byType(BootMenuScreen), findsNothing);
    });

    testWidgets(
        'Clicking AVVIA CONFIGURAZIONE GUIDATA on error screen transitions to onboarding',
        (WidgetTester tester) async {
      final fakeFacade = FakeFirstRunFacade(
        stateToReturn: const FirstRunSetupState(
          step: FirstRunSetupStep.runtimeSelection,
        ),
        errorToThrow: StateError('Corrupted JSON'),
      );

      await tester.pumpWidget(
        GameControllerProvider(
          notifier: notifier,
          child: MaterialApp(
            home: AppStartupGate(
              notifier: notifier,
              firstRunFacade: fakeFacade,
              dependencyService: const FakeLlamaServerDependencyService(),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Click AVVIA CONFIGURAZIONE GUIDATA
      fakeFacade.errorToThrow = null;
      await tester.tap(find.text('AVVIA CONFIGURAZIONE GUIDATA'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(FirstRunModelSetupScreen), findsOneWidget);
    });
  });
}
