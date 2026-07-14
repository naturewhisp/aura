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
      final modelsCompleter = Completer<ModelInitializationResult>();
      final events = <String>[];
      int modelsCallCount = 0;

      Future<ModelInitializationResult> fakeInitializeModels() async {
        modelsCallCount++;
        events.add('models:start');
        final result = await modelsCompleter.future;
        events.add('models:complete');
        return result;
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

      // Start the future and wait for the first 2 steps to complete (600ms)
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(); // Allow microtasks to execute the models callback

      expect(modelsCallCount, equals(1));
      expect(events, contains('models:start'));
      expect(events, isNot(contains('models:complete')));
      expect(events, isNot(contains('audio:start')));

      // Complete models initialization with online status
      modelsCompleter.complete(const ModelInitializationResult(
        status: ModelInitializationStatus.online,
        activeProfile: "Test Profile",
      ));
      await tester.pump(); // Advance microtasks

      // Wait for next delayed steps (300ms + 300ms)
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(); // Allow microtasks to start audio

      // Models should be complete and audio should have started
      expect(events, contains('models:complete'));
      expect(events, contains('audio:start'));
      expect(events, isNot(contains('audio:complete')));

      // Complete audio initialization
      fakeAudio.initCompleter.complete();
      await tester.pump();
      await tester.pump(const Duration(
          milliseconds: 1800)); // wait for boot to complete including delays

      expect(events, contains('audio:complete'));
      expect(
          events,
          isNot(contains(
              'audio:transition'))); // Transition happens at menu proceed
      expect(fakeAudio.initializeCallCount, equals(1));
      expect(fakeAudio.transitionCallCount, equals(0));

      // Confirm log prints for online profile
      expect(
          find.textContaining('Model Router profile: [Test Profile] loaded.'),
          findsOneWidget);
      expect(find.textContaining('ACTIVE ENGINES IDENTIFIED AND ROUTED.'),
          findsOneWidget);
      expect(find.textContaining('CONNECTING TO NEURAL PORT'), findsOneWidget);

      // Verify sequence order
      final modelsStartIndex = events.indexOf('models:start');
      final modelsCompleteIndex = events.indexOf('models:complete');
      final audioStartIndex = events.indexOf('audio:start');
      final audioCompleteIndex = events.indexOf('audio:complete');

      expect(modelsStartIndex < modelsCompleteIndex, isTrue);
      expect(modelsCompleteIndex < audioStartIndex, isTrue);
      expect(audioStartIndex < audioCompleteIndex, isTrue);

      // Now press Enter to transition to menu
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(fakeAudio.transitionCallCount, equals(1));
      expect(events, contains('audio:transition'));
    });

    testWidgets('Models initialize with no models warning logs',
        (WidgetTester tester) async {
      final fakeAudio = FakeBootAudioService();
      final modelsCompleter = Completer<ModelInitializationResult>();

      Future<ModelInitializationResult> fakeInitializeModels() async {
        return modelsCompleter.future;
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

      // Start future
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();

      // Resolve with noModelsDiscovered status
      modelsCompleter.complete(const ModelInitializationResult(
        status: ModelInitializationStatus.noModelsDiscovered,
        activeProfile: "Offline Fallback",
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      // Complete audio
      fakeAudio.initCompleter.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1800));

      // Verify warnings instead of online profile success prints
      expect(find.textContaining('Nessun modello rilevato.'), findsOneWidget);
      expect(
          find.textContaining('Configurazione modelli predefinita mantenuta.'),
          findsOneWidget);
      expect(find.textContaining('Model Router profile'), findsNothing);
      expect(find.textContaining('ACTIVE ENGINES IDENTIFIED'), findsNothing);
    });

    testWidgets('Models initialize with unavailable warning logs',
        (WidgetTester tester) async {
      final fakeAudio = FakeBootAudioService();
      final modelsCompleter = Completer<ModelInitializationResult>();

      Future<ModelInitializationResult> fakeInitializeModels() async {
        return modelsCompleter.future;
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

      // Start future
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();

      // Resolve with unavailable status
      modelsCompleter.complete(const ModelInitializationResult(
        status: ModelInitializationStatus.unavailable,
        activeProfile: "Offline Fallback",
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      // Complete audio
      fakeAudio.initCompleter.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1800));

      // Verify warnings instead of online profile success prints
      expect(
          find.textContaining('Model Router non disponibile.'), findsOneWidget);
      expect(
          find.textContaining('Configurazione modelli predefinita mantenuta.'),
          findsOneWidget);
      expect(find.textContaining('Model Router profile'), findsNothing);
      expect(find.textContaining('ACTIVE ENGINES IDENTIFIED'), findsNothing);
    });

    testWidgets('Pending models: Press Enter not visible and Enter key ignored',
        (WidgetTester tester) async {
      final fakeAudio = FakeBootAudioService();
      final modelsCompleter = Completer<ModelInitializationResult>();

      Future<ModelInitializationResult> fakeInitializeModels() async {
        return modelsCompleter.future;
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
      await tester.pump();

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
      final modelsCompleter = Completer<ModelInitializationResult>()
        ..complete(const ModelInitializationResult(
          status: ModelInitializationStatus.online,
          activeProfile: "Test Profile",
        ));

      Future<ModelInitializationResult> fakeInitializeModels() async {
        return modelsCompleter.future;
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

      // Complete models and start audio
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pump(); // Allow microtask to start audio

      // Trigger audio init error
      fakeAudio.initCompleter.complete();
      await tester.pump();

      // Wait out the rest of the boot delays (ASCII art + Enter visible)
      await tester.pump(const Duration(milliseconds: 1800));

      // Boot should be completed even if audio threw an error
      expect(find.textContaining('PREMI ENTER'), findsOneWidget);

      // Verify that audio initialized was called
      expect(fakeAudio.initializeCallCount, equals(1));
    });

    testWidgets(
        'Widget disposed during boot: completing futures does not throw setState after dispose',
        (WidgetTester tester) async {
      final fakeAudio = FakeBootAudioService();
      final modelsCompleter = Completer<ModelInitializationResult>();

      Future<ModelInitializationResult> fakeInitializeModels() async {
        return modelsCompleter.future;
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
      await tester.pump();

      // Verify models initialized count
      expect(fakeAudio.initializeCallCount, equals(0));

      // Remove the widget from tree to trigger dispose
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));

      // Now complete the pending futures
      modelsCompleter.complete(const ModelInitializationResult(
        status: ModelInitializationStatus.online,
        activeProfile: "Test Profile",
      ));
      fakeAudio.initCompleter.complete();

      // Pump and verify no errors are thrown
      await tester.pumpAndSettle();
    });

    testWidgets(
        'Double avvio: multiple widget rebuilds do not trigger multiple initializations',
        (WidgetTester tester) async {
      final fakeAudio = FakeBootAudioService();
      final modelsCompleter = Completer<ModelInitializationResult>();
      int modelsCallCount = 0;

      Future<ModelInitializationResult> fakeInitializeModels() async {
        modelsCallCount++;
        return modelsCompleter.future;
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
      await tester.pump();

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

    testWidgets(
        'Unexpected error during boot: displays critical error and offers retry interaction',
        (WidgetTester tester) async {
      final fakeAudio = FakeBootAudioService();

      Future<ModelInitializationResult> fakeInitializeModelsWithCrash() async {
        throw Exception("Unexpected internal error!");
      }

      await tester.pumpWidget(
        MaterialApp(
          home: GameControllerProvider(
            notifier: notifier,
            child: BootMenuScreen(
              notifier: notifier,
              audioService: fakeAudio,
              initializeModels: fakeInitializeModelsWithCrash,
            ),
          ),
        ),
      );

      // Start future and let it throw
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();

      // Check that critical error message and retry prompt are visible
      expect(find.textContaining('CRITICAL ERROR'), findsOneWidget);
      expect(find.textContaining('INVIO PER RIPROVARE'), findsOneWidget);

      // Pushing enter when error is active does NOT open main menu (PROGETTO SINDROME not visible)
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('PROGETTO SINDROME'), findsNothing);

      // Consume the pending retry sequence timers to prevent test leak errors
      await tester.pump(const Duration(seconds: 3));
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
