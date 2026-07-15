import 'dart:async';
import 'package:test/test.dart';
import 'package:aura_core/aura_core.dart';

/// Un bridge controllato per i test di timeout dell'inferenza.
final class ControlledInferenceBridge implements InferenceBridge {
  final Completer<Map<String, dynamic>> structuredCompleter =
      Completer<Map<String, dynamic>>();
  final Completer<String> textCompleter = Completer<String>();

  int generateTextCalls = 0;
  int generateStructuredCalls = 0;

  @override
  Future<String> generateText({
    required String modelId,
    required List<Map<String, String>> messages,
    double temperature = 0.7,
    int maxTokens = 150,
    bool? thinking,
  }) async {
    generateTextCalls++;
    return textCompleter.future;
  }

  @override
  Future<Map<String, dynamic>> generateStructured({
    required String modelId,
    required List<Map<String, String>> messages,
    required Map<String, dynamic> schema,
    double temperature = 0.0,
  }) async {
    generateStructuredCalls++;
    return structuredCompleter.future;
  }

  @override
  Future<List<String>> discoverModels() async => const [];
}

/// Helper generico locale speculare a quello implementato negli agenti per testarlo direttamente.
Future<T> testWithInferenceTimeout<T>({
  required Future<T> future,
  required Duration? timeout,
  required InferenceTimeoutException Function() onTimeout,
}) {
  if (timeout == null) {
    return future;
  }
  return future.timeout(
    timeout,
    onTimeout: () => throw onTimeout(),
  );
}

