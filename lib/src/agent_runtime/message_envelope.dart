import 'package:meta/meta.dart';

// TODO(phase5): Queste classi sono riservate per l'implementazione dell'orchestrazione avanzata e
// della messaggistica strutturata asincrona tra agenti nella Fase 5.

/// Vincoli di performance applicati all'invocazione di un agente.
///
/// TODO(phase5): Riservato per il controllo di latenza e conformità strutturata nella Fase 5.
@immutable
class MessageConstraints {
  /// Il budget massimo di latenza (in millisecondi) consentito per il task.
  final int latencyBudgetMs;

  /// Specifica se per questo messaggio è obbligatorio produrre un output strutturato JSON.
  final bool structuredOutputRequired;

  const MessageConstraints({
    required this.latencyBudgetMs,
    required this.structuredOutputRequired,
  });

  /// Crea un'istanza a partire da una mappa JSON.
  factory MessageConstraints.fromJson(Map<String, dynamic> json) {
    return MessageConstraints(
      latencyBudgetMs: json['latency_budget_ms'] as int? ?? 1000,
      structuredOutputRequired: json['structured_output_required'] as bool? ?? false,
    );
  }

  /// Converte questa istanza in una mappa JSON.
  Map<String, dynamic> toJson() {
    return {
      'latency_budget_ms': latencyBudgetMs,
      'structured_output_required': structuredOutputRequired,
    };
  }
}

/// Involucro (envelope) di messaggistica strutturato per le richieste inviate agli agenti.
///
/// TODO(phase5): Riservato per il protocollo di comunicazione inter-agente della Fase 5.
@immutable
class MessageEnvelope {
  /// Identificatore univoco del messaggio.
  final String messageId;

  /// L'identificatore del turno di gioco corrente.
  final int turnId;

  /// ID dell'agente mittente.
  final String fromAgent;

  /// ID dell'agente destinatario.
  final String toAgent;

  /// Descrizione o istruzione del task da eseguire.
  final String task;

  /// Schema di convalida per l'input.
  final String inputSchema;

  /// Il carico di dati (payload) della richiesta.
  final Map<String, dynamic> payload;

  /// I vincoli prestazionali applicati a questa richiesta.
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

  /// Crea un'istanza a partire da una mappa JSON.
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

  /// Converte questa istanza in una mappa JSON.
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

/// Metadati di telemetria e performance registrati durante l'esecuzione dell'agente.
///
/// TODO(phase5): Riservato per il tracciamento della telemetria dei modelli a runtime nella Fase 5.
@immutable
class RuntimeMetadata {
  /// L'ID del modello di linguaggio utilizzato per l'inferenza.
  final String modelId;

  /// Tempo totale impiegato dall'agente (in millisecondi).
  final int latencyMs;

  /// Numero di token inviati in input.
  final int tokensIn;

  /// Numero di token generati in output.
  final int tokensOut;

  /// Backend di inferenza impiegato (es. 'llama_cpp').
  final String backend;

  const RuntimeMetadata({
    required this.modelId,
    required this.latencyMs,
    required this.tokensIn,
    required this.tokensOut,
    required this.backend,
  });

  /// Crea un'istanza a partire da una mappa JSON.
  factory RuntimeMetadata.fromJson(Map<String, dynamic> json) {
    return RuntimeMetadata(
      modelId: json['model_id'] as String? ?? '',
      latencyMs: json['latency_ms'] as int? ?? 0,
      tokensIn: json['tokens_in'] as int? ?? 0,
      tokensOut: json['tokens_out'] as int? ?? 0,
      backend: json['backend'] as String? ?? '',
    );
  }

  /// Converte questa istanza in una mappa JSON.
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

/// Involucro (envelope) di risposta generato da un agente.
///
/// TODO(phase5): Riservato per il protocollo di risposta asincrona inter-agente della Fase 5.
@immutable
class AgentResponseEnvelope {
  /// Identificatore univoco del messaggio di risposta.
  final String messageId;

  /// L'ID del messaggio di richiesta a cui questa risposta è correlata.
  final String correlationId;

  /// Stato dell'operazione ("ok", "error", "fallback").
  final String status;

  /// Schema di convalida dell'output.
  final String outputSchema;

  /// Carico utile di dati ritornato dall'agente.
  final Map<String, dynamic> payload;

  /// Informazioni sulla telemetria di runtime del modello.
  final RuntimeMetadata runtime;

  const AgentResponseEnvelope({
    required this.messageId,
    required this.correlationId,
    required this.status,
    required this.outputSchema,
    required this.payload,
    required this.runtime,
  });

  /// Crea un'istanza a partire da una mappa JSON.
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

  /// Converte questa istanza in una mappa JSON.
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

