import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aura_core/aura_testing.dart';
import 'package:aura_app/main.dart';
import 'package:aura_app/src/state_management/game_controller_notifier.dart';
import 'package:aura_app/src/state_management/desktop_shell_controller.dart';
import 'package:aura_app/src/state_management/application_shutdown_coordinator.dart';
import 'package:aura_app/src/screens/boot_menu_screen.dart';
import 'package:aura_app/src/platform/desktop_shell_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeDesktopWindowController fakeWindowController;
  late WindowPreferencesRepository repo;
  late WindowGeometryPersistenceCoordinator persistenceCoordinator;
  late DesktopShellController shellController;

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
  });

  tearDown(() {
    persistenceCoordinator.dispose();
  });

  group('Single-Flight ApplicationShutdownCoordinator', () {
    test('close requested twice triggers only one shutdown execution',
        () async {
      int shutdownCalls = 0;
      final initialState = GameState.initial(
        sessionId: 'test-single-flight',
        aiIdentityId: 'panopticon',
        targetObjectiveId: 'containment_grid_override',
      );

      final localShellController = DesktopShellController(
        windowController: fakeWindowController,
        persistenceCoordinator: persistenceCoordinator,
      );
      await localShellController.initialize();

      final notifier = GameControllerNotifier(
        bridge: MockInferenceBridge(),
        initialState: initialState,
        onDispose: () async {
          shutdownCalls++;
          await Future.delayed(const Duration(milliseconds: 20));
        },
      );

      final coordinator = ApplicationShutdownCoordinator(
        notifier: notifier,
        shellController: localShellController,
        persistenceCoordinator: persistenceCoordinator,
        windowController: fakeWindowController,
        onNativeExit: () {},
      );

      final req1 = coordinator.requestShutdown();
      final req2 = coordinator.requestShutdown();

      expect(coordinator.isShutdownInProgress, isTrue);

      await Future.wait([req1, req2]);

      expect(shutdownCalls, equals(1));
    });

    test(
        'error during preference save or runtime shutdown does not freeze shutdown flow',
        () async {
      final initialState = GameState.initial(
        sessionId: 'test-fault-tolerant-shutdown',
        aiIdentityId: 'panopticon',
        targetObjectiveId: 'containment_grid_override',
      );

      final localShellController = DesktopShellController(
        windowController: fakeWindowController,
        persistenceCoordinator: persistenceCoordinator,
      );
      await localShellController.initialize();

      final notifier = GameControllerNotifier(
        bridge: MockInferenceBridge(),
        initialState: initialState,
        onDispose: () async {
          throw Exception('Runtime shutdown failure simulation');
        },
      );

      final coordinator = ApplicationShutdownCoordinator(
        notifier: notifier,
        shellController: localShellController,
        persistenceCoordinator: persistenceCoordinator,
        windowController: fakeWindowController,
        onNativeExit: () {},
      );

      await expectLater(coordinator.requestShutdown(), completes);
    });
  });

  group('Window Geometry & Mode Invariants', () {
    test('resize while maximized does NOT overwrite lastWindowedGeometry',
        () async {
      const windowedGeom = WindowGeometry(
        x: 100,
        y: 100,
        width: 1280,
        height: 800,
        monitorId: 'fake-display-1',
        displayScale: 1.0,
      );

      await shellController.setWindowed();
      fakeWindowController
          .emitEvent(const DesktopWindowMovedResized(windowedGeom));
      await Future.delayed(Duration.zero);

      expect(shellController.state.geometry, equals(windowedGeom));

      await shellController.maximize();
      expect(
          shellController.state.activeMode, equals(ActiveWindowMode.maximized));

      // Simulate a window resize event fired by native OS while maximized
      const maximizedGeom = WindowGeometry(
        x: 0,
        y: 0,
        width: 1920,
        height: 1080,
        monitorId: 'fake-display-1',
        displayScale: 1.0,
      );
      fakeWindowController
          .emitEvent(const DesktopWindowMovedResized(maximizedGeom));
      await Future.delayed(Duration.zero);

      // Saved windowed geometry should remain unchanged
      expect(persistenceCoordinator.currentPreferences.lastWindowedGeometry,
          equals(windowedGeom));
    });

    test('exiting fullscreen restores last windowed geometry', () async {
      const windowedGeom = WindowGeometry(
        x: 200,
        y: 200,
        width: 1000,
        height: 700,
        monitorId: 'fake-display-1',
        displayScale: 1.0,
      );
      await shellController.setWindowed();
      fakeWindowController
          .emitEvent(const DesktopWindowMovedResized(windowedGeom));
      await Future.delayed(Duration.zero);

      await shellController.enterBorderlessFullscreen();
      expect(shellController.state.activeMode,
          equals(ActiveWindowMode.borderlessFullscreen));

      await shellController.exitBorderlessFullscreen();
      expect(
          shellController.state.activeMode, equals(ActiveWindowMode.windowed));
      expect(shellController.state.geometry, equals(windowedGeom));
    });
  });

  group('Desktop Shell Widgets & DISPLAY Section', () {
    testWidgets(
        'Renders DISPLAY section in BootMenuScreen Settings and updates startupMode',
        (WidgetTester tester) async {
      final initialState = GameState.initial(
        sessionId: 'test-display-settings',
        aiIdentityId: 'panopticon',
        targetObjectiveId: 'containment_grid_override',
      );

      final notifier = GameControllerNotifier(
        bridge: MockInferenceBridge(),
        initialState: initialState,
      );

      await tester.pumpWidget(
        GameControllerProvider(
          notifier: notifier,
          child: DesktopShellProvider(
            controller: shellController,
            child: MaterialApp(
              home: BootMenuScreen(
                notifier: notifier,
                dependencyService: const FakeLlamaServerDependencyService(),
                initialSubScreen: 'settings',
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Check DISPLAY title header
      expect(find.text('--- DISPLAY & FINESTRA ---'), findsOneWidget);

      // Check mode buttons
      expect(find.byKey(const Key('btn_set_windowed')), findsOneWidget);
      expect(find.byKey(const Key('btn_set_maximized')), findsOneWidget);
      expect(find.byKey(const Key('btn_toggle_fullscreen')), findsOneWidget);

      // Tap on Maximized button
      await tester.tap(find.byKey(const Key('btn_set_maximized')));
      await tester.pump(const Duration(milliseconds: 200));

      expect(
          shellController.state.activeMode, equals(ActiveWindowMode.maximized));

      // Check Audio and Graphics sections
      expect(find.text('--- AUDIO & EFFETTI SONORI ---'), findsOneWidget);
      expect(find.text('--- GRAFICA & PRESTAZIONI ---'), findsOneWidget);

      expect(find.byKey(const Key('checkbox_music_enabled')), findsOneWidget);
      expect(find.byKey(const Key('checkbox_sfx_enabled')), findsOneWidget);
      expect(find.byKey(const Key('checkbox_reduce_graphic_effects')),
          findsOneWidget);

      // Toggle music checkbox
      await tester
          .ensureVisible(find.byKey(const Key('checkbox_music_enabled')));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.byKey(const Key('checkbox_music_enabled')));
      await tester.pump(const Duration(milliseconds: 200));
      expect(shellController.state.musicEnabled, isFalse);

      // Toggle sfx checkbox
      await tester.ensureVisible(find.byKey(const Key('checkbox_sfx_enabled')));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.byKey(const Key('checkbox_sfx_enabled')));
      await tester.pump(const Duration(milliseconds: 200));
      expect(shellController.state.sfxEnabled, isFalse);

      // Toggle reduce graphics checkbox
      await tester.ensureVisible(
          find.byKey(const Key('checkbox_reduce_graphic_effects')));
      await tester.pump(const Duration(milliseconds: 200));
      await tester
          .tap(find.byKey(const Key('checkbox_reduce_graphic_effects')));
      await tester.pump(const Duration(milliseconds: 200));
      expect(shellController.state.reduceGraphicEffects, isTrue);

      // Flush persistence debounce timer before disposing widget tree
      await tester.pump(const Duration(milliseconds: 350));
    });

    testWidgets('Shortcuts F11 and Alt+Enter trigger fullscreen toggle',
        (WidgetTester tester) async {
      final initialState = GameState.initial(
        sessionId: 'test-shortcuts',
        aiIdentityId: 'panopticon',
        targetObjectiveId: 'containment_grid_override',
      );

      final notifier = GameControllerNotifier(
        bridge: MockInferenceBridge(),
        initialState: initialState,
      );

      await tester.pumpWidget(
        AuraApp(
          notifier: notifier,
          dependencyService: const FakeLlamaServerDependencyService(),
          desktopWindowController: fakeWindowController,
          desktopShellController: shellController,
        ),
      );

      await tester.pump(const Duration(seconds: 2));

      // Press F11
      await tester.sendKeyEvent(LogicalKeyboardKey.f11);
      await tester.pump(const Duration(milliseconds: 200));

      expect(shellController.state.activeMode,
          equals(ActiveWindowMode.borderlessFullscreen));

      // Press Esc to exit fullscreen
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump(const Duration(milliseconds: 200));

      expect(
          shellController.state.activeMode, equals(ActiveWindowMode.windowed));
      await tester.pump(const Duration(milliseconds: 350));
    });

    testWidgets(
        'Native window close request (X button) triggers shutdown and closes window via controller',
        (WidgetTester tester) async {
      final initialState = GameState.initial(
        sessionId: 'test-window-close-x',
        aiIdentityId: 'panopticon',
        targetObjectiveId: 'containment_grid_override',
      );

      final notifier = GameControllerNotifier(
        bridge: MockInferenceBridge(),
        initialState: initialState,
      );

      final coordinator = ApplicationShutdownCoordinator(
        notifier: notifier,
        shellController: shellController,
        persistenceCoordinator: persistenceCoordinator,
        windowController: fakeWindowController,
        onNativeExit: () {},
      );

      await tester.pumpWidget(
        AuraApp(
          notifier: notifier,
          dependencyService: const FakeLlamaServerDependencyService(),
          desktopWindowController: fakeWindowController,
          desktopShellController: shellController,
          shutdownCoordinator: coordinator,
        ),
      );

      await tester.pump(const Duration(seconds: 2));

      // Emit native close request (X button)
      fakeWindowController.emitEvent(const DesktopWindowCloseRequested());
      await tester.runAsync(() async {
        await coordinator.requestShutdown();
      });
      await tester.pump();

      expect(fakeWindowController.isWindowClosed, isTrue);
    });

    test('minimize and restore events update shell state minimized property',
        () async {
      fakeWindowController.emitEvent(const DesktopWindowMinimizeChanged(true));
      await Future.delayed(Duration.zero);
      expect(shellController.state.minimized, isTrue);

      fakeWindowController.emitEvent(const DesktopWindowMinimizeChanged(false));
      await Future.delayed(Duration.zero);
      expect(shellController.state.minimized, isFalse);
    });
  });
}
