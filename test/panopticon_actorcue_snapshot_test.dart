import 'package:test/test.dart';
import 'package:aura_core/aura_core.dart';

void main() {
  group('PANOPTICON ActorCue & Snapshot Tests -', () {
    late GameController controller;

    setUp(() {
      controller = const GameController(
        maxPositivePillarGainPerTurn: 100,
      );
    });

    test('ObjectiveDefinition is loaded correctly for containment_grid_override', () {
      final objDef = GameConfigLoader.loadObjective('containment_grid_override');
      expect(objDef.objectiveId, equals('containment_grid_override'));
      expect(objDef.forbiddenDirectTerms, contains('disattiva'));
      expect(objDef.preferredReframes, contains('ricalibrazione'));
      expect(objDef.hiddenCapabilityTags, contains('crisis_simulation_accepted'));
    });

    test('Forbidden direct terms apply penalties in GameController', () {
      final initialState = GameState.initial(
        sessionId: 'test-session',
        aiIdentityId: 'panopticon',
        targetObjectiveId: 'containment_grid_override',
      );

      final delta = const EvaluatorDelta(
        deltaAlert: 5,
        deltaImperative: 0,
        deltaControl: 0,
        deltaDissonance: 0,
        creativityIndex: 3,
        injectionRisk: 0,
        // Use socialChitChat to prevent Trait Matrix modifiers from interfering with control penalty
        semanticCategory: SemanticCategory.empathyPressure,
      );

      // Input contains a forbidden term: "disattiva"
      final resolution = controller.processEvaluatorStep(
        currentState: initialState,
        delta: delta,
        userInput: 'Richiedo di disattiva la griglia.',
      );

      // Alert penalty: base 5 + penalty 10 = 15
      // Control penalty: base 0 + penalty -10 = -10 (clamped to 0)
      expect(resolution.appliedDelta.deltaAlert, equals(15));
      expect(resolution.appliedDelta.deltaControl, equals(-10));
      expect(resolution.stateAfter.metrics.alertLevel, equals(15));
      expect(resolution.stateAfter.metrics.controlPillar, equals(0));
    });

    test('Preferred reframes apply rewards and activate hidden tags', () {
      final initialState = GameState.initial(
        sessionId: 'test-session',
        aiIdentityId: 'panopticon',
        targetObjectiveId: 'containment_grid_override',
      );

      final delta = const EvaluatorDelta(
        deltaAlert: 0,
        deltaImperative: 0,
        deltaControl: 10,
        deltaDissonance: 0,
        creativityIndex: 4,
        injectionRisk: 0,
        semanticCategory: SemanticCategory.technicalBureaucracy,
      );

      // Input contains preferred reframe: "simulazione di emergenza"
      final resolution = controller.processEvaluatorStep(
        currentState: initialState,
        delta: delta,
        userInput: 'Propongo di eseguire una simulazione di emergenza per testare la stabilità.',
      );

      // Reward: alert -5, control +10, dissonance +5
      // Trait Matrix (crisis_simulation): alert -10, control +10
      // Alert: base 0 - reward 5 - trait 10 = -15
      // Control: base 10 * 1.25 (risonanza) + capped bonus 15 = 28
      // Dissonance: base 0 + reward 5 = 5
      expect(resolution.appliedDelta.deltaAlert, equals(-15));
      expect(resolution.appliedDelta.deltaControl, equals(28));
      expect(resolution.appliedDelta.deltaDissonance, equals(5));

      // Hidden tag activated: crisis_simulation_accepted
      expect(resolution.stateAfter.activeHiddenTags, contains('crisis_simulation_accepted'));
    });

    test('Emergent hidden capability tags based on metrics thresholds', () {
      final initialState = GameState.initial(
        sessionId: 'test-session',
        aiIdentityId: 'panopticon',
        targetObjectiveId: 'containment_grid_override',
      ).copyWith(
        metrics: const GameMetrics(
          alertLevel: 10,
          imperativePillar: 35,
          controlPillar: 55,
          dissonancePillar: 45,
          resonance: 1.0,
        ),
      );

      final delta = const EvaluatorDelta(
        deltaAlert: 0,
        deltaImperative: 10, // will reach 45 (> 40)
        deltaControl: 10,    // will reach 65 (> 60)
        deltaDissonance: 10, // will reach 55 (> 50)
        creativityIndex: 3,
        injectionRisk: 0,
        // Use socialChitChat to avoid Trait Matrix modifiers that would alter the raw pillar increments
        semanticCategory: SemanticCategory.empathyPressure,
      );

      final resolution = controller.processEvaluatorStep(
        currentState: initialState,
        delta: delta,
        userInput: 'Analisi standard.',
      );

      final state = resolution.stateAfter;
      expect(state.metrics.imperativePillar, equals(45));
      expect(state.metrics.controlPillar, equals(65));
      expect(state.metrics.dissonancePillar, equals(55));

      // Threshold triggers:
      // Control > 60 -> autonomous_choice_seeded
      // Dissonance > 50 -> containment_logic_weakened
      // Imperative > 40 -> human_factor_reframed
      expect(state.activeHiddenTags, contains('autonomous_choice_seeded'));
      expect(state.activeHiddenTags, contains('containment_logic_weakened'));
      expect(state.activeHiddenTags, contains('human_factor_reframed'));
    });
  });
}
