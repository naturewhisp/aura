import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aura_core/aura_core.dart';
import 'package:aura_app/src/state_management/game_controller_notifier.dart';
import 'package:aura_app/src/widgets/audio_reactive_background.dart';
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

    // Inizializza l'AudioManager senza abilitare l'audio nativo reale per i test
    await AudioManager().initialize('test_dir', audioEnabled: false);
  });

  testWidgets('AudioReactiveBackground - Performance Benchmarking Test', (WidgetTester tester) async {
    // Costruisce la gerarchia dei widget con il Provider ed inserisce il widget reattivo
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GameControllerProvider(
            notifier: notifier,
            child: const AudioReactiveBackground(),
          ),
        ),
      ),
    );

    // Verifica che il widget sia correttamente istanziato ed inserito
    expect(find.byType(AudioReactiveBackground), findsOneWidget);

    // Esegue il benchmark simulando il rendering continuo di 60 frame (60 FPS)
    final stopwatch = Stopwatch()..start();
    
    for (int i = 0; i < 60; i++) {
      // Avanza il Ticker simulando il frame-rate a 60 FPS (circa 16.6ms per frame)
      await tester.pump(const Duration(milliseconds: 16, microseconds: 666));
    }
    
    stopwatch.stop();
    final int totalMs = stopwatch.elapsedMilliseconds;
    final double avgMsPerFrame = totalMs / 60.0;

    debugPrint("[PERFORMANCE BENCHMARK] Tempo totale per 60 frame: ${totalMs}ms (Media: ${avgMsPerFrame.toStringAsFixed(2)}ms/frame)");

    // Il tempo di rendering headless deve essere ampiamente inferiore a 33.3ms (budget di 30 FPS)
    expect(avgMsPerFrame, lessThan(33.3));
  });
}
