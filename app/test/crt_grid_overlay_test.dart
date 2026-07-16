import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aura_core/aura_testing.dart';
import 'package:aura_app/src/widgets/crt_grid_overlay.dart';
import 'package:aura_app/src/screens/terminal_screen.dart';
import 'package:aura_app/src/state_management/game_controller_notifier.dart';
import 'package:aura_app/src/audio/audio_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GameControllerNotifier notifier;
  late MockInferenceBridge mockBridge;

  setUp(() async {
    mockBridge = MockInferenceBridge();
    final initialState = GameState.initial(
      sessionId: 'test-session-crt',
      aiIdentityId: 'panopticon',
      targetObjectiveId: 'containment_grid_override',
    );
    notifier = GameControllerNotifier(
      bridge: mockBridge,
      initialState: initialState,
    );
    await AudioManager().initialize('test_dir', audioEnabled: false);
  });

  group('CrtGridOverlay - Widget & Lifecycle Tests', () {
    testWidgets('1. Mount senza flicker e anima senza eccezioni',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: CrtGridOverlay(flicker: false),
            ),
          ),
        ),
      );

      // Verifica che CustomPaint sia discendente del widget
      expect(
        find.descendant(
          of: find.byType(CrtGridOverlay),
          matching: find.byType(CustomPaint),
        ),
        findsOneWidget,
      );

      // Lascia girare l'animazione per alcuni tick
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
    });

    testWidgets('2. Mount con flicker attivo e anima senza eccezioni',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: CrtGridOverlay(flicker: true),
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
    });

    testWidgets('3. Dispose pulito senza ticker attivi',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: CrtGridOverlay(flicker: false),
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 200));

      // Rimuove il widget dall'albero per innescare dispose
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets('4. Rebuild parent preserva lo State interno',
        (WidgetTester tester) async {
      final key = GlobalKey();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: CrtGridOverlay(key: key, flicker: false),
            ),
          ),
        ),
      );

      final stateBefore = key.currentState;
      expect(stateBefore, isNotNull);

      // Rebuild del widget padre
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Container(
              padding: const EdgeInsets.all(8.0),
              child: SizedBox(
                width: 800,
                height: 600,
                child: CrtGridOverlay(key: key, flicker: false),
              ),
            ),
          ),
        ),
      );

      final stateAfter = key.currentState;
      expect(identical(stateBefore, stateAfter), isTrue);
    });

    testWidgets('5. Toggle flicker aggiorna il widget senza errori',
        (WidgetTester tester) async {
      final key = GlobalKey();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: CrtGridOverlay(key: key, flicker: false),
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));

      // Attiva il flicker
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: CrtGridOverlay(key: key, flicker: true),
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
    });

    testWidgets('6. Il widget è IgnorePointer — i click passano attraverso',
        (WidgetTester tester) async {
      int clickCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                const Positioned.fill(
                  child: CrtGridOverlay(flicker: false),
                ),
                Positioned(
                  left: 100,
                  top: 100,
                  child: ElevatedButton(
                    onPressed: () {
                      clickCount++;
                    },
                    child: const Text('Test Button'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();

      expect(clickCount, equals(1));
    });

    testWidgets('7. Gestisce dimensioni molto piccole (1x1 e 0x0)',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1,
              height: 1,
              child: CrtGridOverlay(flicker: false),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 0,
              height: 0,
              child: CrtGridOverlay(flicker: false),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('8. TerminalScreen contiene esattamente un CrtGridOverlay',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: GameControllerProvider(
            notifier: notifier,
            child: TerminalScreen(notifier: notifier),
          ),
        ),
      );

      expect(find.byType(CrtGridOverlay), findsOneWidget);
    });

    group('CrtGridOverlay - Verifica logica CustomPainter', () {
      testWidgets('9. CustomPainter è presente e shouldRepaint funziona',
          (WidgetTester tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 200,
                height: 200,
                child: CrtGridOverlay(flicker: false),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));

        final CustomPaint customPaint = tester.widget(
          find.descendant(
            of: find.byType(CrtGridOverlay),
            matching: find.byType(CustomPaint),
          ),
        );
        expect(customPaint.painter, isNotNull);
        // shouldRepaint ritorna true solo se l'opacità è cambiata;
        // con lo stesso painter l'opacità è identica → false.
        expect(
          customPaint.painter!.shouldRepaint(customPaint.painter!),
          isFalse,
        );
      });
    });
  });
}
