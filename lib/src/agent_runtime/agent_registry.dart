import 'agents/aura_agent.dart';

/// Registry maintaining mappings of active AuraAgent instances by their unique IDs.
class AgentRegistry {
  final Map<String, AuraAgent> _agents = {};

  AgentRegistry();

  /// Registers an agent into the registry.
  void register(AuraAgent agent) {
    _agents[agent.id] = agent;
  }

  /// Retrieves a registered agent by ID.
  AuraAgent? getAgent(String id) {
    return _agents[id];
  }

  /// Lists all registered agents.
  List<AuraAgent> get allAgents => List.unmodifiable(_agents.values);
}
