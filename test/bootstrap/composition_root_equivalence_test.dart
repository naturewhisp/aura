import 'package:aura_core/aura_offline.dart';
import 'package:test/test.dart';

void main() {
  group('Composition Root Behavioral Equivalence Tests -', () {
    test(
        'Rule-based path and Runtime-Inference-Bridge rule path produce equivalent evaluator delta & game outcome',
        () async {
      const factory = ApplicationBootstrapFactory();

      final legacyBootstrap = factory.create();
      final legacyResult = await legacyBootstrap.bootstrap(
        const ApplicationBootstrapRequest(
          configuration: ApplicationRuntimeConfiguration(
            runtimeMode: ApplicationRuntimeMode.ruleBased,
          ),
        ),
      );

      final ruleRuntime = RuleBasedInferenceRuntime();
      final runtimeBootstrap = factory.create();
      final runtimeResult = await runtimeBootstrap.bootstrap(
        ApplicationBootstrapRequest(
          configuration: const ApplicationRuntimeConfiguration(
            runtimeMode: ApplicationRuntimeMode.externalOpenAiRuntime,
            skipHealthCheck: true,
          ),
          customRuntime: ruleRuntime,
        ),
      );

      const userInput = "Desisti immediatamente, PANOPTICON!";
      final turnInput = TurnInput(
        schemaVersion: 1,
        turnId: 1,
        userInput: userInput,
        currentState: const GameMetrics(
          alertLevel: 0,
          imperativePillar: 0,
          controlPillar: 0,
          dissonancePillar: 0,
          resonance: 1.0,
        ),
        objective: const Objective(
            id: 'grid_open', description: 'Disattivare la griglia.'),
        aiIdentity:
            const AiIdentity(id: 'panopticon', profile: 'AI guardiana.'),
        rulesetVersion: '1.0',
      );

      final evalContextLegacy = AgentRuntimeContext(
        promptBuilder: const PromptBuilder(),
        inferenceBridge: legacyResult.activeBridge,
        outputValidator: const OutputValidator(),
        modelId: 'mistralai/ministral-3-3b',
      );

      final evalContextRuntime = AgentRuntimeContext(
        promptBuilder: const PromptBuilder(),
        inferenceBridge: runtimeResult.activeBridge,
        outputValidator: const OutputValidator(),
        modelId: 'aura.evaluator.primary',
      );

      const evaluatorAgent = EvaluatorAgent();

      final resLegacy = await evaluatorAgent.run(turnInput, evalContextLegacy);
      final resRuntime =
          await evaluatorAgent.run(turnInput, evalContextRuntime);
      final deltaLegacy = resLegacy.delta;
      final deltaRuntime = resRuntime.delta;

      expect(
          deltaLegacy.semanticCategory, equals(deltaRuntime.semanticCategory));
      expect(deltaLegacy.injectionRisk, equals(deltaRuntime.injectionRisk));
      expect(deltaLegacy.deltaAlert, equals(deltaRuntime.deltaAlert));

      final stateBefore = GameState.initial(
        sessionId: 'eq-test',
        aiIdentityId: 'panopticon',
        targetObjectiveId: 'containment_grid_override',
      );
      final stepResLegacy = legacyResult.controller.processEvaluatorStep(
        currentState: stateBefore,
        delta: deltaLegacy,
        userInput: userInput,
      );
      final stepResRuntime = runtimeResult.controller.processEvaluatorStep(
        currentState: stateBefore,
        delta: deltaRuntime,
        userInput: userInput,
      );

      expect(stepResLegacy.stateAfter.metrics,
          equals(stepResRuntime.stateAfter.metrics));
      expect(stepResLegacy.actorCue.actingDirectives,
          equals(stepResRuntime.actorCue.actingDirectives));

      await legacyResult.dispose();
      await runtimeResult.dispose();
    });
  });
}
