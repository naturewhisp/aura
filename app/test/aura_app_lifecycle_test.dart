import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:aura_core/aura_testing.dart';
import 'package:aura_app/src/state_management/game_controller_notifier.dart';
import 'package:aura_app/src/state_management/desktop_shell_controller.dart';
import 'package:aura_app/src/state_management/application_shutdown_coordinator.dart';

void main() {
  test(
      'ApplicationShutdownCoordinator requestShutdown executes shutdown sequence deterministically',
      () async {
    final shutdownStartedCompleter = Completer<void>();
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
        if (!shutdownStartedCompleter.isCompleted) {
          shutdownStartedCompleter.complete();
        }
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

    final shutdownFuture = shutdownCoordinator.requestShutdown();

    // Await deterministic entry into onDispose without any arbitrary delay
    await shutdownStartedCompleter.future;

    // Verify shutdown is in progress (notifier.isShutdown is true) but onDispose has not finished
    expect(shutdownCompleted, isFalse);
    expect(notifier.isShutdown, isTrue);

    // Complete shutdownCompleter to unblock onDispose and allow shutdownFuture to resolve
    shutdownCompleter.complete();
    await shutdownFuture;

    expect(shutdownCompleted, isTrue);
    expect(notifier.isShutdown, isTrue);
    expect(fakeWindowController.isWindowClosed, isTrue);

    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });
}
