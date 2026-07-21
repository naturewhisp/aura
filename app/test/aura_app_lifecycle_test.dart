import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aura_core/aura_testing.dart';
import 'package:aura_app/main.dart';
import 'package:aura_app/src/state_management/game_controller_notifier.dart';

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

    await tester.pumpWidget(AuraApp(notifier: notifier));

    // Pump to allow BootMenuScreen's initial boot sequence timers to complete
    await tester.pump(const Duration(seconds: 2));

    final state = tester.state(find.byType(AuraApp)) as WidgetsBindingObserver;

    bool exitCompleted = false;
    AppExitResponse? exitResponse;

    final exitFuture = state.didRequestAppExit().then((response) {
      exitCompleted = true;
      exitResponse = response;
      return response;
    });

    await tester.pump();

    // Verify exitFuture is still pending because onDispose is awaiting shutdownCompleter
    expect(exitCompleted, isFalse);
    expect(shutdownCompleted, isFalse);

    // Complete the shutdown completer
    shutdownCompleter.complete();

    await exitFuture;

    expect(exitCompleted, isTrue);
    expect(exitResponse, equals(AppExitResponse.exit));
    expect(shutdownCompleted, isTrue);
    expect(notifier.isShutdown, isTrue);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
