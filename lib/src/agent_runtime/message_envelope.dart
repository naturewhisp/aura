import 'package:meta/meta.dart';

/// Performance constraints applied to an agent invocation.
@immutable
class MessageConstraints {
  final int latencyBudgetMs;
  final bool structuredOutputRequired;

  const MessageConstraints({
    required this.latencyBudgetMs,
    required this.structuredOutputRequired,
  });

  factory MessageConstraints.fromJson(Map<String, dynamic> json) {
    return MessageConstraints(
      latencyBudgetMs: json['latency_budget_ms'] as int? ?? 1000,
      structuredOutputRequired: json['structured_output_required'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'latency_budget_ms': latencyBudgetMs,
      'structured_output_required': structuredOutputRequired,
    };
  }
}

/// Staged envelope wrap for agent requests.
@immutable
class MessageEnvelope {
  final String messageId;
  final int turnId;
  final String fromAgent;
  final String toAgent;
  final String task;
  final String inputSchema;
  final Map<String, dynamic> payload;
  final MessageConstraints constraints;

  const MessageEnvelope({
    required this.messageId,
    required this.turnId,
    required this.fromAgent,
    required this.toAgent,
    required this.task,
    required this.inputSchema,
    required this.payload,
    required this.constraints,
  });

  factory MessageEnvelope.fromJson(Map<String, dynamic> json) {
    return MessageEnvelope(
      messageId: json['message_id'] as String? ?? '',
      turnId: json['turn_id'] as int? ?? 0,
      fromAgent: json['from_agent'] as String? ?? '',
      toAgent: json['to_agent'] as String? ?? '',
      task: json['task'] as String? ?? '',
      inputSchema: json['input_schema'] as String? ?? '',
      payload: Map<String, dynamic>.from(json['payload'] ?? const {}),
      constraints: MessageConstraints.fromJson(json['constraints'] ?? const {}),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'message_id': messageId,
      'turn_id': turnId,
      'from_agent': fromAgent,
      'to_agent': toAgent,
      'task': task,
      'input_schema': inputSchema,
      'payload': payload,
      'constraints': constraints.toJson(),
    };
  }
}

/// Performance telemetry recorded during agent execution.
@immutable
class RuntimeMetadata {
  final String modelId;
  final int latencyMs;
  final int tokensIn;
  final int tokensOut;
  final String backend;

  const RuntimeMetadata({
    required this.modelId,
    required this.latencyMs,
    required this.tokensIn,
    required this.tokensOut,
    required this.backend,
  });

  factory RuntimeMetadata.fromJson(Map<String, dynamic> json) {
    return RuntimeMetadata(
      modelId: json['model_id'] as String? ?? '',
      latencyMs: json['latency_ms'] as int? ?? 0,
      tokensIn: json['tokens_in'] as int? ?? 0,
      tokensOut: json['tokens_out'] as int? ?? 0,
      backend: json['backend'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'model_id': modelId,
      'latency_ms': latencyMs,
      'tokens_in': tokensIn,
      'tokens_out': tokensOut,
      'backend': backend,
    };
  }
}

/// Staged envelope wrap for agent responses.
@immutable
class AgentResponseEnvelope {
  final String messageId;
  final String correlationId;
  final String status; // "ok", "error", "fallback"
  final String outputSchema;
  final Map<String, dynamic> payload;
  final RuntimeMetadata runtime;

  const AgentResponseEnvelope({
    required this.messageId,
    required this.correlationId,
    required this.status,
    required this.outputSchema,
    required this.payload,
    required this.runtime,
  });

  factory AgentResponseEnvelope.fromJson(Map<String, dynamic> json) {
    return AgentResponseEnvelope(
      messageId: json['message_id'] as String? ?? '',
      correlationId: json['correlation_id'] as String? ?? '',
      status: json['status'] as String? ?? 'ok',
      outputSchema: json['output_schema'] as String? ?? '',
      payload: Map<String, dynamic>.from(json['payload'] ?? const {}),
      runtime: RuntimeMetadata.fromJson(json['runtime'] ?? const {}),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'message_id': messageId,
      'correlation_id': correlationId,
      'status': status,
      'output_schema': outputSchema,
      'payload': payload,
      'runtime': runtime.toJson(),
    };
  }
}
