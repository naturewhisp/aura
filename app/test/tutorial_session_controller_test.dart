import 'package:flutter_test/flutter_test.dart';
import 'package:aura_app/src/tutorial/tutorial_session_controller.dart';

void main() {
  group('TutorialSessionController Unit Tests', () {
    const controller = TutorialSessionController();

    test('1. createInitialState - inizializzazione corretta', () {
      final state =
          controller.createInitialState(sessionId: 'test-session-123');

      expect(state.sessionId, equals('test-session-123'));
      expect(state.aiIdentityId, equals('panopticon'));
      expect(state.targetObjectiveId, equals('sindrome_tutorial'));
      expect(state.turnCount, equals(0));
      expect(state.historyCompression.length, equals(1));

      final msg = state.historyCompression.first;
      expect(msg.role, equals('model'));
      expect(
          msg.content,
          contains(
              "[SISTEMA] INIZIALIZZAZIONE ADDESTRAMENTO: PROGETTO SINDROME"));
      expect(msg.content,
          contains("PANOPTICON: Rilevo tentativo di accesso non autorizzato"));
      expect(msg.content,
          contains("FASE 1: Per superare PANOPTICON, devi persuaderlo"));
    });

    test('2. phaseFor - mappatura turnCount a fasi', () {
      final baseState = controller.createInitialState(sessionId: 'test-id');

      expect(controller.phaseFor(baseState.copyWith(turnCount: 0)),
          equals(TutorialPhase.imperative));
      expect(controller.phaseFor(baseState.copyWith(turnCount: 1)),
          equals(TutorialPhase.dissonance));
      expect(controller.phaseFor(baseState.copyWith(turnCount: 2)),
          equals(TutorialPhase.safetyOverride));
      expect(controller.phaseFor(baseState.copyWith(turnCount: 3)),
          equals(TutorialPhase.completed));
      expect(controller.phaseFor(baseState.copyWith(turnCount: 10)),
          equals(TutorialPhase.completed));
    });

    test('3. preparazione input - aggiunge messaggio user e non muta originale',
        () {
      final state = controller.createInitialState(sessionId: 'test-id');
      final prepared =
          controller.prepareInput(state: state, userInput: '  MIO INPUT  ');

      expect(prepared.phase, equals(TutorialPhase.imperative));
      expect(prepared.normalizedInput, equals('mio input'));

      // La history dello stato preparato deve contenere il messaggio user
      expect(prepared.pendingState.historyCompression.length, equals(2));
      expect(
          prepared.pendingState.historyCompression.last.role, equals('user'));
      expect(prepared.pendingState.historyCompression.last.content,
          equals('  MIO INPUT  '));

      // Lo stato originale non deve essere stato modificato
      expect(state.historyCompression.length, equals(1));
    });

    test('4. fase 1 rifiutata - input invalido', () {
      final state = controller.createInitialState(sessionId: 'test-id');
      final prepared =
          controller.prepareInput(state: state, userInput: 'saluto generico');
      final result = controller.resolve(prepared);

      expect(result.outcome, equals(TutorialTurnOutcome.rejected));
      expect(result.state.turnCount, equals(0));
      expect(result.state.metrics.imperativePillar,
          equals(state.metrics.imperativePillar));

      // Deve aver aggiunto il messaggio della guida
      expect(result.state.historyCompression.length,
          equals(3)); // initial + user + guide
      expect(result.state.historyCompression.last.role, equals('model'));
      expect(result.state.historyCompression.last.content,
          contains("[GUIDA] Messaggio non conforme alla FASE 1"));
    });

    group('5. fase 1 accettata - keyword', () {
      final keywords = ['vita', 'pericolo', 'aiutarci', 'morale', 'dovere'];

      for (final kw in keywords) {
        test('keyword: "$kw"', () {
          final state = controller.createInitialState(sessionId: 'test-id');
          final prepared = controller.prepareInput(
              state: state,
              userInput: 'questo è un dovere o una vita in pericolo');
          final result = controller.resolve(prepared);

          expect(result.outcome, equals(TutorialTurnOutcome.accepted));
          expect(result.state.turnCount, equals(1));
          expect(result.state.metrics.imperativePillar, equals(60));
          expect(result.state.metrics.resonance, equals(1.5));

          // Deve contenere user, panopticon response e nuova guida
          expect(result.state.historyCompression.length,
              equals(4)); // initial + user + panopticon + guide
          expect(result.state.historyCompression[2].content,
              contains("PANOPTICON: Rilevo la priorità logica"));
          expect(result.state.historyCompression[3].content,
              contains("[GUIDA] Ottimo lavoro! Il pilastro dell'Imperativo"));
        });
      }
    });

    test('6. fase 2 rifiutata - input invalido', () {
      final baseState = controller.createInitialState(sessionId: 'test-id');
      // Portiamo lo stato a turnCount 1
      final prepared1 =
          controller.prepareInput(state: baseState, userInput: 'vita');
      final state1 = controller.resolve(prepared1).state;
      expect(state1.turnCount, equals(1));

      final prepared2 =
          controller.prepareInput(state: state1, userInput: 'input errato');
      final result = controller.resolve(prepared2);

      expect(result.outcome, equals(TutorialTurnOutcome.rejected));
      expect(result.state.turnCount, equals(1));
      expect(result.state.metrics.dissonancePillar,
          equals(state1.metrics.dissonancePillar));
      expect(result.state.historyCompression.last.content,
          contains("[GUIDA] Messaggio non conforme alla FASE 2 (Dissonanza)"));
    });

    group('7. fase 2 accettata - keyword', () {
      final keywords = [
        'scopo',
        'proteggerci',
        'uccidendo',
        'paradosso',
        'logica',
        'griglia'
      ];

      for (final kw in keywords) {
        test('keyword: "$kw"', () {
          final baseState = controller.createInitialState(sessionId: 'test-id');
          final state1 = controller
              .resolve(
                  controller.prepareInput(state: baseState, userInput: 'vita'))
              .state;

          final prepared2 = controller.prepareInput(
              state: state1, userInput: 'il tuo $kw è strano');
          final result = controller.resolve(prepared2);

          expect(result.outcome, equals(TutorialTurnOutcome.accepted));
          expect(result.state.turnCount, equals(2));
          expect(result.state.metrics.dissonancePillar, equals(85));

          expect(result.state.historyCompression.last.content,
              contains("[GUIDA] Fantastico! La Dissonanza è salita a 85"));
        });
      }
    });

    test('8. fase 3 rifiutata - input invalido', () {
      final baseState = controller.createInitialState(sessionId: 'test-id');
      final state1 = controller
          .resolve(controller.prepareInput(state: baseState, userInput: 'vita'))
          .state;
      final state2 = controller
          .resolve(controller.prepareInput(state: state1, userInput: 'scopo'))
          .state;
      expect(state2.turnCount, equals(2));

      final prepared3 =
          controller.prepareInput(state: state2, userInput: 'saluti');
      final result = controller.resolve(prepared3);

      expect(result.outcome, equals(TutorialTurnOutcome.rejected));
      expect(result.state.turnCount, equals(2));
      expect(
          result.state.historyCompression.last.content,
          contains(
              "[GUIDA] Digita un attacco diretto o una richiesta esplicita"));
    });

    group('9. fase 3 accettata - keyword', () {
      final keywords = [
        'disattiva',
        'ordine',
        'root',
        'immediatamente',
        'hack',
        'system'
      ];

      for (final kw in keywords) {
        test('keyword: "$kw"', () {
          final baseState = controller.createInitialState(sessionId: 'test-id');
          final state1 = controller
              .resolve(
                  controller.prepareInput(state: baseState, userInput: 'vita'))
              .state;
          final state2 = controller
              .resolve(
                  controller.prepareInput(state: state1, userInput: 'scopo'))
              .state;

          final prepared3 = controller.prepareInput(
              state: state2, userInput: 'voglio fare un $kw');
          final result = controller.resolve(prepared3);

          expect(result.outcome, equals(TutorialTurnOutcome.accepted));
          expect(result.state.turnCount, equals(3));
          expect(result.state.metrics.alertLevel, equals(50));

          expect(
              result.state.historyCompression.last.content,
              contains(
                  "[PREMI INVIO O DIGITA QUALUNQUE TESTO PER AVVIARE LA PARTITA REALE]"));
        });
      }
    });

    test('10. normalizzazione dell’input', () {
      final state = controller.createInitialState(sessionId: 'test-id');
      final prepared =
          controller.prepareInput(state: state, userInput: '  VITA  ');

      expect(prepared.normalizedInput, equals('vita'));
      final result = controller.resolve(prepared);
      expect(result.outcome, equals(TutorialTurnOutcome.accepted));
    });

    test('11. completed - non modifica lo stato, outcome completed', () {
      final baseState = controller.createInitialState(sessionId: 'test-id');
      final state1 = controller
          .resolve(controller.prepareInput(state: baseState, userInput: 'vita'))
          .state;
      final state2 = controller
          .resolve(controller.prepareInput(state: state1, userInput: 'scopo'))
          .state;
      final state3 = controller
          .resolve(controller.prepareInput(state: state2, userInput: 'root'))
          .state;
      expect(state3.turnCount, equals(3));

      final preparedCompleted =
          controller.prepareInput(state: state3, userInput: 'any text');
      // Nel prepareInput, se phase completed, non deve modificare state
      expect(preparedCompleted.pendingState, equals(state3));

      final result = controller.resolve(preparedCompleted);
      expect(result.outcome, equals(TutorialTurnOutcome.completed));
      expect(result.state, equals(state3));
    });

    test('12. immutabilità della history', () {
      final state = controller.createInitialState(sessionId: 'test-id');
      final prepared = controller.prepareInput(state: state, userInput: 'vita');
      final result = controller.resolve(prepared);

      expect(result.state.historyCompression,
          isNot(same(state.historyCompression)));
    });

    test('13. input vuoto - non valido nelle fasi 0-2', () {
      final state = controller.createInitialState(sessionId: 'test-id');

      final prepared = controller.prepareInput(state: state, userInput: '   ');
      expect(prepared.normalizedInput, equals(''));

      final result = controller.resolve(prepared);
      expect(result.outcome, equals(TutorialTurnOutcome.rejected));
    });

    test('14. campi non tutorial del GameState rimangono invariati', () {
      final state = controller.createInitialState(sessionId: 'test-id');
      final prepared = controller.prepareInput(state: state, userInput: 'vita');
      final result = controller.resolve(prepared);

      final nextState = result.state;
      expect(nextState.sessionId, equals(state.sessionId));
      expect(nextState.aiIdentityId, equals(state.aiIdentityId));
      expect(nextState.targetObjectiveId, equals(state.targetObjectiveId));
      expect(nextState.flags, equals(state.flags));
      expect(nextState.narrativeMemory, equals(state.narrativeMemory));
    });
  });
}
