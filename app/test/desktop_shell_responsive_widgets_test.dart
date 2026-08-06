import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aura_core/aura_testing.dart';
import 'package:aura_core/aura_offline.dart';
import 'package:aura_app/src/state_management/game_controller_notifier.dart';
import 'package:aura_app/src/state_management/desktop_shell_controller.dart';
import 'package:aura_app/src/platform/desktop_shell_provider.dart';
import 'package:aura_app/src/screens/terminal_screen.dart';
import 'package:aura_app/src/screens/boot_menu_screen.dart';
import 'package:aura_app/src/screens/first_run_model_setup_screen.dart';
import 'package:aura_app/src/screens/new_connection_briefing_screen.dart';

final class ResponsiveFakeInferenceFacade implements LocalInferenceFacade {
  @override
  Future<List<ProcessOwnershipRecord>> cleanupStaleProcesses() async =>
      const [];

  @override
  Future<LlamaServerDetectionResult> detectRuntime() async =>
      const LlamaServerDetectionResult();

  @override
  Future<LocalInferenceSnapshot> getSnapshot() async =>
      const LocalInferenceSnapshot(
        runtimeConfiguration:
            LlamaServerConfiguration(executablePath: r'C:\llama.exe'),
        modelConfiguration: ModelRoleConfiguration(),
        isConsentValid: false,
        lastPreflightResult: LocalInferencePreflightResult.ready(),
      );

  @override
  Future<List<InstalledArtifactDescriptor>> listManagedModels() async =>
      const [];

  @override
  Future<List<ProcessOwnershipRecord>> listManagedProcesses() async => const [];

  @override
  Future<LocalInferencePreflightResult> runPreflight(
          {required PreflightDepth depth}) async =>
      const LocalInferencePreflightResult.ready();

  @override
  Future<List<ExternalModelCandidate>> scanExternalCandidates(
          {String? customPath}) async =>
      const [];
}

final class ResponsiveFakeFirstRunFacade implements FirstRunModelSetupFacade {
  FirstRunSetupState currentState = const FirstRunSetupState(
    step: FirstRunSetupStep.runtimeSelection,
  );

  @override
  Future<FirstRunSetupState> acceptConsentAndBindActor(
          ExternalModelReference reference) async =>
      currentState;

  @override
  Future<FirstRunSetupState> acceptConsentAndBindEvaluator(
          ExternalModelReference reference) async =>
      currentState;

  @override
  Future<FirstRunSetupState> acceptConsentAndRetry({
    required ModelActivationRole role,
    required ExternalModelReference reference,
  }) async =>
      currentState;

  @override
  Future<FirstRunSetupState> downloadAndProvisionCatalogArtifact({
    required CatalogArtifact artifact,
    required ModelActivationRole role,
    ProvisioningCancellationToken? cancellationToken,
    void Function(DownloadProgress progress)? onProgress,
  }) async =>
      currentState;

  @override
  Future<FirstRunSetupState> configureRuntime(String executablePath) async =>
      currentState;

  @override
  Future<FirstRunSetupState> evaluateInitialState() async => currentState;

  @override
  Future<FirstRunSetupState> runFinalPreflight() async => currentState;

  @override
  Future<FirstRunSetupState> selectActorModel(
          ConfiguredModelReference ref) async =>
      currentState;

  @override
  Future<FirstRunSetupState> selectEvaluatorModel(
          ConfiguredModelReference ref) async =>
      currentState;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeDesktopWindowController fakeWindowController;
  late WindowPreferencesRepository repo;
  late WindowGeometryPersistenceCoordinator persistenceCoordinator;
  late DesktopShellController shellController;
  late GameControllerNotifier gameNotifier;
  late ResponsiveFakeFirstRunFacade fakeFirstRunFacade;
  late ResponsiveFakeInferenceFacade fakeInferenceFacade;

  const targetSizes = [
    Size(420, 500), // Minimo assoluto
    Size(450, 800), // Portrait realistico
    Size(600, 900), // Portrait ampio
    Size(699, 700), // Ultimo pixel layout compatto
    Size(700, 700), // Primo pixel layout desktop
  ];

