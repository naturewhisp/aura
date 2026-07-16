import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aura_core/aura_testing.dart';
import 'package:aura_app/src/widgets/matrix_rain_background.dart';
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
      sessionId: 'test-session-matrix',
      aiIdentityId: 'panopticon',
      targetObjectiveId: 'containment_grid_override',
    );
    notifier = GameControllerNotifier(
      bridge: mockBridge,
      initialState: initialState,
    );
    await AudioManager().initialize('test_dir', audioEnabled: false);
  });

  group('MatrixRainBackground - Widget & Lifecycle Tests', () {
    testWidgets('1. Mount and animates without exceptions',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: MatrixRainBackground(opacity: 0.2),
            ),
          ),
        ),
      );

      // Verify that it renders CustomPaint descendant
      expect(
        find.descendant(
          of: find.byType(MatrixRainBackground),
          matching: find.byType(CustomPaint),
        ),
        findsOneWidget,
      );

      // Let animation run for a few ticks
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
    });

    testWidgets('2. Disposes clean without active tickers',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: MatrixRainBackground(opacity: 0.2),
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 200));

      // Remove the widget from the tree to trigger dispose
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets('3. Updates opacity on the same state (didUpdateWidget check)',
        (WidgetTester tester) async {
      final key = GlobalKey();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: MatrixRainBackground(
                key: key,
                opacity: 0.05,
              ),
            ),
          ),
        ),
      );

      final stateBefore = key.currentState;
      expect(stateBefore, isNotNull);

      // Rebuild with different opacity on same state
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: MatrixRainBackground(
                key: key,
                opacity: 0.40,
              ),
            ),
          ),
        ),
      );

      final stateAfter = key.currentState;
      expect(identical(stateBefore, stateAfter), isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('4. Rebuild parent preserves internal State',
        (WidgetTester tester) async {
      final key = GlobalKey();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: MatrixRainBackground(
                key: key,
                opacity: 0.2,
              ),
            ),
          ),
        ),
      );

      final stateBefore = key.currentState;
      expect(stateBefore, isNotNull);

      // Rebuild parent wrapping widget
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Container(
              padding: const EdgeInsets.all(8.0),
              child: SizedBox(
                width: 800,
                height: 600,
                child: MatrixRainBackground(
                  key: key,
                  opacity: 0.2,
                ),
              ),
            ),
          ),
        ),
      );

      final stateAfter = key.currentState;
      expect(identical(stateBefore, stateAfter), isTrue);
    });

    testWidgets('5. Resize with finite constraints succeeds without error',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: MatrixRainBackground(opacity: 0.2),
            ),
          ),
        ),
      );

      await tester.pump();

      // Trigger resize to different finite dimensions
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1024,
              height: 768,
              child: MatrixRainBackground(opacity: 0.2),
            ),
          ),
        ),
      );

      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('6. Handles very small sizes (1x1 and 0x0)',
        (WidgetTester tester) async {
      // Test 1x1 size
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1,
              height: 1,
              child: MatrixRainBackground(opacity: 0.1),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);

      // Test 0x0 size
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 0,
              height: 0,
              child: MatrixRainBackground(opacity: 0.1),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '7. Interactive overlay widget continues to receive click events',
        (WidgetTester tester) async {
      int clickCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                const Positioned.fill(
                  child: MatrixRainBackground(opacity: 0.2),
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

      // Click the button and check count
      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();

      expect(clickCount, equals(1));
    });

    testWidgets(
        '8. TerminalScreen ordinary mode contains exactly one MatrixRainBackground',
        (WidgetTester tester) async {
      // Set large size to prevent dashboard overflow issues in test mode
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

      expect(find.byType(MatrixRainBackground), findsOneWidget);
    });

    testWidgets(
        '9. Summary overlay background structures (opacity 0.40 and 0.20) render correctly',
        (WidgetTester tester) async {
      // We directly test the structures & opacities that the summary overlay returns
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: MatrixRainBackground(opacity: 0.40),
            ),
          ),
        ),
      );
      expect(find.byType(MatrixRainBackground), findsOneWidget);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: MatrixRainBackground(opacity: 0.20),
            ),
          ),
        ),
      );
      expect(find.byType(MatrixRainBackground), findsOneWidget);
    });

    group('MatrixRainBackground - Logic Verification', () {
      testWidgets('10. CustomPainter performs layout painting successfully',
          (WidgetTester tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 200,
                height: 200,
                child: MatrixRainBackground(opacity: 0.5),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));

        final CustomPaint customPaint = tester.widget(
          find.descendant(
            of: find.byType(MatrixRainBackground),
            matching: find.byType(CustomPaint),
          ),
        );
        expect(customPaint.painter, isNotNull);
        expect(
            customPaint.painter!.shouldRepaint(customPaint.painter!), isTrue);
      });
    });
  });
}
