import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
