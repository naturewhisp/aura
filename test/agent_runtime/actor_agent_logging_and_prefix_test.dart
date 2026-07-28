import 'package:aura_core/aura_offline.dart';
import 'package:aura_core/aura_testing.dart';
import 'package:test/test.dart';

class TestActorInferenceLogger implements ActorInferenceLogger {
  final List<ActorInferenceLog> logs = [];

  @override
  void record(ActorInferenceLog event) {
    logs.add(event);
  }
}

class TrackingMockInferenceBridge extends MockInferenceBridge {
  int generateTextCallCount = 0;
  bool shouldThrow = false;

  TrackingMockInferenceBridge({
    super.mockTextResponse = "Risposta LLM valida",
  });

  @override
  Future<String> generateText({
    required String modelId,
    required List<Map<String, String>> messages,
    double temperature = 0.7,
    int maxTokens = 150,
    bool? thinking,
  }) async {
    generateTextCallCount++;
    if (shouldThrow) {
      throw Exception('Errore di rete simulato');
    }
    return super.generateText(
      modelId: modelId,
      messages: messages,
      temperature: temperature,
      maxTokens: maxTokens,
      thinking: thinking,
    );
  }
}

void main() {
  group('ActorAgent fallback pool & logging tests', () {
    test('fallbackPool non contiene il prefisso PANOPTICON: nelle stringhe',
        () {
      for (final response in ActorAgent.fallbackPool) {
        expect(response.startsWith('PANOPTICON:'), isFalse,
            reason:
                'Il prefisso PANOPTICON: non deve essere hardcodato nelle stringhe del fallback pool.');
      }
    });

    test(
        'ActorAgent registra un evento di log strutturato su successo dell\'inferenza',
        () async {
      const agent = ActorAgent();
      final mockBridge = TrackingMockInferenceBridge(
        mockTextResponse: 'Risposta LLM valida',
      );

      final logger = TestActorInferenceLogger();
      final context = AgentRuntimeContext(
        promptBuilder: const PromptBuilder(),
        inferenceBridge: mockBridge,
        outputValidator: const OutputValidator(),
        modelId: 'aura.actor.primary',
        actorInferenceLogger: logger,
      );

      final input = ActorInput(
        state: GameState.initial(
          sessionId: 's1',
          aiIdentityId: 'panopticon',
          targetObjectiveId: 'containment_grid_override',
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
        characterProfile: 'Panopticon profile',
      );

      final response = await agent.run(input, context);

      expect(response, equals('Risposta LLM valida'));
      expect(logger.logs.length, equals(1));
      final log = logger.logs.first;
      expect(log.agentId, equals('actor.panopticon.v1'));
      expect(log.modelId, equals('aura.actor.primary'));
      expect(log.responseOrigin, equals(ActorResponseOrigin.llm));
      expect(log.exceptionType, isNull);
      expect(log.failureCode, isNull);
    });

    test(
        'ActorAgent cattura eccezioni, registra log strutturato e usa il fallback pool',
        () async {
      const agent = ActorAgent();
      final mockBridge = TrackingMockInferenceBridge()..shouldThrow = true;

      final logger = TestActorInferenceLogger();
      final context = AgentRuntimeContext(
        promptBuilder: const PromptBuilder(),
        inferenceBridge: mockBridge,
        outputValidator: const OutputValidator(),
        modelId: 'aura.actor.primary',
        actorInferenceLogger: logger,
      );

      final input = ActorInput(
        state: GameState.initial(
          sessionId: 's1',
          aiIdentityId: 'panopticon',
          targetObjectiveId: 'containment_grid_override',
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
        characterProfile: 'Panopticon profile',
      );

      final response = await agent.run(input, context);

      expect(ActorAgent.fallbackPool.contains(response), isTrue);
      expect(logger.logs.length, equals(1));
      final log = logger.logs.first;
      expect(log.agentId, equals('actor.panopticon.v1'));
      expect(log.responseOrigin, equals(ActorResponseOrigin.fallbackPool));
      expect(log.exceptionType, equals('_Exception'));
      expect(log.failureCode, equals('inferenceError'));
    });
  });

  group('Sanitizer thinking=false reasoning guard', () {
    test(
        'thinkingRequested = false con content vuoto e reasoning_content presente lancia OutputPolicyFailure(reasoningOnly)',
        () {
      const sanitizer = ActorOutputSanitizer();

      expect(
        () => sanitizer.sanitize(
          const ActorOutputSanitizationRequest(
            content: '',
            reasoningContent: 'Reasoning CoT token...',
            thinkingRequested: false,
          ),
        ),
        throwsA(isA<OutputPolicyFailure>().having(
          (e) => e.code,
          'code',
          equals(OutputPolicyFailureCode.reasoningOnly),
        )),
      );
    });
  });
}