  setUp(() async {
    fakeWindowController = FakeDesktopWindowController();
    repo = WindowPreferencesRepository(
      storeDirectoryPath: Directory.systemTemp.path,
    );
    persistenceCoordinator = WindowGeometryPersistenceCoordinator(
      repository: repo,
    );
    shellController = DesktopShellController(
      windowController: fakeWindowController,
      persistenceCoordinator: persistenceCoordinator,
    );
    await shellController.initialize();

    final initialState = GameState.initial(
      sessionId: 'test-responsive-session',
      aiIdentityId: 'panopticon',
      targetObjectiveId: 'containment_grid_override',
    );

    gameNotifier = GameControllerNotifier(
      bridge: MockInferenceBridge(),
      initialState: initialState,
    );

    fakeFirstRunFacade = ResponsiveFakeFirstRunFacade();
    fakeInferenceFacade = ResponsiveFakeInferenceFacade();
  });

  tearDown(() {
    persistenceCoordinator.dispose();
  });

  Widget buildAppWrapper({
    required Widget child,
    TextScaler textScaler = TextScaler.noScaling,
  }) {
    return GameControllerProvider(
      notifier: gameNotifier,
      child: DesktopShellProvider(
        controller: shellController,
        child: MediaQuery(
          data: MediaQueryData(textScaler: textScaler),
          child: MaterialApp(
            home: Scaffold(body: child),
          ),
        ),
      ),
    );
  }

  group('Responsive Widget Rendering Matrix Across Dimensions', () {
    for (final size in targetSizes) {
      testWidgets(
          'TerminalScreen renders without exceptions at ${size.width}x${size.height}',
          (WidgetTester tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          buildAppWrapper(
            child: TerminalScreen(notifier: gameNotifier),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(tester.takeException(), isNull);
        expect(find.byType(TerminalScreen), findsOneWidget);
      });

      testWidgets(
          'BootMenuScreen (main & settings) renders cleanly at ${size.width}x${size.height}',
          (WidgetTester tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          buildAppWrapper(
            child: BootMenuScreen(
              notifier: gameNotifier,
              dependencyService: const FakeLlamaServerDependencyService(),
              initialSubScreen: 'settings',
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(tester.takeException(), isNull);
        expect(find.byType(BootMenuScreen), findsOneWidget);
      });

      testWidgets(
          'FirstRunModelSetupScreen renders onboarding step at ${size.width}x${size.height}',
          (WidgetTester tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          buildAppWrapper(
            child: FirstRunModelSetupScreen(
              firstRunFacade: fakeFirstRunFacade,
              inferenceFacade: fakeInferenceFacade,
              onComplete: () {},
              disableBackgroundAnimation: true,
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(tester.takeException(), isNull);
        expect(find.byType(FirstRunModelSetupScreen), findsOneWidget);
      });

      testWidgets(
          'NewConnectionBriefingScreen renders briefing profile at ${size.width}x${size.height}',
          (WidgetTester tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          buildAppWrapper(
            child: NewConnectionBriefingScreen(
              notifier: gameNotifier,
              onBack: () {},
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(tester.takeException(), isNull);
        expect(find.byType(NewConnectionBriefingScreen), findsOneWidget);
      });
    }

    testWidgets(
        'TerminalScreen renders cleanly at absolute minimum 420x500 with text scaling 1.2',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(420, 500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        buildAppWrapper(
          textScaler: const TextScaler.linear(1.2),
          child: TerminalScreen(notifier: gameNotifier),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
      expect(find.byType(TerminalScreen), findsOneWidget);
    });

    testWidgets(
        'FirstRunModelSetupScreen renders at 420x500 with text scaling 1.2',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(420, 500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        buildAppWrapper(
          textScaler: const TextScaler.linear(1.2),
          child: FirstRunModelSetupScreen(
            firstRunFacade: fakeFirstRunFacade,
            inferenceFacade: fakeInferenceFacade,
            onComplete: () {},
            disableBackgroundAnimation: true,
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
      expect(find.byType(FirstRunModelSetupScreen), findsOneWidget);
    });
  });
}
