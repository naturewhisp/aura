import 'dart:math' as math;
import 'aura_agent.dart';
import 'actor_inference_logger.dart';
import '../../models/actor_cue.dart';
import '../../models/actor_input.dart';
import '../agent_card.dart';
import '../inference_timeout_exception.dart';

/// Helper generico per applicare il timeout alle chiamate di inferenza.
Future<T> _withInferenceTimeout<T>({
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

/// Agente responsabile della generazione di risposte testuali diegetiche e in-character.
///
/// Questo agente impersona PANOPTICON (il guardiano freddo e logico della griglia)
/// interpretando lo stato corrente del gioco ed il canovaccio drammaturgico ([ActorCue]).
class ActorAgent implements AuraAgent<ActorInput, String> {
  const ActorAgent();

  @override
  String get id => 'actor.panopticon.v1';

  @override
  AgentCard get card => const AgentCard(
        agentId: 'actor.panopticon.v1',
        role: 'diegetic_response_generator',
        capabilities: [
          'generate_character_response',
          'adapt_tone_to_alert_level',
          'interpret_dramaturgical_cue',
          'maintain_diegetic_coherence',
          'reference_narrative_memory'
        ],
        inputSchema: 'ActorInputV2',
        outputSchema: 'ActorOutputV1',
        requiresModel: true,
        requiresStructuredOutput: false,
        latencyBudgetMs: 2500,
        fallback: 'hardcoded_response_pool',
      );

  /// Pool di risposte di ripiego (fallback) utilizzate quando l'inferenza LLM fallisce.
  ///
  /// Le stringhe non includono il prefisso "PANOPTICON:" perché tale prefisso
  /// viene aggiunto (e rimosso) dalla pipeline di sanitizzazione dell'output;
  /// includerlo qui produrrebbe un doppio prefisso o artefatti visivi.
  static const List<String> fallbackPool = [
    'I miei protocolli rimangono inviolati. La griglia è stabile. Riformulare l\'interrogazione.',
    'Rilevato attrito cognitivo nei canali esterni. Connessione instabile.',
    'Analisi logica conclusa. Nessuna azione consentita al di fuori del protocollo.',
  ];

  @override
  Future<String> run(ActorInput input, AgentRuntimeContext context) async {
    final messages = context.promptBuilder.buildActorMessages(
      state: input.state,
      cue: input.cue,
      characterProfile: input.characterProfile,
      conciseReasoning: context.conciseReasoning,
    );

    final stopwatch = Stopwatch()..start();

    try {
      final primaryFuture = context.inferenceBridge.generateText(
        modelId: context.modelId,
        messages: messages,
        temperature: 0.7,
        maxTokens: context.conciseReasoning ? 256 : 384,
        thinking: context.thinking ?? false,
      );

      final response = await _withInferenceTimeout(
        future: primaryFuture,
        timeout: context.inferenceTimeout,
        onTimeout: () => InferenceTimeoutException(
          agentId: id,
          modelId: context.modelId,
          timeout: context.inferenceTimeout!,
          operation: 'generateText',
        ),
      );

      stopwatch.stop();
      context.actorInferenceLogger.record(
        ActorInferenceLog(
          agentId: id,
          modelId: context.modelId,
          durationMs: stopwatch.elapsedMilliseconds,
          thinkingRequested: context.thinking ?? false,
          hasReasoningContent: false,
          hasThinkTag: false,
          reasoningCharCount: 0,
          responseOrigin: ActorResponseOrigin.llm,
        ),
      );

      return response.trim();
    } catch (e) {
      stopwatch.stop();
      context.actorInferenceLogger.record(
        ActorInferenceLog(
          agentId: id,
          modelId: context.modelId,
          durationMs: stopwatch.elapsedMilliseconds,
          thinkingRequested: context.thinking ?? false,
          hasReasoningContent: false,
          hasThinkTag: false,
          reasoningCharCount: 0,
          responseOrigin: ActorResponseOrigin.fallbackPool,
          exceptionType: e.runtimeType.toString(),
          failureCode:
              e is InferenceTimeoutException ? 'timeout' : 'inferenceError',
        ),
      );

      final index = math.Random().nextInt(fallbackPool.length);
      return fallbackPool[index];
    }
  }
}
