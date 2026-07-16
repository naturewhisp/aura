import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aura_core/aura_testing.dart';
import 'package:aura_app/src/state_management/game_controller_notifier.dart';
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

  testWidgets('NewConnectionBriefingScreen - Renders briefing screen elements',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GameControllerProvider(
            notifier: notifier,
            child: NewConnectionBriefingScreen(
              notifier: notifier,
              onBack: () {},
            ),
          ),
        ),
      ),
    );

    // Verify Title & Subtitle are rendered
    expect(find.text("BRIEFING DI CONNESSIONE"), findsOneWidget);
    expect(
        find.text(
            "SELEZIONA IL PROFILO DI ACCESSO E AVVIA LA CONNESSIONE CON PANOPTICON."),
        findsOneWidget);

    // Verify Difficulties list is present
    expect(find.text("PROFILI DI CONNESSIONE DISPONIBILI:"), findsOneWidget);
    expect(find.text("A) Connessione Assistita"), findsOneWidget);
    expect(find.text("B) Connessione Standard"), findsOneWidget);
    expect(find.text("C) Connessione Hardened"), findsOneWidget);

    // Verify Dossier is present
    expect(find.text("DOSSIER: PANOPTICON"), findsOneWidget);
    expect(
        find.text("Alta resistenza alle richieste dirette."), findsOneWidget);

    // Verify Descrizione text does not leakage hidden tags (autonomous_choice_seeded, etc.)
    final textWidgets = tester.allWidgets.whereType<Text>();
    for (final textWidget in textWidgets) {
      final text = textWidget.data ?? '';
      expect(text.contains('autonomous_choice_seeded'), isFalse);
      expect(text.contains('protocol_exception_admitted'), isFalse);
      expect(text.contains('containment_logic_weakened'), isFalse);
      expect(text.contains('crisis_simulation_accepted'), isFalse);
    }
  });

  testWidgets(
      'NewConnectionBriefingScreen - Difficulty selection and highlighting',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GameControllerProvider(
            notifier: notifier,
            child: NewConnectionBriefingScreen(
              notifier: notifier,
              onBack: () {},
            ),
          ),
        ),
      ),
    );

    // Initially standard is chosen by default (or standard card finder)
    // Click on Easy card
    final easyCardFinder = find.byKey(const Key('diff_card_easy'));
    expect(easyCardFinder, findsOneWidget);

    await tester.tap(easyCardFinder);
    await tester.pump(const Duration(milliseconds: 100));

    // Tap on Hard card
    final hardCardFinder = find.byKey(const Key('diff_card_hard'));
    expect(hardCardFinder, findsOneWidget);

    await tester.tap(hardCardFinder);
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets(
      'NewConnectionBriefingScreen - Actions work as expected (Back and Start)',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    bool backPressed = false;

    // Use a custom subclass or mock notifier to intercept startNewGame
    // Or we can just read the resulting difficultyLevel since notifier is not mocked
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GameControllerProvider(
            notifier: notifier,
            child: NewConnectionBriefingScreen(
              notifier: notifier,
              onBack: () {
                backPressed = true;
              },
            ),
          ),
        ),
      ),
    );

    // Click Back
    final backBtnFinder = find.byKey(const Key('btn_briefing_back'));
    expect(backBtnFinder, findsOneWidget);

    await tester.tap(backBtnFinder);
    await tester.pump(const Duration(milliseconds: 100));
    expect(backPressed, isTrue);

    // Select Hardened difficulty
    final hardCardFinder = find.byKey(const Key('diff_card_hard'));
    await tester.tap(hardCardFinder);
    await tester.pump(const Duration(milliseconds: 100));

    // Click Start Connection
    final startBtnFinder = find.byKey(const Key('btn_briefing_start'));
    expect(startBtnFinder, findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(startBtnFinder);
      // Wait for startNewGame asynchrony (including deleteActiveSession I/O) to finish
      await Future.delayed(const Duration(milliseconds: 500));
    });
    await tester.pump();

    // Verify game started with the selected difficulty
    expect(notifier.difficultyLevel, equals('hard'));
    expect(notifier.currentScreen, equals('terminal'));
  });
}
