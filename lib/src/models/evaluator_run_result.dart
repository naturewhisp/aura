import 'evaluator_delta.dart';

/// Modalità esplicita di esecuzione del Valutatore.
enum EvaluatorExecutionMode {
  /// Pre-check deterministico per input vuoti, troppo brevi, saluti o injection esplicite rigide.
  deterministicPrecheck,

  /// Inferenza LLM completata via `json_schema` strutturato.
  llmJsonSchema,

  /// Inferenza LLM completata via `json_object`.
  llmJsonObject,

  /// Inferenza LLM completata via JSON estratto da testo o Markdown.
  llmRawJson,

  /// Fallback deterministico basato su regole (`RuleBasedEvaluatorBridge`).
  ruleBasedFallback,

  /// Default assoluto di emergenza (fail-safe).
  emergencyDefault,
}

/// Telemetria dettagliata per ciascun tentativo di inferenza eseguito dal Valutatore.
final class EvaluatorAttemptTelemetry {
  final EvaluatorExecutionMode mode;
  final String
      resultStatus; // e.g. "success", "http_400_grammar_error", "timeout", "parse_error"
  final int durationMs;
  final String? errorMessage;

  const EvaluatorAttemptTelemetry({
    required this.mode,
    required this.resultStatus,
    required this.durationMs,
    this.errorMessage,
  });

  Map<String, dynamic> toJson() => {
        'mode': mode.name,
        'result_status': resultStatus,
        'duration_ms': durationMs,
        if (errorMessage != null) 'error_message': errorMessage,
      };
}

/// DTO wrapper immutabile che racchiude sia il punteggio di dominio ([EvaluatorDelta])
/// sia i metadati di telemetria dell'esecuzione dell'agente Valutatore.
final class EvaluatorRunResult {
  /// Il delta numerico e la categoria semantica calcolati.
  final EvaluatorDelta delta;

  /// La modalità di esecuzione effettivamente utilizzata.
  final EvaluatorExecutionMode executionMode;

  /// L'identificatore del valutatore richiesto (es. alias o id modello).
  final String requestedEvaluator;

  /// L'identificatore del valutatore o del motore che ha realmente elaborato l'input.
  final String actualEvaluator;

  /// Motivo diagnostico sanitizzato del primo fallimento (se avvenuto un downgrade o fallback).
  final String? primaryFailureReason;

  /// Elenco dei tentativi eseguiti durante l'inferenza con la loro durata ed esito.
  final List<EvaluatorAttemptTelemetry> attempts;

  const EvaluatorRunResult({
    required this.delta,
    required this.executionMode,
    required this.requestedEvaluator,
    required this.actualEvaluator,
    this.primaryFailureReason,
    this.attempts = const [],
  });

  /// Restituisce `true` se l'esecuzione è degradata al fallback rule-based o all'emergency default.
  bool get usedRuleFallback =>
      executionMode == EvaluatorExecutionMode.ruleBasedFallback ||
      executionMode == EvaluatorExecutionMode.emergencyDefault;

  /// Restituisce `true` se l'esecuzione è terminata nell'emergency default assoluto.
  bool get usedEmergencyDefault =>
      executionMode == EvaluatorExecutionMode.emergencyDefault;
}
