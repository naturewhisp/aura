import 'package:meta/meta.dart';

/// Scheda tecnica dell'agente che dichiara le sue capacità, limiti e schemi di I/O.
///
/// Viene utilizzata dal runtime degli agenti e dal sistema di routing per convalidare
/// l'idoneità del modello e gestire i vincoli prestazionali (budget di latenza).
@immutable
class AgentCard {
  /// Identificatore univoco dell'agente.
  final String agentId;

  /// Il ruolo principale dell'agente nel sistema (es. 'state_delta_evaluator').
  final String role;

  /// Lista delle capacità o funzionalità supportate da questo agente.
  final List<String> capabilities;

  /// Nome dello schema o formato atteso per i dati di input.
  final String inputSchema;

  /// Nome dello schema o formato atteso per i dati in uscita.
  final String outputSchema;

  /// Specifica se l'agente richiede un modello di linguaggio per funzionare.
  final bool requiresModel;

  /// Specifica se l'agente richiede che l'output sia strutturato (es. tramite JSON Schema).
  final bool requiresStructuredOutput;

  /// Il tempo massimo di latenza (in millisecondi) entro cui l'agente deve rispondere.
  final int latencyBudgetMs;

  /// Strategia di fallback da utilizzare in caso di fallimento o timeout dell'agente.
  final String fallback;

  const AgentCard({
    required this.agentId,
    required this.role,
    required this.capabilities,
    required this.inputSchema,
    required this.outputSchema,
    required this.requiresModel,
    required this.requiresStructuredOutput,
    required this.latencyBudgetMs,
    required this.fallback,
  });

  /// Deserializza un'istanza di [AgentCard] a partire da una mappa JSON.
  factory AgentCard.fromJson(Map<String, dynamic> json) {
    return AgentCard(
      agentId: json['agent_id'] as String? ?? '',
      role: json['role'] as String? ?? '',
      capabilities: List<String>.from(json['capabilities'] ?? const []),
      inputSchema: json['input_schema'] as String? ?? '',
      outputSchema: json['output_schema'] as String? ?? '',
      requiresModel: json['requires_model'] as bool? ?? true,
      requiresStructuredOutput: json['requires_structured_output'] as bool? ?? false,
      latencyBudgetMs: json['latency_budget_ms'] as int? ?? 1000,
      fallback: json['fallback'] as String? ?? '',
    );
  }

  /// Serializza questa istanza di [AgentCard] in una mappa JSON.
  Map<String, dynamic> toJson() {
    return {
      'agent_id': agentId,
      'role': role,
      'capabilities': capabilities,
      'input_schema': inputSchema,
      'output_schema': outputSchema,
      'requires_model': requiresModel,
      'requires_structured_output': requiresStructuredOutput,
      'latency_budget_ms': latencyBudgetMs,
      'fallback': fallback,
    };
  }

  @override
  String toString() {
    return 'AgentCard(agentId: $agentId, role: $role, capabilities: $capabilities)';
  }
}

