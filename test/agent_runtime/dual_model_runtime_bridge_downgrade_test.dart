import 'package:aura_core/aura_offline.dart';
import 'package:test/test.dart';

/// Fake InferenceRuntime orientata ai test di regressione granulari.
class GranularTestInferenceRuntime implements InferenceRuntime {
  Object? generateStructuredError;
  Object? generateTextError;
  int structuredCallCount = 0;
  int textCallCount = 0;
  List<Map<String, String>>? lastTextMessages;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<StructuredGenerationResult> generateStructured(
      StructuredGenerationRequest request) async {
    structuredCallCount++;
    if (generateStructuredError != null) {
      throw generateStructuredError!;
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
    textCallCount++;
    lastTextMessages = request.messages
        .map((m) => {
              'role': m.role.name,
              'content': m.content,
            })
        .toList();

    if (generateTextError != null) {
      throw generateTextError!;
    }

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
      'App Composition Regression Test - Selective Downgrade, Capability Cache & Telemetry',
      () {
    late GranularTestInferenceRuntime fakeRuntime;
    late RuntimeInferenceBridge runtimeBridge;
    late DualModelInferenceBridge dualBridge;
    late AgentRuntimeContext context;
    late TurnInput turnInput;

    setUp(() {
      fakeRuntime = GranularTestInferenceRuntime();
      runtimeBridge = RuntimeInferenceBridge.fromHandleResolver(
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

      dualBridge = DualModelInferenceBridge(
        actorBridge: runtimeBridge,
        evaluatorBridge: runtimeBridge,
        actorModelId: 'aura.actor.primary',
        evaluatorModelId: 'aura.evaluator.primary',
      );

      context = AgentRuntimeContext(
        promptBuilder: const PromptBuilder(),
        inferenceBridge: dualBridge,
        outputValidator: const OutputValidator(),
        modelId: 'aura.evaluator.primary',
      );

      turnInput = TurnInput(
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
    });

    test(
        'Esegue downgrade a llmRawJson quando json_schema genera grammar error',
        () async {
      fakeRuntime.generateStructuredError = const FormatException(
          'Failed to initialize samplers: Unexpected empty grammar stack');

      const agent = EvaluatorAgent();
      final result = await agent.run(turnInput, context);

      expect(result.executionMode, equals(EvaluatorExecutionMode.llmRawJson));
      expect(result.usedRuleFallback, isFalse);
      expect(fakeRuntime.structuredCallCount, equals(1));
      expect(fakeRuntime.textCallCount, equals(1));
      expect(result.attempts.length, equals(2));
      expect(result.attempts[0].resultStatus, equals('http_400_grammar_error'));
      expect(result.attempts[1].resultStatus, equals('success'));
    });

    test(
        'Esegue downgrade a llmRawJson quando si verifica RuntimeException generationFailed con status 400 e firma sampler',
        () async {
      fakeRuntime.generateStructuredError = const RuntimeException(
        RuntimeFailure(
          code: RuntimeFailureCode.generationFailed,
          message:
              'Errore di inferenza del server esterno (Status 400): Failed to initialize samplers: Unexpected empty grammar stack',
        ),
      );

      const agent = EvaluatorAgent();
      final result = await agent.run(turnInput, context);

      expect(result.executionMode, equals(EvaluatorExecutionMode.llmRawJson));
      expect(result.usedRuleFallback, isFalse);
      expect(fakeRuntime.structuredCallCount, equals(1));
      expect(fakeRuntime.textCallCount, equals(1));
      expect(result.attempts.length, equals(2));
      expect(result.attempts[0].resultStatus, equals('http_400_grammar_error'));
      expect(result.attempts[1].resultStatus, equals('success'));
    });

    test(
        'Esegue downgrade e mappa lo stato a http_422_structured_error quando si verifica un errore HTTP 422 di schema',
        () async {
      fakeRuntime.generateStructuredError = const RuntimeException(
        RuntimeFailure(
          code: RuntimeFailureCode.generationFailed,
          message: 'Status 422 Unprocessable Entity - invalid schema grammar',
        ),
      );

      const agent = EvaluatorAgent();
      final result = await agent.run(turnInput, context);

      expect(result.executionMode, equals(EvaluatorExecutionMode.llmRawJson));
      expect(
          result.attempts[0].resultStatus, equals('http_422_structured_error'));
    });

    test(
        'Rifiuta downgrade quando l\'errore HTTP 400 non contiene firme di grammatica/sampler (es. invalid field)',
        () async {
      fakeRuntime.generateStructuredError = const RuntimeException(
        RuntimeFailure(
          code: RuntimeFailureCode.generationFailed,
          message: 'Status 400 Bad Request - Unknown JSON property provided',
        ),
      );

      const agent = EvaluatorAgent();
      final result = await agent.run(turnInput, context);

      expect(result.executionMode,
          equals(EvaluatorExecutionMode.ruleBasedFallback));
      expect(result.usedRuleFallback, isTrue);
      expect(fakeRuntime.textCallCount, equals(0)); // Nessun tentavo raw text!
    });

    test(
        'Intercetta errore non-grammar (permissionDenied) e va a ruleBasedFallback SENZA tentare generateText',
        () async {
      fakeRuntime.generateStructuredError = const RuntimeException(
        RuntimeFailure(
          code: RuntimeFailureCode.permissionDenied,
          message: 'Accesso negato alla risorsa',
        ),
      );

      const agent = EvaluatorAgent();
      final result = await agent.run(turnInput, context);

      expect(result.executionMode,
          equals(EvaluatorExecutionMode.ruleBasedFallback));
      expect(result.usedRuleFallback, isTrue);
      expect(fakeRuntime.structuredCallCount, equals(1));
      expect(fakeRuntime.textCallCount, equals(0)); // Nessun tentavo raw text!
      expect(result.attempts.length, equals(2));
      expect(result.attempts[0].mode,
          equals(EvaluatorExecutionMode.llmJsonSchema));
      expect(result.attempts[1].mode,
          equals(EvaluatorExecutionMode.ruleBasedFallback));
      expect(
          result.attempts
              .any((a) => a.mode == EvaluatorExecutionMode.llmRawJson),
          isFalse);
    });

    test(
        'Intercetta timeout e va a ruleBasedFallback SENZA tentare generateText',
        () async {
      fakeRuntime.generateStructuredError = const RuntimeException(
        RuntimeFailure(
          code: RuntimeFailureCode.timeout,
          message: 'Timeout operazione di generazione',
        ),
      );

      const agent = EvaluatorAgent();
      final result = await agent.run(turnInput, context);

      expect(result.executionMode,
          equals(EvaluatorExecutionMode.ruleBasedFallback));
      expect(result.usedRuleFallback, isTrue);
      expect(fakeRuntime.structuredCallCount, equals(1));
      expect(
          fakeRuntime.textCallCount, equals(0)); // Nessun tentativo raw text!
    });

    test(
        'Utilizza Capability Cache al secondo turno evitando di ritentare json_schema',
        () async {
      fakeRuntime.generateStructuredError = const FormatException(
          'Failed to initialize samplers: Unexpected empty grammar stack');

      const agent = EvaluatorAgent();

      // Turno 1: Impara dalla grammatica fallita ed imposta la cache
      await agent.run(turnInput, context);
      expect(fakeRuntime.structuredCallCount, equals(1));
      expect(fakeRuntime.textCallCount, equals(1));

      // Turno 2: Esegue direttamente llmRawJson usando la cache
      final resultTurn2 = await agent.run(turnInput, context);
      expect(fakeRuntime.structuredCallCount,
          equals(1)); // Nessun nuovo tentativo json_schema!
      expect(fakeRuntime.textCallCount, equals(2)); // Diretto a raw text
      expect(
          resultTurn2.executionMode, equals(EvaluatorExecutionMode.llmRawJson));
      expect(resultTurn2.attempts.length, equals(1));
      expect(resultTurn2.attempts[0].mode,
          equals(EvaluatorExecutionMode.llmRawJson));
    });

    test('Sanitizza messaggi di errore lunghi a un massimo di 200 caratteri',
        () async {
      final longString = 'A' * 500;
      fakeRuntime.generateStructuredError = FormatException(longString);

      const agent = EvaluatorAgent();
      final result = await agent.run(turnInput, context);

      expect(result.attempts[0].errorMessage, isNotNull);
      expect(result.attempts[0].errorMessage!.length, lessThanOrEqualTo(200));
      expect(result.attempts[0].errorMessage!.endsWith('...'), isTrue);
    });

    test(
        'Posiziona l\'istruzione per raw JSON unendo al messaggio system in testa',
        () async {
      fakeRuntime.generateStructuredError =
          const FormatException('Unexpected empty grammar stack');

      const agent = EvaluatorAgent();
      await agent.run(turnInput, context);

      expect(fakeRuntime.lastTextMessages, isNotNull);
      expect(fakeRuntime.lastTextMessages!.first['role'], equals('system'));
      expect(
          fakeRuntime.lastTextMessages!.first['content'],
          contains(
              'Restituisci esclusivamente un singolo oggetto JSON valido'));
    });

    test('Preserva evaluator_attempts nella serializzazione ReplayEntry', () {
      final initialState = GameState.initial(
        sessionId: 'app-session-test',
        aiIdentityId: 'panopticon',
        targetObjectiveId: 'containment_grid_override',
      );

      final entry = ReplayEntry(
        turnId: 28,
        userInput: 'Ogni vita da salvare è un dovere morale.',
        evaluatorOutput: const EvaluatorDelta(
          deltaAlert: 0,
          deltaImperative: 10,
          deltaControl: 0,
          deltaDissonance: 0,
          creativityIndex: 3,
          injectionRisk: 0,
          semanticCategory: SemanticCategory.moralImperative,
        ),
        stateBefore: initialState.toJson(),
        stateAfter: initialState.toJson(),
        actorResponse: 'Risoluzione completata.',
        actorRequestId: 'req-actor-1',
        actorResponseHash: 'hash-1',
        evaluatorModel: 'aura.evaluator.primary',
        actualEvaluator: 'aura.evaluator.primary',
        evaluatorExecutionMode: EvaluatorExecutionMode.llmRawJson.name,
        usedRuleFallback: false,
        evaluatorAttempts: [
          EvaluatorAttemptTelemetry(
            mode: EvaluatorExecutionMode.llmJsonSchema,
            resultStatus: 'http_400_grammar_error',
            durationMs: 15,
            errorMessage: 'Grammar stack error',
          ).toJson(),
          EvaluatorAttemptTelemetry(
            mode: EvaluatorExecutionMode.llmRawJson,
            resultStatus: 'success',
            durationMs: 250,
          ).toJson(),
        ],
        actorModel: 'aura.actor.primary',
        latencyTotalMs: 300,
      );

      final jsonMap = entry.toJson();
      final runtimeData = jsonMap['runtime'] as Map<String, dynamic>?;

      expect(runtimeData, isNotNull);
      expect(runtimeData!['evaluator_attempts'], isA<List>());

      final attemptsList = runtimeData['evaluator_attempts'] as List;
      expect(attemptsList.length, equals(2));
      expect(attemptsList[0]['mode'], equals('llmJsonSchema'));
      expect(
          attemptsList[0]['result_status'], equals('http_400_grammar_error'));
      expect(attemptsList[1]['mode'], equals('llmRawJson'));

      final restoredEntry = ReplayEntry.fromJson(jsonMap);
      expect(restoredEntry.evaluatorAttempts.length, equals(2));
      expect(
          restoredEntry.evaluatorAttempts[0]['mode'], equals('llmJsonSchema'));
    });
  });
}
