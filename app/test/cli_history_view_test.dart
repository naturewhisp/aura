import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aura_core/aura_core.dart';
import 'package:aura_app/src/widgets/cli_history_view.dart';

void main() {
  group('CLIHistoryView - Stato vuoto guidato', () {
    testWidgets('prima del primo turno spiega come giocare e come usare /menu',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CLIHistoryView(
              history: [],
              isLoading: false,
              currentLoadingMessage: '',
              loadingLogs: [],
            ),
          ),
        ),
      );

      expect(
          find.textContaining('CANALE APERTO CON PANOPTICON'), findsOneWidget);
      expect(find.textContaining('/menu'), findsOneWidget);
    });

    testWidgets('durante il caricamento del primo turno non mostra la guida',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CLIHistoryView(
              history: [],
              isLoading: true,
              currentLoadingMessage: 'Elaborazione...',
              loadingLogs: [],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('CANALE APERTO CON PANOPTICON'), findsNothing);
    });
  });

  testWidgets('a fine battitura la riga finale della risposta è visibile',
      (WidgetTester tester) async {
    Widget view(List<ChatMessage> history) => MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 200,
              child: CLIHistoryView(
                history: history,
                isLoading: false,
                currentLoadingMessage: '',
                loadingLogs: const [],
              ),
            ),
          ),
        );
    const opening = [ChatMessage(role: 'user', content: 'messaggio iniziale')];
    final reply = '${List.generate(9, (i) => 'riga $i').join('\n')}\nX';

    await tester.pumpWidget(view(opening));
    await tester.pump();
    await tester.pumpWidget(
        view([...opening, ChatMessage(role: 'model', content: reply)]));
    for (var i = 0; i < reply.length + 20; i++) {
      await tester.pump(const Duration(milliseconds: 15));
    }

    final position =
        tester.state<ScrollableState>(find.byType(Scrollable)).position;
    expect(position.maxScrollExtent, greaterThan(0));
    expect(position.pixels, closeTo(position.maxScrollExtent, 0.5));
  });

  testWidgets('chi ha scorso verso l’alto non viene riportato al fondo',
      (WidgetTester tester) async {
    Widget view(int width) => MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: width.toDouble(),
              height: 200,
              child: CLIHistoryView(
                history: List.generate(
                  30,
                  (i) => ChatMessage(role: 'user', content: 'messaggio $i'),
                ),
                isLoading: false,
                currentLoadingMessage: '',
                loadingLogs: const [],
              ),
            ),
          ),
        );
    await tester.pumpWidget(view(300));
    await tester.pump();
    await tester.drag(find.byType(Scrollable), const Offset(0, 400));
    await tester.pump();
    final position =
        tester.state<ScrollableState>(find.byType(Scrollable)).position;
    final before = position.maxScrollExtent - position.pixels;
    expect(before, greaterThan(80));

    // Cambio di metriche (messaggi che vanno a capo): nessun salto al fondo.
    await tester.pumpWidget(view(120));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(position.maxScrollExtent - position.pixels, greaterThan(80));
  });
}
