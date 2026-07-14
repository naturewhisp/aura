import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aura_core/aura_core.dart';
import 'package:aura_app/src/screens/boot_menu_screen.dart';
import 'package:aura_app/src/audio/boot_audio_service.dart';
import 'package:aura_app/src/state_management/game_controller_notifier.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GameControllerNotifier notifier;
  late GameState testState;

  setUp(() {
    final bridge = MockInferenceBridge();
    testState = GameState.initial(
      sessionId: "boot-test-session",
      aiIdentityId: "panopticon",
      targetObjectiveId: "containment_grid_override",
    );
    notifier = GameControllerNotifier(
      bridge: bridge,
      initialState: testState,
    );
  });

  group('BootMenuScreen - Lifecycle & Initialization (Fase 3)', () {
    testWidgets('Models and audio initialize in correct sequential order',
        (WidgetTester tester) async {
      final fakeAudio = FakeBootAudioService();
      final modelsCompleter = Completer<void>();
      final events = <String>[];
      int modelsCallCount = 0;

      Future<void> fakeInitializeModels() async {
        modelsCallCount++;
        events.add('models:start');
        await modelsCompleter.future;
        events.add('models:complete');
      }

      // Link fake audio events to the shared list
      fakeAudio.onEvent = (event) => events.add(event);

      await tester.pumpWidget(
        MaterialApp(
          home: GameControllerProvider(
            notifier: notifier,
            child: BootMenuScreen(
              notifier: notifier,
              audioService: fakeAudio,
              initializeModels: fakeInitializeModels,
            ),
          ),
        ),
      );

      // Start the future and wait for the first 2 steps (300ms + 300ms) to complete
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      // Animation starts, models start initializing
      expect(modelsCallCount, equals(1));
      expect(events, contains('models:start'));
      expect(events, isNot(contains('models:complete')));
      expect(events, isNot(contains('audio:start')));

      // Complete models initialization
      modelsCompleter.complete();
      await tester.pump(); // Advance microtasks

      // Wait a frame or duration for the next delayed step (300ms)
      await tester.pump(const Duration(milliseconds: 300));

      // Models should be complete and audio should have started
      expect(events, contains('models:complete'));
      expect(events, contains('audio:start'));
      expect(events, isNot(contains('audio:complete')));

      // Complete audio initialization
      fakeAudio.initCompleter.complete();
      await tester.pump(); // Advance microtasks
      await tester.pump(
          const Duration(milliseconds: 1500)); // wait for delayed UI actions

      expect(events, contains('audio:complete'));
      expect(events, contains('audio:transition'));
      expect(fakeAudio.initializeCallCount, equals(1));
      expect(fakeAudio.transitionCallCount, equals(1));

      // Verify sequence order
      final modelsStartIndex = events.indexOf('models:start');
      final modelsCompleteIndex = events.indexOf('models:complete');
      final audioStartIndex = events.indexOf('audio:start');
      final audioCompleteIndex = events.indexOf('audio:complete');
      final audioTransitionIndex = events.indexOf('audio:transition');

      expect(modelsStartIndex < modelsCompleteIndex, isTrue);
      expect(modelsCompleteIndex < audioStartIndex, isTrue);
      expect(audioStartIndex < audioCompleteIndex, isTrue);
      expect(audioCompleteIndex < audioTransitionIndex, isTrue);
    });

    testWidgets('Pending models: Press Enter not visible and Enter key ignored',
        (WidgetTester tester) async {
      final fakeAudio = FakeBootAudioService();
      final modelsCompleter = Completer<void>();

      Future<void> fakeInitializeModels() async {
        await modelsCompleter.future;
      }

      await tester.pumpWidget(
        MaterialApp(
          home: GameControllerProvider(
            notifier: notifier,
            child: BootMenuScreen(
              notifier: notifier,
              audioService: fakeAudio,
              initializeModels: fakeInitializeModels,
            ),
          ),
        ),
      );

      // Start future and advance to model init step
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      // Models are pending, verify "PREMI ENTER" is not visible
      expect(find.textContaining('PREMI ENTER'), findsNothing);

      // Send Enter key keydown event
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      // Verify menu options are not visible (did not proceed to menu)
      expect(find.textContaining('PROGETTO SINDROME'), findsNothing);
    });

    testWidgets('Audio initialization throws: boot still succeeds in mute mode',
        (WidgetTester tester) async {
      final fakeAudio = FakeBootAudioService()..throwOnError = true;
      final modelsCompleter = Completer<void>()..complete();
      final events = <String>[];

      Future<void> fakeInitializeModels() async {
        await modelsCompleter.future;
      }

      fakeAudio.onEvent = (event) => events.add(event);

      await tester.pumpWidget(
        MaterialApp(
          home: GameControllerProvider(
            notifier: notifier,
            child: BootMenuScreen(
              notifier: notifier,
              audioService: fakeAudio,
              initializeModels: fakeInitializeModels,
            ),
          ),
        ),
      );

      // Complete models and start audio
      await tester.pump();
      await tester.pump(const Duration(
          milliseconds: 900)); // 600ms (steps 1,2) + 300ms (step 4)

      // Trigger audio init error
      fakeAudio.initCompleter.complete();
      await tester.pump();

      // Wait out the rest of the boot delays (ASCII art + Enter visible)
      await tester.pump(const Duration(milliseconds: 1500));

      // Boot should be completed even if audio threw an error
      expect(find.textContaining('PREMI ENTER'), findsOneWidget);

      // Verify that audio initialized was called
      expect(fakeAudio.initializeCallCount, equals(1));
    });

    testWidgets(
        'Widget disposed during boot: completing futures does not throw setState after dispose',
        (WidgetTester tester) async {
      final fakeAudio = FakeBootAudioService();
      final modelsCompleter = Completer<void>();

      Future<void> fakeInitializeModels() async {
        await modelsCompleter.future;
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GameControllerProvider(
              notifier: notifier,
              child: BootMenuScreen(
                notifier: notifier,
                audioService: fakeAudio,
                initializeModels: fakeInitializeModels,
              ),
            ),
          ),
        ),
      );

      // Start future and advance to model init step
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      // Verify models initialized count
      expect(fakeAudio.initializeCallCount, equals(0));

      // Remove the widget from tree to trigger dispose
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));

      // Now complete the pending futures
      modelsCompleter.complete();
      fakeAudio.initCompleter.complete();

      // Pump and verify no errors are thrown
      await tester.pumpAndSettle();
    });

    testWidgets(
        'Double avvio: multiple widget rebuilds do not trigger multiple initializations',
        (WidgetTester tester) async {
      final fakeAudio = FakeBootAudioService();
      final modelsCompleter = Completer<void>();
      int modelsCallCount = 0;

      Future<void> fakeInitializeModels() async {
        modelsCallCount++;
        await modelsCompleter.future;
      }

      await tester.pumpWidget(
        MaterialApp(
          home: GameControllerProvider(
            notifier: notifier,
            child: BootMenuScreen(
              notifier: notifier,
              audioService: fakeAudio,
              initializeModels: fakeInitializeModels,
            ),
          ),
        ),
      );

      // Start future and advance to model init step
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      // Rebuild the widget multiple times with the same state (same hot-rebuild simulation)
      await tester.pumpWidget(
        MaterialApp(
          home: GameControllerProvider(
            notifier: notifier,
            child: BootMenuScreen(
              notifier: notifier,
              audioService: fakeAudio,
              initializeModels: fakeInitializeModels,
            ),
          ),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: GameControllerProvider(
            notifier: notifier,
            child: BootMenuScreen(
              notifier: notifier,
              audioService: fakeAudio,
              initializeModels: fakeInitializeModels,
            ),
          ),
        ),
      );

      expect(modelsCallCount, equals(1));
    });
  });
}

class FakeBootAudioService implements BootAudioService {
  final Completer<void> initCompleter = Completer<void>();
  bool throwOnError = false;
  void Function(String)? onEvent;

  int initializeCallCount = 0;
  int transitionCallCount = 0;

  @override
  Future<void> initialize({
    required String appDataPath,
    required bool audioEnabled,
  }) async {
    initializeCallCount++;
    onEvent?.call('audio:start');
    await initCompleter.future;
    if (throwOnError) {
      throw Exception("Simulated audio error");
    }
    onEvent?.call('audio:complete');
  }

  @override
  Future<void> transitionToMenu() async {
    transitionCallCount++;
    onEvent?.call('audio:transition');
  }
}