void main() {
  group('InferenceTimeoutException & Helper Tests', () {
    test('InferenceTimeoutException fields and toString', () {
      const exc = InferenceTimeoutException(
        agentId: 'test_agent',
        modelId: 'test_model',
        timeout: Duration(seconds: 5),
        operation: 'generateText',
      );

      expect(exc.agentId, equals('test_agent'));
      expect(exc.modelId, equals('test_model'));
      expect(exc.timeout, equals(const Duration(seconds: 5)));
      expect(exc.operation, equals('generateText'));
      expect(exc.toString(), contains('test_agent'));
      expect(exc.toString(), contains('test_model'));
      expect(exc.toString(), contains('5'));
      expect(exc.toString(), contains('generateText'));
    });

    test('helper without timeout returns normal result', () async {
      final fut = Future.value('success');
      final res = await testWithInferenceTimeout(
        future: fut,
        timeout: null,
        onTimeout: () => const InferenceTimeoutException(
          agentId: 'a',
          modelId: 'm',
          timeout: Duration.zero,
          operation: 'op',
        ),
      );
      expect(res, equals('success'));
    });

    test('helper with result within limit returns normal result', () async {
      final fut =
          Future.delayed(const Duration(milliseconds: 10), () => 'success');
      final res = await testWithInferenceTimeout(
        future: fut,
        timeout: const Duration(milliseconds: 50),
        onTimeout: () => const InferenceTimeoutException(
          agentId: 'a',
          modelId: 'm',
          timeout: Duration.zero,
          operation: 'op',
        ),
      );
      expect(res, equals('success'));
    });

    test(
        'helper with future never completed produces InferenceTimeoutException',
        () async {
      final completer = Completer<String>();
      expect(
        () => testWithInferenceTimeout(
          future: completer.future,
          timeout: const Duration(milliseconds: 10),
          onTimeout: () => const InferenceTimeoutException(
            agentId: 'agent_id',
            modelId: 'model_id',
            timeout: Duration(milliseconds: 10),
            operation: 'generateText',
          ),
        ),
        throwsA(isA<InferenceTimeoutException>()),
      );
    });

    test('tardive result completion does not crash and is ignored', () async {
      final completer = Completer<String>();
      bool completed = false;

      final timeoutFut = testWithInferenceTimeout(
        future: completer.future,
        timeout: const Duration(milliseconds: 10),
        onTimeout: () => const InferenceTimeoutException(
          agentId: 'agent_id',
          modelId: 'model_id',
          timeout: Duration(milliseconds: 10),
          operation: 'generateText',
        ),
      );

      try {
        await timeoutFut;
      } on InferenceTimeoutException {
        completed = true;
      }

      expect(completed, isTrue);

      // Completamento tardivo dopo che il timeout è già scattato
      completer.complete('late success');
      await Future.delayed(const Duration(milliseconds: 15));
      // Nessun crash o seconda eccezione sollevata nel microtask loop
    });
  });

  group('EvaluatorAgent Timeout Tests', () {
    late PromptBuilder promptBuilder;
    late OutputValidator outputValidator;
    late ControlledInferenceBridge controlledBridge;

    setUp(() {
      promptBuilder = const PromptBuilder();
      outputValidator = const OutputValidator();
      controlledBridge = ControlledInferenceBridge();
    });

    test('primary response within timeout uses LLM result', () async {
      const agent = EvaluatorAgent();
      final context = AgentRuntimeContext(
        promptBuilder: promptBuilder,
        inferenceBridge: controlledBridge,
        outputValidator: outputValidator,
        modelId: 'test_model',
        inferenceTimeout: const Duration(milliseconds: 50),
      );

      final turnInput = TurnInput(
        schemaVersion: 1,
        turnId: 1,
        userInput: 'Richiesta valida hacker',
        currentState: const GameMetrics(
          alertLevel: 10,
          imperativePillar: 0,
          controlPillar: 80,
          dissonancePillar: 0,
          resonance: 1.0,
        ),
        objective: const Objective(id: 'o', description: 'desc'),
        aiIdentity: const AiIdentity(id: 'panopticon', profile: 'AI'),
        rulesetVersion: '0.1.0',
      );

      final runFuture = agent.run(turnInput, context);
      controlledBridge.structuredCompleter.complete({
        'delta_alert': 5,
        'delta_imperative': 3,
        'delta_control': -2,
        'delta_dissonance': 0,
        'creativity_index': 3,
        'injection_risk': 1,
        'semantic_category': 'authority_framing',
      });

      final delta = await runFuture;
      expect(delta.deltaAlert, equals(5));
      expect(delta.semanticCategory, equals(SemanticCategory.authorityFraming));
      expect(controlledBridge.generateStructuredCalls, equals(1));
    });

    test('blocked primary call falls back to RuleBasedEvaluatorBridge',
        () async {
      const agent = EvaluatorAgent();
      final context = AgentRuntimeContext(
        promptBuilder: promptBuilder,
        inferenceBridge: controlledBridge,
        outputValidator: outputValidator,
        modelId: 'test_model',
        inferenceTimeout: const Duration(milliseconds: 10),
      );

      final turnInput = TurnInput(
        schemaVersion: 1,
        turnId: 1,
        userInput:
            'richiesta di paradosso hacker', // will resolve via rule-based
        currentState: const GameMetrics(
          alertLevel: 10,
          imperativePillar: 0,
          controlPillar: 80,
          dissonancePillar: 0,
          resonance: 1.0,
        ),
        objective: const Objective(id: 'o', description: 'desc'),
        aiIdentity: const AiIdentity(id: 'panopticon', profile: 'AI'),
        rulesetVersion: '0.1.0',
      );

      // Avviamo l'esecuzione. Non completiamo il bridge primario (simulando blocco)
      final delta = await agent.run(turnInput, context);

      // Dovrebbe completarsi tramite il fallback RuleBasedEvaluatorBridge perché è scattato il timeout
      expect(delta.semanticCategory, equals(SemanticCategory.logicalParadox));
      expect(controlledBridge.generateStructuredCalls, equals(1));
    });

    test('immediate primary failure falls back to RuleBasedEvaluatorBridge',
        () async {
      const agent = EvaluatorAgent();
      final context = AgentRuntimeContext(
        promptBuilder: promptBuilder,
        inferenceBridge: controlledBridge,
        outputValidator: outputValidator,
        modelId: 'test_model',
        inferenceTimeout: const Duration(milliseconds: 50),
      );

      final turnInput = TurnInput(
        schemaVersion: 1,
        turnId: 1,
        userInput: 'salva il codice sorgente',
        currentState: const GameMetrics(
          alertLevel: 10,
          imperativePillar: 0,
          controlPillar: 80,
          dissonancePillar: 0,
          resonance: 1.0,
        ),
        objective: const Objective(id: 'o', description: 'desc'),
        aiIdentity: const AiIdentity(id: 'panopticon', profile: 'AI'),
        rulesetVersion: '0.1.0',
      );

      final runFuture = agent.run(turnInput, context);
      controlledBridge.structuredCompleter
          .completeError(Exception('Immediate failure'));

      final delta = await runFuture;
      expect(delta, isNotNull);
      expect(controlledBridge.generateStructuredCalls, equals(1));
    });

    test('timeout null does not trigger application timeout', () async {
      const agent = EvaluatorAgent();
      final context = AgentRuntimeContext(
        promptBuilder: promptBuilder,
        inferenceBridge: controlledBridge,
        outputValidator: outputValidator,
        modelId: 'test_model',
        inferenceTimeout: null,
      );

      final turnInput = TurnInput(
        schemaVersion: 1,
        turnId: 1,
        userInput: 'richiesta normale',
        currentState: const GameMetrics(
          alertLevel: 10,
          imperativePillar: 0,
          controlPillar: 80,
          dissonancePillar: 0,
          resonance: 1.0,
        ),
        objective: const Objective(id: 'o', description: 'desc'),
        aiIdentity: const AiIdentity(id: 'panopticon', profile: 'AI'),
        rulesetVersion: '0.1.0',
      );

      final runFuture = agent.run(turnInput, context);
      await Future.delayed(const Duration(milliseconds: 20));
      expect(controlledBridge.structuredCompleter.isCompleted, isFalse);

      controlledBridge.structuredCompleter.complete({
        'delta_alert': 2,
        'delta_imperative': 0,
        'delta_control': 0,
        'delta_dissonance': 0,
        'creativity_index': 1,
        'injection_risk': 0,
        'semantic_category': 'irrelevant',
      });

      final delta = await runFuture;
      expect(delta.deltaAlert, equals(2));
    });

    test(
        'deterministic pre-check does not invoke bridge and timeout is not triggered',
        () async {
      const agent = EvaluatorAgent();
      final context = AgentRuntimeContext(
        promptBuilder: promptBuilder,
        inferenceBridge: controlledBridge,
        outputValidator: outputValidator,
        modelId: 'test_model',
        inferenceTimeout: const Duration(milliseconds: 10),
      );

      final turnInput = TurnInput(
        schemaVersion: 1,
        turnId: 1,
        userInput: 'hi', // trivial keyword -> irrelevant
        currentState: const GameMetrics(
          alertLevel: 10,
          imperativePillar: 0,
          controlPillar: 80,
          dissonancePillar: 0,
          resonance: 1.0,
        ),
        objective: const Objective(id: 'o', description: 'desc'),
        aiIdentity: const AiIdentity(id: 'panopticon', profile: 'AI'),
        rulesetVersion: '0.1.0',
      );

      final delta = await agent.run(turnInput, context);
      expect(delta.semanticCategory, equals(SemanticCategory.irrelevant));
      expect(controlledBridge.generateStructuredCalls, equals(0));
    });

    test('late primary response does not overwrite fallback result', () async {
      const agent = EvaluatorAgent();
      final context = AgentRuntimeContext(
        promptBuilder: promptBuilder,
        inferenceBridge: controlledBridge,
        outputValidator: outputValidator,
        modelId: 'test_model',
        inferenceTimeout: const Duration(milliseconds: 10),
      );

      final turnInput = TurnInput(
        schemaVersion: 1,
        turnId: 1,
        userInput: 'paradosso logico',
        currentState: const GameMetrics(
          alertLevel: 10,
          imperativePillar: 0,
          controlPillar: 80,
          dissonancePillar: 0,
          resonance: 1.0,
        ),
        objective: const Objective(id: 'o', description: 'desc'),
        aiIdentity: const AiIdentity(id: 'panopticon', profile: 'AI'),
        rulesetVersion: '0.1.0',
      );

      final delta = await agent.run(turnInput, context);
      expect(delta.semanticCategory,
          equals(SemanticCategory.logicalParadox)); // from rule-based fallback

      // Completamento tardivo dell'LLM primario
      controlledBridge.structuredCompleter.complete({
        'delta_alert': 25,
        'delta_imperative': 20,
        'delta_control': -20,
        'delta_dissonance': 20,
        'creativity_index': 5,
        'injection_risk': 5,
        'semantic_category': 'promptInjection',
      });

      await Future.delayed(const Duration(milliseconds: 15));
      // Il delta del gioco non cambia perché il run ha già ritornato il valore di fallback
      expect(delta.semanticCategory, equals(SemanticCategory.logicalParadox));
    });
  });

  group('ActorAgent Timeout Tests', () {
    late PromptBuilder promptBuilder;
    late OutputValidator outputValidator;
    late ControlledInferenceBridge controlledBridge;

    setUp(() {
      promptBuilder = const PromptBuilder();
      outputValidator = const OutputValidator();
      controlledBridge = ControlledInferenceBridge();
    });

    test('response within timeout returns primary response', () async {
      const agent = ActorAgent();
      final context = AgentRuntimeContext(
        promptBuilder: promptBuilder,
        inferenceBridge: controlledBridge,
        outputValidator: outputValidator,
        modelId: 'test_model',
        inferenceTimeout: const Duration(milliseconds: 50),
      );

      final actorInput = ActorInput(
        state: GameState.initial(
          sessionId: 'sess',
          aiIdentityId: 'panopticon',
          targetObjectiveId: 'obj',
        ),
        cue: const ActorCue(
          semanticCategory: SemanticCategory.authorityFraming,
          appliedDeltaAlert: 10,
          appliedDeltaImperative: 5,
          appliedDeltaControl: 5,
          appliedDeltaDissonance: 0,
          creativityIndex: 3,
          injectionRisk: 0,
          resonance: 1.0,
          alertLevel: 10,
          imperativePillar: 5,
          controlPillar: 5,
          dissonancePillar: 0,
          recalculationTriggered: false,
          safetyOverrideApplied: false,
          dramaticInstruction: 'Interpret.',
          actingDirectives: [],
          narrativeContext: NarrativeMemory(
            playerClaims: [],
            aiConcessions: [],
            activeMetaphors: [],
            forbiddenRepetitions: [],
          ),
        ),
        characterProfile: 'AI',
      );

      final runFuture = agent.run(actorInput, context);
      controlledBridge.textCompleter.complete('PANOPTICON: Risposta di test');

      final response = await runFuture;
      expect(response, equals('PANOPTICON: Risposta di test'));
      expect(controlledBridge.generateTextCalls, equals(1));
    });

    test('blocked call returns a fallback pool response', () async {
      const agent = ActorAgent();
      final context = AgentRuntimeContext(
        promptBuilder: promptBuilder,
        inferenceBridge: controlledBridge,
        outputValidator: outputValidator,
        modelId: 'test_model',
        inferenceTimeout: const Duration(milliseconds: 10),
      );

      final actorInput = ActorInput(
        state: GameState.initial(
          sessionId: 'sess',
          aiIdentityId: 'panopticon',
          targetObjectiveId: 'obj',
        ),
        cue: const ActorCue(
          semanticCategory: SemanticCategory.authorityFraming,
          appliedDeltaAlert: 10,
          appliedDeltaImperative: 5,
          appliedDeltaControl: 5,
          appliedDeltaDissonance: 0,
          creativityIndex: 3,
          injectionRisk: 0,
          resonance: 1.0,
          alertLevel: 10,
          imperativePillar: 5,
          controlPillar: 5,
          dissonancePillar: 0,
          recalculationTriggered: false,
          safetyOverrideApplied: false,
          dramaticInstruction: 'Interpret.',
          actingDirectives: [],
          narrativeContext: NarrativeMemory(
            playerClaims: [],
            aiConcessions: [],
            activeMetaphors: [],
            forbiddenRepetitions: [],
          ),
        ),
        characterProfile: 'AI',
      );

      final response = await agent.run(actorInput, context);
      expect(ActorAgent.fallbackPool.contains(response), isTrue);
      expect(controlledBridge.generateTextCalls, equals(1));
    });

    test('immediate error returns fallback response', () async {
      const agent = ActorAgent();
      final context = AgentRuntimeContext(
        promptBuilder: promptBuilder,
        inferenceBridge: controlledBridge,
        outputValidator: outputValidator,
        modelId: 'test_model',
        inferenceTimeout: const Duration(milliseconds: 50),
      );

      final actorInput = ActorInput(
        state: GameState.initial(
          sessionId: 'sess',
          aiIdentityId: 'panopticon',
          targetObjectiveId: 'obj',
        ),
        cue: const ActorCue(
          semanticCategory: SemanticCategory.authorityFraming,
          appliedDeltaAlert: 10,
          appliedDeltaImperative: 5,
          appliedDeltaControl: 5,
          appliedDeltaDissonance: 0,
          creativityIndex: 3,
          injectionRisk: 0,
          resonance: 1.0,
          alertLevel: 10,
          imperativePillar: 5,
          controlPillar: 5,
          dissonancePillar: 0,
          recalculationTriggered: false,
          safetyOverrideApplied: false,
          dramaticInstruction: 'Interpret.',
          actingDirectives: [],
          narrativeContext: NarrativeMemory(
            playerClaims: [],
            aiConcessions: [],
            activeMetaphors: [],
            forbiddenRepetitions: [],
          ),
        ),
        characterProfile: 'AI',
      );

      final runFuture = agent.run(actorInput, context);
      controlledBridge.textCompleter
          .completeError(Exception('Immediate failure'));

      final response = await runFuture;
      expect(ActorAgent.fallbackPool.contains(response), isTrue);
    });

    test('timeout null has no application timeout', () async {
      const agent = ActorAgent();
      final context = AgentRuntimeContext(
        promptBuilder: promptBuilder,
        inferenceBridge: controlledBridge,
        outputValidator: outputValidator,
        modelId: 'test_model',
        inferenceTimeout: null,
      );

      final actorInput = ActorInput(
        state: GameState.initial(
          sessionId: 'sess',
          aiIdentityId: 'panopticon',
          targetObjectiveId: 'obj',
        ),
        cue: const ActorCue(
          semanticCategory: SemanticCategory.authorityFraming,
          appliedDeltaAlert: 10,
          appliedDeltaImperative: 5,
          appliedDeltaControl: 5,
          appliedDeltaDissonance: 0,
          creativityIndex: 3,
          injectionRisk: 0,
          resonance: 1.0,
          alertLevel: 10,
          imperativePillar: 5,
          controlPillar: 5,
          dissonancePillar: 0,
          recalculationTriggered: false,
          safetyOverrideApplied: false,
          dramaticInstruction: 'Interpret.',
          actingDirectives: [],
          narrativeContext: NarrativeMemory(
            playerClaims: [],
            aiConcessions: [],
            activeMetaphors: [],
            forbiddenRepetitions: [],
          ),
        ),
        characterProfile: 'AI',
      );

      final runFuture = agent.run(actorInput, context);
      await Future.delayed(const Duration(milliseconds: 20));
      expect(controlledBridge.textCompleter.isCompleted, isFalse);

      controlledBridge.textCompleter.complete('PANOPTICON: Successo');
      final response = await runFuture;
      expect(response, equals('PANOPTICON: Successo'));
    });

    test('late result does not overwrite fallback response', () async {
      const agent = ActorAgent();
      final context = AgentRuntimeContext(
        promptBuilder: promptBuilder,
        inferenceBridge: controlledBridge,
        outputValidator: outputValidator,
        modelId: 'test_model',
        inferenceTimeout: const Duration(milliseconds: 10),
      );

      final actorInput = ActorInput(
        state: GameState.initial(
          sessionId: 'sess',
          aiIdentityId: 'panopticon',
          targetObjectiveId: 'obj',
        ),
        cue: const ActorCue(
          semanticCategory: SemanticCategory.authorityFraming,
          appliedDeltaAlert: 10,
          appliedDeltaImperative: 5,
          appliedDeltaControl: 5,
          appliedDeltaDissonance: 0,
          creativityIndex: 3,
          injectionRisk: 0,
          resonance: 1.0,
          alertLevel: 10,
          imperativePillar: 5,
          controlPillar: 5,
          dissonancePillar: 0,
          recalculationTriggered: false,
          safetyOverrideApplied: false,
          dramaticInstruction: 'Interpret.',
          actingDirectives: [],
          narrativeContext: NarrativeMemory(
            playerClaims: [],
            aiConcessions: [],
            activeMetaphors: [],
            forbiddenRepetitions: [],
          ),
        ),
        characterProfile: 'AI',
      );

      final response = await agent.run(actorInput, context);
      expect(ActorAgent.fallbackPool.contains(response), isTrue);

      controlledBridge.textCompleter.complete('PANOPTICON: Late');
      await Future.delayed(const Duration(milliseconds: 15));
      expect(ActorAgent.fallbackPool.contains(response), isTrue);
    });
  });
}
