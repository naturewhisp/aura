import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aura_core/aura_testing.dart';
import 'package:aura_app/main.dart';
import 'package:aura_app/src/state_management/game_controller_notifier.dart';
import 'package:aura_app/src/state_management/desktop_shell_controller.dart';
import 'package:aura_app/src/state_management/application_shutdown_coordinator.dart';

void main() {
  testWidgets('AuraApp didRequestAppExit invokes and awaits notifier.shutdown',
      (WidgetTester tester) async {
    final shutdownCompleter = Completer<void>();
    bool shutdownCompleted = false;

    final initialState = GameState.initial(
      sessionId: 'test-app-exit-session',
      aiIdentityId: 'panopticon',
      targetObjectiveId: 'containment_grid_override',
    );

    final notifier = GameControllerNotifier(
      bridge: MockInferenceBridge(),
      initialState: initialState,
      onDispose: () async {
        await shutdownCompleter.future;
        shutdownCompleted = true;
      },
    );

    final tempDir = Directory.systemTemp.createTempSync('aura_app_exit_test_');
    final fakeWindowController = FakeDesktopWindowController();
    final prefsRepo =
        WindowPreferencesRepository(storeDirectoryPath: tempDir.path);
    final persistenceCoordinator =
        WindowGeometryPersistenceCoordinator(repository: prefsRepo);
    final shellController = DesktopShellController(
      windowController: fakeWindowController,
      persistenceCoordinator: persistenceCoordinator,
    );
    final shutdownCoordinator = ApplicationShutdownCoordinator(
      notifier: notifier,
      shellController: shellController,
      persistenceCoordinator: persistenceCoordinator,
      windowController: fakeWindowController,
      onNativeExit: () {},
    );

    await tester.pumpWidget(AuraApp(
      notifier: notifier,
      dependencyService: const FakeLlamaServerDependencyService(),
      desktopWindowController: fakeWindowController,
      desktopShellController: shellController,
      shutdownCoordinator: shutdownCoordinator,
    ));

    // Pump to allow BootMenuScreen's initial boot sequence timers to complete
    await tester.pump(const Duration(seconds: 2));

    final state = tester.state(find.byType(AuraApp)) as WidgetsBindingObserver;

    late Future<AppExitResponse> exitFuture;
    await tester.runAsync(() async {
      exitFuture = state.didRequestAppExit();
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });

    // Verify exitFuture is pending because onDispose is awaiting shutdownCompleter
    expect(shutdownCompleted, isFalse);

    AppExitResponse? response;
    await tester.runAsync(() async {
      shutdownCompleter.complete();
      response = await exitFuture;
    });

    expect(response, equals(AppExitResponse.exit));
    expect(shutdownCompleted, isTrue);
    expect(notifier.isShutdown, isTrue);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));

    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });
}
