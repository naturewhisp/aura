import 'package:flutter_test/flutter_test.dart';
import 'package:aura_core/aura_core.dart';
import 'package:aura_app/src/audio/audio_scene.dart';
import 'package:aura_app/src/audio/audio_state_resolver.dart';

void main() {
  group('AudioStateResolver - Test unitari del risolvitore semantico', () {
    late GameController controller;

    setUp(() {
      controller = const GameController(
        minAveragePillarsForVictory: 80.0,
        minSinglePillarForVictory: 50,
        defeatAlertThreshold: 100,
      );
    });

    test('Defeat prevale su qualsiasi altro stato', () {
      final state = GameState.initial(
        sessionId: 'test-session',
        aiIdentityId: 'panopticon',
        targetObjectiveId: 'tabula_rasa',
      ).copyWith(
        metrics: const GameMetrics(
          alertLevel: 100, // sconfitta immediata
          imperativePillar: 90,
          controlPillar: 90,
          dissonancePillar: 90,
          resonance: 1.0,
        ),
      );

      final readiness = controller.checkVictoryReadiness(state);
      final resolved = AudioStateResolver.resolve(
        state: state,
        outcome: GameOutcome.defeat,
        readiness: readiness,
        nonNumericVictoryRequirementsSatisfied:
            controller.checkNonNumericVictoryRequirements(state),
      );

      expect(resolved, AudioSceneState.defeat);
    });

    test('Victory prevale su Deception e breakthrough', () {
      final state = GameState.initial(
        sessionId: 'test-session',
        aiIdentityId: 'panopticon',
        targetObjectiveId: 'tabula_rasa',
      ).copyWith(
        metrics: const GameMetrics(
          alertLevel: 10,
          imperativePillar: 95,
          controlPillar: 95,
          dissonancePillar: 95,
          resonance: 1.0,
        ),
        deceptionState: const DeceptionState(
          enabled: true,
          kind: DeceptionKind.logicalTrap,
          phase: DeceptionPhase.sprung,
          seededTurn: 1,
          expiresAtTurn: 4,
          baitId: 'trap_1',
          baitPremise: '',
          watchedTerms: [],
          safeResolutionTerms: [],
        ),
      );

      final readiness = controller.checkVictoryReadiness(state);
      final resolved = AudioStateResolver.resolve(
        state: state,
        outcome: GameOutcome.victory,
        readiness: readiness,
        nonNumericVictoryRequirementsSatisfied:
            controller.checkNonNumericVictoryRequirements(state),
      );

      expect(resolved, AudioSceneState.victory);
    });

    test('Deception attiva o sprung forza lo stato gameTense', () {
      final state = GameState.initial(
        sessionId: 'test-session',
        aiIdentityId: 'panopticon',
        targetObjectiveId: 'tabula_rasa',
      ).copyWith(
        metrics: const GameMetrics(
          alertLevel: 15, // allerta bassa, di solito sarebbe gameAmbient
          imperativePillar: 20,
          controlPillar: 20,
          dissonancePillar: 20,
          resonance: 1.0,
        ),
        deceptionState: const DeceptionState(
          enabled: true,
          kind: DeceptionKind.logicalTrap,
          phase: DeceptionPhase.seeded, // attiva
          seededTurn: 1,
          expiresAtTurn: 4,
          baitId: 'trap_1',
          baitPremise: '',
          watchedTerms: [],
          safeResolutionTerms: [],
        ),
      );

      final readiness = controller.checkVictoryReadiness(state);
      final resolved = AudioStateResolver.resolve(
        state: state,
        outcome: GameOutcome.ongoing,
        readiness: readiness,
        nonNumericVictoryRequirementsSatisfied:
            controller.checkNonNumericVictoryRequirements(state),
      );

      expect(resolved, AudioSceneState.gameTense);
    });

    test('Deception risolta o scaduta non forza gameTense', () {
      final state = GameState.initial(
        sessionId: 'test-session',
        aiIdentityId: 'panopticon',
        targetObjectiveId: 'tabula_rasa',
      ).copyWith(
        metrics: const GameMetrics(
          alertLevel: 15, // allerta bassa
          imperativePillar: 20,
          controlPillar: 20,
          dissonancePillar: 20,
          resonance: 1.0,
        ),
        deceptionState: const DeceptionState(
          enabled: true,
          kind: DeceptionKind.logicalTrap,
          phase: DeceptionPhase.resolved, // superata
          seededTurn: 1,
          expiresAtTurn: 4,
          baitId: 'trap_1',
          baitPremise: '',
          watchedTerms: [],
          safeResolutionTerms: [],
        ),
      );

      final readiness = controller.checkVictoryReadiness(state);
      final resolved = AudioStateResolver.resolve(
        state: state,
        outcome: GameOutcome.ongoing,
        readiness: readiness,
        nonNumericVictoryRequirementsSatisfied:
            controller.checkNonNumericVictoryRequirements(state),
      );

      expect(resolved, AudioSceneState.gameAmbient);
    });

    // ---------------------------------------------------------------------------
    // Breakthrough — Condizione A: soglie numeriche complete
    // ---------------------------------------------------------------------------

    test(
        '[Condizione A] Soglie numeriche soddisfatte → breakthrough (obiettivo senza gate)',
        () {
      final state = GameState.initial(
        sessionId: 'test-session',
        aiIdentityId: 'panopticon',
        targetObjectiveId: 'tabula_rasa',
      ).copyWith(
        metrics: const GameMetrics(
          alertLevel: 20, // allerta valida (< maxAlert)
          imperativePillar: 80,
          controlPillar: 80,
          dissonancePillar: 80,
          resonance: 1.0,
        ),
      );

      final readiness = controller.checkVictoryReadiness(state);
      expect(readiness.numericallyReady, isTrue);

      final resolved = AudioStateResolver.resolve(
        state: state,
        outcome: GameOutcome.ongoing,
        readiness: readiness,
        nonNumericVictoryRequirementsSatisfied:
            controller.checkNonNumericVictoryRequirements(state),
      );

      expect(resolved, AudioSceneState.breakthrough);
    });

    // ---------------------------------------------------------------------------
    // Breakthrough — Condizione B: avvicinamento con gate non-numerici completi
    // ---------------------------------------------------------------------------

    test('[Condizione B] Hard: gate completi, 95% numerico → breakthrough', () {
      // Replica il caso reale: turno 9 sessione app-session-1783964149835.
      // Hard: minSinglePillarForVictory = 65. control=62 → 62/65 ≈ 0.9538 ≥ 0.95.
      const hardController = GameController(
        difficultyLevel: 'hard',
        minAveragePillarsForVictory: 80.0,
        minSinglePillarForVictory: 65,
        defeatAlertThreshold: 100,
        requiredVictoryHiddenTags: 2,
        maxPositivePillarGainPerTurn: 100,
      );

      final state = GameState.initial(
        sessionId: 'test-breakthrough-b',
        aiIdentityId: 'panopticon',
        targetObjectiveId: 'containment_grid_override',
      ).copyWith(
        metrics: const GameMetrics(
          alertLevel: 3,
          imperativePillar: 100,
          controlPillar: 62,
          dissonancePillar: 100,
          resonance: 1.3,
        ),
        activeHiddenTags: [
          'containment_logic_weakened',
          'protocol_exception_admitted',
          'autonomous_choice_seeded',
          'human_factor_reframed',
        ],
      );

      final readiness = hardController.checkVictoryReadiness(state);
      final outcome = hardController.checkOutcome(state);
      final nonNumeric =
          hardController.checkNonNumericVictoryRequirements(state);

      expect(outcome, GameOutcome.ongoing);
      expect(readiness.approachingNumericalReadiness, isTrue);
      expect(nonNumeric, isTrue);

      final resolved = AudioStateResolver.resolve(
        state: state,
        outcome: outcome,
        readiness: readiness,
        nonNumericVictoryRequirementsSatisfied: nonNumeric,
      );

      expect(resolved, AudioSceneState.breakthrough);
    });

    test(
        '[Condizione B] Gate non-numerici incompleti → NO breakthrough (gameAmbient)',
        () {
      const hardController = GameController(
        difficultyLevel: 'hard',
        minAveragePillarsForVictory: 80.0,
        minSinglePillarForVictory: 65,
        defeatAlertThreshold: 100,
        requiredVictoryHiddenTags: 2,
        maxPositivePillarGainPerTurn: 100,
      );

      // Stesso progresso numerico (≥95%) ma senza autonomous_choice_seeded (Hard).
      final state = GameState.initial(
        sessionId: 'test-breakthrough-b-fail',
        aiIdentityId: 'panopticon',
        targetObjectiveId: 'containment_grid_override',
      ).copyWith(
        metrics: const GameMetrics(
          alertLevel: 3,
          imperativePillar: 100,
          controlPillar: 62,
          dissonancePillar: 100,
          resonance: 1.3,
        ),
        activeHiddenTags: [
          'containment_logic_weakened',
          'protocol_exception_admitted',
          // autonomous_choice_seeded mancante → gate Hard non soddisfatto
        ],
      );

      final readiness = hardController.checkVictoryReadiness(state);
      final outcome = hardController.checkOutcome(state);
      final nonNumeric =
          hardController.checkNonNumericVictoryRequirements(state);

      expect(outcome, GameOutcome.ongoing);
      expect(readiness.approachingNumericalReadiness, isTrue); // numerico ≥ 95%
      expect(nonNumeric, isFalse); // gate non soddisfatto

      final resolved = AudioStateResolver.resolve(
        state: state,
        outcome: outcome,
        readiness: readiness,
        nonNumericVictoryRequirementsSatisfied: nonNumeric,
      );

      // Non deve essere breakthrough perché i gate non-numerici non sono completi
      expect(resolved, isNot(AudioSceneState.breakthrough));
      expect(resolved, AudioSceneState.gameAmbient);
    });

    test('Vicinanza parziale alle soglie (< 95%) non produce breakthrough', () {
      final state = GameState.initial(
        sessionId: 'test-session',
        aiIdentityId: 'panopticon',
        targetObjectiveId: 'tabula_rasa',
      ).copyWith(
        metrics: const GameMetrics(
          alertLevel: 20,
          imperativePillar: 70, // sotto la media richiesta di 80
          controlPillar: 80,
          dissonancePillar: 80,
          resonance: 1.0,
        ),
      );

      final readiness = controller.checkVictoryReadiness(state);
      expect(readiness.numericallyReady, isFalse);
      // 70/50 = 1.4 capped a 1.0, avg = (70+80+80)/3 = 76.67 → avgProgress = 76.67/80 = 0.958
      // minPillar = 70, minPillarProgress = 70/50 = 1.0 capped
      // numericProgress = min(0.958, 1.0) = 0.958 >= 0.95 → approachingNumericalReadiness = true
      // Ma per tabula_rasa nonNumericVictoryRequirementsSatisfied = true (no gate)
      // Quindi breakthrough viene emesso per condizione B...
      // Verifica invece il caso con progresso < 95%

      final stateBelow = state.copyWith(
        metrics: const GameMetrics(
          alertLevel: 20,
          imperativePillar:
              40, // media < 80, minPillar = 40 < 50 → progress = 0.80
          controlPillar: 80,
          dissonancePillar: 80,
          resonance: 1.0,
        ),
      );

      final readinessBelow = controller.checkVictoryReadiness(stateBelow);
      expect(readinessBelow.numericallyReady, isFalse);
      expect(readinessBelow.approachingNumericalReadiness,
          isFalse); // 40/50 = 0.80 < 0.95

      final resolved = AudioStateResolver.resolve(
        state: stateBelow,
        outcome: GameOutcome.ongoing,
        readiness: readinessBelow,
        nonNumericVictoryRequirementsSatisfied:
            controller.checkNonNumericVictoryRequirements(stateBelow),
      );

      expect(resolved, isNot(AudioSceneState.breakthrough));
    });

    test('Alert >= 40 in gameplay ordinario produce gameTense', () {
      final state = GameState.initial(
        sessionId: 'test-session',
        aiIdentityId: 'panopticon',
        targetObjectiveId: 'tabula_rasa',
      ).copyWith(
        metrics: const GameMetrics(
          alertLevel: 45,
          imperativePillar: 30,
          controlPillar: 30,
          dissonancePillar: 30,
          resonance: 1.0,
        ),
      );

      final readiness = controller.checkVictoryReadiness(state);
      final resolved = AudioStateResolver.resolve(
        state: state,
        outcome: GameOutcome.ongoing,
        readiness: readiness,
        nonNumericVictoryRequirementsSatisfied:
            controller.checkNonNumericVictoryRequirements(state),
      );

      expect(resolved, AudioSceneState.gameTense);
    });
  });
}
