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

  testWidgets('AudioReactiveBackground - Performance Benchmarking Test',
      (WidgetTester tester) async {
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

    debugPrint(
        "[PERFORMANCE BENCHMARK] Tempo totale per 60 frame: ${totalMs}ms (Media: ${avgMsPerFrame.toStringAsFixed(2)}ms/frame)");

    // Il tempo di rendering headless deve essere ampiamente inferiore a 33.3ms (budget di 30 FPS)
    expect(avgMsPerFrame, lessThan(33.3));
  });

  group('AudioReactiveBackground - Fasi 1 & 2 tests', () {
    test('1. Continuità al wrapping', () {
      const spacing = 18.0;
      const speed = 60.0;
      const logicalIndex = 1;

      // Tempo t1 prima del crossing (spacing = 18, t = 18 / 60 = 0.3)
      final pos1 = DnaHelixPainter.calculatePositionForLogicalIndex(
        logicalIndex: logicalIndex,
        motionSeconds: 0.29,
        scrollPixelsPerSecond: speed,
        spacing: spacing,
      );

      // Tempo t2 dopo il crossing
      final pos2 = DnaHelixPainter.calculatePositionForLogicalIndex(
        logicalIndex: logicalIndex,
        motionSeconds: 0.31,
        scrollPixelsPerSecond: speed,
        spacing: spacing,
      );

      // La differenza deve essere esattamente pari a speed * dt (60 * 0.02 = 1.2px a sinistra)
      const expectedDelta = -speed * 0.02;
      expect(pos2 - pos1, closeTo(expectedDelta, 1e-9));
    });

    test('2. Indice logico continuo', () {
      const spacing = 18.0;
      const speed = 60.0;

      // t1 prima del crossing: scrollDistance = 17.4
      const scrollDistance1 = 0.29 * speed;
      final firstLogicalIndex1 = (scrollDistance1 / spacing).floor();
      final fractionalOffset1 = scrollDistance1 - firstLogicalIndex1 * spacing;

      expect(firstLogicalIndex1, equals(0));
      expect(fractionalOffset1, closeTo(17.4, 1e-9));

      // t2 dopo il crossing: scrollDistance = 18.6
      const scrollDistance2 = 0.31 * speed;
      final firstLogicalIndex2 = (scrollDistance2 / spacing).floor();
      final fractionalOffset2 = scrollDistance2 - firstLogicalIndex2 * spacing;

      expect(firstLogicalIndex2, equals(1));
      expect(fractionalOffset2, closeTo(0.6, 1e-9));

      // La posizione visibile del logicalIndex 1 deve continuare in modo fluido
      final localIndex1 = 1 - firstLogicalIndex1; // 1 - 0 = 1
      final x1 = localIndex1 * spacing - fractionalOffset1; // 1 * 18 - 17.4 = 0.6

      final localIndex2 = 1 - firstLogicalIndex2; // 1 - 1 = 0
      final x2 = localIndex2 * spacing - fractionalOffset2; // 0 * 18 - 0.6 = -0.6

      expect(x2 - x1, closeTo(-1.2, 1e-9));
    });

    test('3. Cambio traccia senza reset del movimento (realistico)', () {
      const spacing = 18.0;
      const speed = 60.0;
      const logicalIndex = 5;

      double simulatedTime = 10.0;

      // 1. Calcola posizione a t = 10.0
      final pos1 = DnaHelixPainter.calculatePositionForLogicalIndex(
        logicalIndex: logicalIndex,
        motionSeconds: simulatedTime,
        scrollPixelsPerSecond: speed,
        spacing: spacing,
      );

      // 2. Avanza il tempo simulato di un frame (16ms) simulating track change happening in between
      simulatedTime = 10.016;

      // 3. Calcola la nuova posizione
      final pos2 = DnaHelixPainter.calculatePositionForLogicalIndex(
        logicalIndex: logicalIndex,
        motionSeconds: simulatedTime,
        scrollPixelsPerSecond: speed,
        spacing: spacing,
      );

      // 4. Verifica che lo spostamento sia continuo e pari a speed * 0.016
      const expectedDelta = -speed * 0.016;
      expect(pos2 - pos1, closeTo(expectedDelta, 1e-9));

      // 5. Verifica che non ritorni alla posizione iniziale (quella a t = 0)
      final posInitial = DnaHelixPainter.calculatePositionForLogicalIndex(
        logicalIndex: logicalIndex,
        motionSeconds: 0.0,
        scrollPixelsPerSecond: speed,
        spacing: spacing,
      );
      expect(pos2, isNot(closeTo(posInitial, 1e-9)));
    });

    test('3b. Cambio traccia e riallineamento del beat', () {
      const beatDuration = 0.5; // 120 BPM

      // 1. All'istante t = 10.0, con trackStart = 9.8 (beatSeconds = 0.2)
      final trackStart1 = DateTime.fromMillisecondsSinceEpoch(9800);
      final now1 = DateTime.fromMillisecondsSinceEpoch(10000);
      final beatSeconds1 = now1.difference(trackStart1).inMicroseconds / 1000000.0;
      final pulse1 = DnaHelixPainter.calculateBeatPulse(
        beatSeconds: beatSeconds1,
        beatDuration: beatDuration,
      );

      // 2. Simula cambio traccia a t = 10.0, con trackStart = 10.0 (beatSeconds = 0.0)
      final trackStart2 = DateTime.fromMillisecondsSinceEpoch(10000);
      final beatSeconds2 = now1.difference(trackStart2).inMicroseconds / 1000000.0;
      final pulse2 = DnaHelixPainter.calculateBeatPulse(
        beatSeconds: beatSeconds2,
        beatDuration: beatDuration,
      );

      // Le due pulsazioni del beat devono riallinearsi e quindi differire
      expect(pulse1, isNot(closeTo(pulse2, 1e-9)));
      expect(pulse2, closeTo(1.0, 1e-9)); // Al picco
    });

    test('4. Glifi sfalsati (usa funzione di produzione)', () {
      // Nodi diversi nello stesso frame devono poter avere tick diversi
      final tick1 = DnaHelixPainter.calculateGlyphTick(
        motionSeconds: 1.5,
        logicalIndex: 0,
        wireIndex: 0,
      );
      final tick2 = DnaHelixPainter.calculateGlyphTick(
        motionSeconds: 1.5,
        logicalIndex: 10,
        wireIndex: 0,
      );
      expect(tick1, isNot(equals(tick2)));
    });

    test('5. Beat envelope (usa funzione di produzione)', () {
      const beatDuration = 0.5;

      // Range 0.0 - 1.0 e picco a 0 e 0.5 (periodico)
      expect(DnaHelixPainter.calculateBeatPulse(beatSeconds: 0.0, beatDuration: beatDuration), closeTo(1.0, 1e-9));
      expect(DnaHelixPainter.calculateBeatPulse(beatSeconds: 0.25, beatDuration: beatDuration), closeTo(0.0, 1e-9));
      expect(DnaHelixPainter.calculateBeatPulse(beatSeconds: 0.5, beatDuration: beatDuration), closeTo(1.0, 1e-9));

      // Continuità e assenza di salti ai confini (t = 0.499 e t = 0.501)
      final valBefore = DnaHelixPainter.calculateBeatPulse(beatSeconds: 0.499, beatDuration: beatDuration);
      final valAfter = DnaHelixPainter.calculateBeatPulse(beatSeconds: 0.501, beatDuration: beatDuration);
      expect(valBefore - valAfter, closeTo(0.0, 0.05));
    });

    testWidgets('6. Repaint pipeline e shouldRepaint', (WidgetTester tester) async {
      final mockController = AnimationController(
        vsync: const TestVSync(),
        duration: const Duration(seconds: 1),
      );
      double simulatedSeconds = 10.0;
      double motionSecondsProvider() => simulatedSeconds;

      final painter1 = DnaHelixPainter(
        repaintListenable: mockController,
        motionSecondsProvider: motionSecondsProvider,
        alertLevel: 10,
        outcome: GameOutcome.ongoing,
      );

      final painter2 = DnaHelixPainter(
        repaintListenable: mockController,
        motionSecondsProvider: motionSecondsProvider,
        alertLevel: 10,
        outcome: GameOutcome.ongoing,
      );

      final painter3 = DnaHelixPainter(
        repaintListenable: mockController,
        motionSecondsProvider: motionSecondsProvider,
        alertLevel: 30,
        outcome: GameOutcome.ongoing,
      );

      // shouldRepaint deve essere false se i parametri strutturali sono equivalenti
      expect(painter1.shouldRepaint(painter2), isFalse);

      // shouldRepaint deve essere true se alertLevel cambia
      expect(painter1.shouldRepaint(painter3), isTrue);

      mockController.dispose();
    });
  });
}
