import 'package:meta/meta.dart';

/// Technical schema card declaring capabilities, limits, and schemas for an Agent.
@immutable
class AgentCard {
  final String agentId;
  final String role;
  final List<String> capabilities;
  final String inputSchema;
  final String outputSchema;
  final bool requiresModel;
  final bool requiresStructuredOutput;
  final int latencyBudgetMs;
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
