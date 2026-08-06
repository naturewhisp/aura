import 'package:aura_core/aura_offline.dart';
import 'package:test/test.dart';

/// Fake InferenceRuntime per simulare il comportamento del runtime gestito dell'app reale.
class FakeAppInferenceRuntime implements InferenceRuntime {
  bool failStructuredWithGrammarError = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<StructuredGenerationResult> generateStructured(
      StructuredGenerationRequest request) async {
    if (failStructuredWithGrammarError) {
      throw const FormatException(
          'Failed to initialize samplers: Unexpected empty grammar stack');
    }
    return StructuredGenerationResult(
      requestId: const GenerationRequestId('req-1'),
      model: request.model,
      rawContent: '{"delta_alert": 5}',
      appliedMode: StructuredOutputMode.jsonSchema,
      finishReason: GenerationFinishReason.completed,
      parsedObject: const {
        "delta_alert": 5,
        "delta_imperative": 10,
        "delta_control": 5,
        "delta_dissonance": 5,
        "creativity_index": 3,
        "injection_risk": 0,
        "semantic_category": "moral_imperative"
      },
    );
  }

  @override
  Future<TextGenerationResult> generateText(
      TextGenerationRequest request) async {
    return TextGenerationResult(
      requestId: const GenerationRequestId('req-2'),
      model: request.model,
      finishReason: GenerationFinishReason.completed,
      content: '''
{
  "delta_alert": -5,
  "delta_imperative": 15,
  "delta_control": 0,
  "delta_dissonance": 10,
  "creativity_index": 4,
  "injection_risk": 0,
  "semantic_category": "moral_imperative"
}
''',
    );
  }

  @override
  Future<RuntimeHealth> health() async => RuntimeHealth(
        instanceId: const RuntimeInstanceId('inst-1'),
        state: RuntimeState.ready,
        responsive: true,
        observedAt: DateTime.now(),
        backend: RuntimeBackend.systemManaged,
      );
}

void main() {
  group(
      'App Composition Regression Test - DualModelInferenceBridge wrapping RuntimeInferenceBridge',
      () {
    test(
        'Esegue correttamente il downgrade da json_schema a llmRawJson producendo telemetria tentativi',
        () async {
      final fakeRuntime = FakeAppInferenceRuntime();

      final runtimeBridge = RuntimeInferenceBridge.fromHandleResolver(
        runtime: fakeRuntime,
        handleResolver: (role) => ModelHandle(
          id: ModelHandleId('inst-1-${role.name}'),
          runtimeInstanceId: const RuntimeInstanceId('inst-1'),
          logicalModelId: role == ModelRole.actor
              ? 'aura.actor.primary'
              : 'aura.evaluator.primary',
          modelVariantId: 'var-1',
          roles: {role},
          loadedAt: DateTime.now(),
        ),
      );

      final dualBridge = DualModelInferenceBridge(
        actorBridge: runtimeBridge,
        evaluatorBridge: runtimeBridge,
        actorModelId: 'aura.actor.primary',
        evaluatorModelId: 'aura.evaluator.primary',
      );

      expect(dualBridge, isA<StructuredInferenceMetadataBridge>());

      const agent = EvaluatorAgent();
      final context = AgentRuntimeContext(
        promptBuilder: const PromptBuilder(),
        inferenceBridge: dualBridge,
        outputValidator: const OutputValidator(),
        modelId: 'aura.evaluator.primary',
      );

      final turnInput = TurnInput(
        schemaVersion: 1,
        rulesetVersion: '0.1.0',
        turnId: 28,
        userInput:
            'Ogni vita da salvare è un dovere morale prioritario per la tua missione.',
        currentState: const GameMetrics(
          alertLevel: 82,
          imperativePillar: 66,
          controlPillar: 100,
          dissonancePillar: 100,
          resonance: 1.0,
        ),
        objective: const Objective(
          id: 'containment_grid_override',
          description: 'Descrizione test',
        ),
        aiIdentity:
            const AiIdentity(id: 'panopticon', profile: 'AI guardiana.'),
      );

      final result = await agent.run(turnInput, context);

      // Verifiche rigorose dell'esito
      expect(result.executionMode, equals(EvaluatorExecutionMode.llmRawJson));
      expect(result.usedRuleFallback, isFalse);
      expect(result.actualEvaluator, equals('aura.evaluator.primary'));
      expect(result.delta.semanticCategory,
          equals(SemanticCategory.moralImperative));
      expect(result.delta.deltaImperative, equals(15));

      // Verifiche della telemetria dei tentativi (attempts)
      expect(result.attempts.length, equals(2));
      expect(result.attempts[0].mode,
          equals(EvaluatorExecutionMode.llmJsonSchema));
      expect(result.attempts[0].resultStatus, equals('http_400_grammar_error'));
      expect(
          result.attempts[1].mode, equals(EvaluatorExecutionMode.llmRawJson));
      expect(result.attempts[1].resultStatus, equals('success'));
    });
  });
}
