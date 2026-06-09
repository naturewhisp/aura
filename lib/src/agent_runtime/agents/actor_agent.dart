import 'dart:math' as math;
import 'aura_agent.dart';
import '../../models/game_state.dart';
import '../../models/actor_cue.dart';
import '../agent_card.dart';

/// Represents the input package sent to the Actor Agent (Version 2).
class ActorInput {
  final GameState state;
  final ActorCue cue;
  final String characterProfile;

  const ActorInput({
    required this.state,
    required this.cue,
    required this.characterProfile,
  });
}

/// Agent responsible for generating diegetic, character-aligned text responses.
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

  /// Default character pool used when inference fails.
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
      final response = await context.inferenceBridge.generateText(
        modelId: context.modelId,
        messages: messages,
        temperature: 0.7,
        maxTokens: context.conciseReasoning ? 800 : 4096,
        thinking: context.thinking,
      );
      
      return response.trim();
    } catch (e, stackTrace) {
      print("[ActorAgent ERROR] Error during inference: $e\n$stackTrace");
      // Return a random diegetic message from the fallback pool
      final index = math.Random().nextInt(fallbackPool.length);
      return fallbackPool[index];
    }
  }
}
