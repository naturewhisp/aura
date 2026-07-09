import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aura_core/aura_core.dart';
import 'package:aura_app/src/state_management/game_controller_notifier.dart';
import 'package:aura_app/src/screens/boot_menu_screen.dart';
import 'package:aura_app/src/screens/new_connection_briefing_screen.dart';
import 'package:aura_app/src/audio/audio_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GameControllerNotifier notifier;
  late MockInferenceBridge mockBridge;

  setUp(() async {
    mockBridge = MockInferenceBridge();
    final initialState = GameState.initial(
      sessionId: 'test-session',
      aiIdentityId: 'panopticon',
      targetObjectiveId: 'tabula_rasa',
    );
    notifier = GameControllerNotifier(
      bridge: mockBridge,
      initialState: initialState,
    );

    // Initialize AudioManager in headless mode for testing
    await AudioManager().initialize('test_dir', audioEnabled: false);
  });

  testWidgets('BootMenuScreen - Click Nuova Connessione opens Briefing Screen and backing out works', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GameControllerProvider(
            notifier: notifier,
            child: BootMenuScreen(
              notifier: notifier,
            ),
          ),
        ),
      ),
    );

    // Initial state: Boot screen requires logs loading and delay to proceed
    // Wait 10 seconds for the periodic timers and Future.delayed calls to complete
    await tester.pump(const Duration(seconds: 10));

    // Tap anywhere to proceed to Main Menu
    await tester.tap(find.byType(BootMenuScreen));
    await tester.pump(const Duration(milliseconds: 100));

    // Now we should be on the Main Menu screen
    expect(find.text("NUOVA CONNESSIONE"), findsOneWidget);

    // Tap on Nuova Connessione button
    await tester.tap(find.text("NUOVA CONNESSIONE"));
    // Wait for the blinking selection animation (6 blinks * 60ms = ~360ms)
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 100));

    // Verify we are now showing the briefing screen
    expect(find.byType(NewConnectionBriefingScreen), findsOneWidget);
    expect(find.text("BRIEFING DI CONNESSIONE"), findsOneWidget);

    // Click Back to return to Main Menu
    final backBtnFinder = find.byKey(const Key('btn_briefing_back'));
    await tester.tap(backBtnFinder);
    await tester.pump(const Duration(milliseconds: 100));

    // Verify we are back to Main Menu
    expect(find.byType(NewConnectionBriefingScreen), findsNothing);
    expect(find.text("NUOVA CONNESSIONE"), findsOneWidget);
  });
}
