import 'agents/aura_agent.dart';

/// Registro che mantiene la mappatura delle istanze attive di [AuraAgent] tramite il loro ID univoco.
class AgentRegistry {
  final Map<String, AuraAgent> _agents = {};

  AgentRegistry();

  /// Registra un agente nel registro.
  void register(AuraAgent agent) {
    _agents[agent.id] = agent;
  }

  /// Recupera un agente registrato tramite il suo [id].
  ///
  /// Ritorna `null` se nessun agente con quell'ID è presente nel registro.
  AuraAgent? getAgent(String id) {
    return _agents[id];
  }

  /// Restituisce la lista di tutti gli agenti registrati.
  List<AuraAgent> get allAgents => List.unmodifiable(_agents.values);
}
