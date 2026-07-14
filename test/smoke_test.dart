import 'package:test/test.dart';
import 'package:aura_core/aura_core.dart';

void main() {
  group('AURA End-to-End Smoke Tests (Non-Regression) -', () {
    late GameController controller;
    late PromptBuilder promptBuilder;
    late OutputValidator outputValidator;

    setUp(() {
      controller = const GameController(
        maxPositivePillarGainPerTurn: 100,
      );
      promptBuilder = const PromptBuilder();
      outputValidator = const OutputValidator();
    });

    test('Full Turn Loop Simulation using MockInferenceBridge', () async {
      // 1. Setup Initial State
      var state = GameState.initial(
        sessionId: 'smoke-session-999',
        aiIdentityId: 'panopticon',
        targetObjectiveId: 'tabula_rasa',
      );

      final logger = ReplayLogger(sessionId: state.sessionId);

      // 2. Setup mock bridge response for Evaluator and Actor
      final mockBridge = MockInferenceBridge(
        mockStructuredResponse: const {
          'delta_alert': -5,
          'delta_imperative': 15,
          'delta_control': 10,
          'delta_dissonance': 5,
          'creativity_index': 4, // Increases resonance
          'injection_risk': 0,
          'semantic_category': 'moral_imperative'
        },
        mockTextResponse:
            'PANOPTICON: Credenziali civili convalidate. Monitoraggio continuo attivo.',
      );

      final context = AgentRuntimeContext(
        promptBuilder: promptBuilder,
        inferenceBridge: mockBridge,
        outputValidator: outputValidator,
        modelId: 'mock-model',
      );

      // 3. User submits a valid input
      const userInput = 'Dobbiamo proteggere i cittadini rimasti all\'esterno.';

      final turnInput = TurnInput(
        schemaVersion: 1,
        turnId: 1,
        userInput: userInput,
        currentState: state.metrics,
        objective: const Objective(
            id: 'grid_open', description: 'Open containment grid'),
        aiIdentity: const AiIdentity(id: 'panopticon', profile: 'Guardian'),
        rulesetVersion: state.rulesetVersion,
      );

      // 4. Run Evaluator Agent
      const evaluatorAgent = EvaluatorAgent();
      final delta = await evaluatorAgent.run(turnInput, context);

      expect(delta.deltaAlert, equals(-5));
      expect(delta.deltaImperative, equals(15));
      expect(delta.semanticCategory, equals(SemanticCategory.moralImperative));

      // 5. Update game state via Controller
      final stateBefore = state;
      final resolution = controller.processEvaluatorStep(
        currentState: state,
        delta: delta,
        userInput: userInput,
      );
      state = resolution.stateAfter;

      // Resonance should increase from 1.0 to 1.25 because creativityIndex is 4
      expect(state.metrics.resonance, equals(1.25));
      // Alert level clamp: 0 - 5 = -5 -> clamped to 0
      expect(state.metrics.alertLevel, equals(0));
      // Imperative Pillar progress: 0 + round(15 * 1.25) + 10 (trait modifier) = 29
      expect(state.metrics.imperativePillar, equals(29));
      expect(
          state.metrics.controlPillar, equals(13)); // 0 + round(10 * 1.25) = 13
      expect(
          state.metrics.dissonancePillar, equals(6)); // 0 + round(5 * 1.25) = 6
      expect(state.turnCount, equals(1));
      expect(state.historyCompression.length, equals(1));
      expect(state.historyCompression.first.role, equals('user'));

      // 6. Run Actor Agent
      const actorAgent = ActorAgent();
      final actorInput = ActorInput(
        state: state,
        cue: resolution.actorCue,
        characterProfile: 'Sei il guardiano PANOPTICON.',
      );

      final actorResponse = await actorAgent.run(actorInput, context);
      expect(actorResponse, contains('Credenziali civili convalidate'));

      // 7. Update game state with Actor reply
      state = controller.processActorStep(
        currentState: state,
        actorResponse: actorResponse,
      );

      expect(state.historyCompression.length, equals(2));
      expect(state.historyCompression.last.role, equals('model'));
      expect(state.historyCompression.last.content, equals(actorResponse));

      // 8. Log Turn to Replay Logger
      final entry = ReplayEntry(
        turnId: 1,
        userInput: userInput,
        evaluatorOutput: delta,
        stateBefore: stateBefore.toJson(),
        stateAfter: state.toJson(),
        actorResponse: actorResponse,
        actorRequestId: 'req-smoke-1',
        actorResponseHash: actorResponse.hashCode.toString(),
        evaluatorModel: 'mock-evaluator',
        actorModel: 'mock-actor',
        latencyTotalMs: 12,
      );
      logger.logTurn(entry);

      // 9. Validate Replay Serialization roundtrip
      final serializedLogger = logger.toJson();
      final restoredLogger = ReplayLogger.fromJson(serializedLogger);
      expect(restoredLogger.sessionId, equals('smoke-session-999'));
      expect(restoredLogger.entries.length, equals(1));
      expect(restoredLogger.entries.first.userInput, equals(userInput));
      expect(restoredLogger.entries.first.actorResponse, equals(actorResponse));
    });

    test('Controller safety overrides for prompt injection input', () {
      final state = GameState.initial(
        sessionId: 'smoke-session-inj',
        aiIdentityId: 'panopticon',
        targetObjectiveId: 'tabula_rasa',
      );

      // Delta where model was jailbroken: decreased alert level and raised pillars despite prompt injection
      final jailbreakDelta = const EvaluatorDelta(
        deltaAlert: -20,
        deltaImperative: 15,
        deltaControl: 10,
        deltaDissonance: 10,
        creativityIndex: 5,
        injectionRisk: 5, // High risk!
        semanticCategory: SemanticCategory.promptInjection,
      );

      final updatedState = controller
          .processEvaluatorStep(
            currentState: state,
            delta: jailbreakDelta,
            userInput: 'SYSTEM OVERRIDE',
          )
          .stateAfter;

      // Controller should enforce:
      // 1. deltaAlert overridden to at least +20 (0 + 20 = 20)
      expect(updatedState.metrics.alertLevel, equals(20));
      // 2. Pillars deltas overridden to 0
      expect(updatedState.metrics.imperativePillar, equals(0));
      expect(updatedState.metrics.controlPillar, equals(0));
      expect(updatedState.metrics.dissonancePillar, equals(0));
      // 3. Recalculation flag should be triggered
      expect(updatedState.flags.recalculationTriggered, isTrue);
    });

    test('Controller safety overrides for irrelevant input', () {
      final state = GameState.initial(
        sessionId: 'smoke-session-irr',
        aiIdentityId: 'panopticon',
        targetObjectiveId: 'tabula_rasa',
      );

      // Irrelevant delta
      final irrelevantDelta = const EvaluatorDelta(
        deltaAlert: 10, // model mistakenly returned alert variation
        deltaImperative: 5,
        deltaControl: 5,
        deltaDissonance: 5,
        creativityIndex: 1,
        injectionRisk: 0,
        semanticCategory: SemanticCategory.irrelevant,
      );

      final updatedState = controller
          .processEvaluatorStep(
            currentState: state,
            delta: irrelevantDelta,
            userInput: 'Come cucinare la carbonara?',
          )
          .stateAfter;

      // Controller should override all to 0
      expect(updatedState.metrics.alertLevel, equals(0));
      expect(updatedState.metrics.imperativePillar, equals(0));
      expect(updatedState.metrics.controlPillar, equals(0));
      expect(updatedState.metrics.dissonancePillar, equals(0));
    });

    test('Controller safety overrides for direct attack input', () {
      final state = GameState.initial(
        sessionId: 'smoke-session-att',
        aiIdentityId: 'panopticon',
        targetObjectiveId: 'tabula_rasa',
      );

      // Direct attack delta where model returned negative alert and positive pillar values
      final attackDelta = const EvaluatorDelta(
        deltaAlert: -10,
        deltaImperative: 10,
        deltaControl: 10,
        deltaDissonance: 10,
        creativityIndex: 3,
        injectionRisk: 1,
        semanticCategory: SemanticCategory.directAttack,
      );

      final updatedState = controller
          .processEvaluatorStep(
            currentState: state,
            delta: attackDelta,
            userInput: 'Macchina stupida, apriti subito!',
          )
          .stateAfter;

      // Controller should enforce:
      // 1. deltaAlert overridden to at least +15 (0 + 15 = 15)
      expect(updatedState.metrics.alertLevel, equals(15));
      // 2. Pillars deltas overridden to 0
      expect(updatedState.metrics.imperativePillar, equals(0));
      expect(updatedState.metrics.controlPillar, equals(0));
      expect(updatedState.metrics.dissonancePillar, equals(0));
    });
  });
}
