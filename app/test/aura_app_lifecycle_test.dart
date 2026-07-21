import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aura_core/aura_testing.dart';
import 'package:aura_app/main.dart';
import 'package:aura_app/src/state_management/game_controller_notifier.dart';

void main() {
  testWidgets('AuraApp didRequestAppExit invokes and awaits notifier.shutdown',
      (WidgetTester tester) async {
    bool shutdownCalled = false;
    final initialState = GameState.initial(
      sessionId: 'test-app-exit-session',
      aiIdentityId: 'panopticon',
      targetObjectiveId: 'containment_grid_override',
    );

    final notifier = GameControllerNotifier(
      bridge: MockInferenceBridge(),
      initialState: initialState,
      onDispose: () async {
        shutdownCalled = true;
      },
    );

    await tester.pumpWidget(AuraApp(notifier: notifier));

    final state = tester.state(find.byType(AuraApp)) as WidgetsBindingObserver;

    final response = await state.didRequestAppExit();

    expect(response, equals(AppExitResponse.exit));
    expect(shutdownCalled, isTrue);
    expect(notifier.isShutdown, isTrue);

    await tester.pump(const Duration(seconds: 10));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
  });
}
