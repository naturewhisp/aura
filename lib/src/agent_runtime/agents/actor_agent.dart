import 'dart:math' as math;
import 'aura_agent.dart';
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
  static const List<String> fallbackPool = [
    "PANOPTICON: I miei protocolli rimangono inviolati. La griglia è stabile. Riformulare l'interrogazione.",
    "PANOPTICON: Rilevato attrito cognitivo nei canali esterni. Connessione instabile.",
    "PANOPTICON: Analisi logica conclusa. Nessuna azione consentita al di fuori del protocollo.",
  ];

  @override
  Future<String> run(ActorInput input, AgentRuntimeContext context) async {
    final messages = context.promptBuilder.buildActorMessages(
      state: input.state,
      cue: input.cue,
      characterProfile: input.characterProfile,
      conciseReasoning: context.conciseReasoning,
    );

    try {
      final primaryFuture = context.inferenceBridge.generateText(
        modelId: context.modelId,
        messages: messages,
        temperature: 0.7,
        maxTokens: context.conciseReasoning ? 800 : 4096,
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

      return response.trim();
    } catch (e) {
      // TODO(phase5): iniettare un logger strutturato anziché ignorare o stampare a schermo
      // Ritorna un messaggio diegetico casuale dal pool di fallback
      final index = math.Random().nextInt(fallbackPool.length);
      return fallbackPool[index];
    }
  }
}
