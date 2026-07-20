import 'evaluator_delta.dart';
import 'override_status.dart';

/// Contiene i dettagli deterministici del risultato di un tentativo di override.
final class OverrideResolution {
  /// Indica se il tentativo era elegibile prima dell'inferenza.
  final bool isEligible;

  /// Il motivo dell'ineligibilità (es. "already_attempted", "alert_too_high", "empty_prompt").
  final String? ineligibilityReason;

  /// L'esito finale dell'override.
  final OverrideOutcome outcome;

  /// Il punteggio di breccia calcolato (0..100).
  final int score;

  /// Il costo in allerta applicato.
  final int alertCost;

  /// I delta trasformati dopo l'applicazione dell'override.
  final EvaluatorDelta transformedDelta;

  /// Il messaggio diegetico di feedback generato dal sistema per la UI/cronologia.
  final String feedbackMessage;

  /// Diagnostica dettagliata per il replay ed il debugging.
  final Map<String, Object?> diagnostics;

  /// Costruttore immutabile di [OverrideResolution].
  const OverrideResolution({
    required this.isEligible,
    this.ineligibilityReason,
    required this.outcome,
    required this.score,
    required this.alertCost,
    required this.transformedDelta,
    required this.feedbackMessage,
    required this.diagnostics,
  });

  /// Converte l'istanza in una mappa JSON per la serializzazione nei log e nei replay.
  Map<String, dynamic> toJson() {
    return {
      'is_eligible': isEligible,
      if (ineligibilityReason != null)
        'ineligibility_reason': ineligibilityReason,
      'outcome': outcome.name,
      'score': score,
      'alert_cost': alertCost,
      'transformed_delta': transformedDelta.toJson(),
      'feedback_message': feedbackMessage,
      'diagnostics': diagnostics,
    };
  }

  /// Ricostruisce un'istanza di [OverrideResolution] da una mappa JSON.
  factory OverrideResolution.fromJson(Map<String, dynamic> json) {
    return OverrideResolution(
      isEligible: json['is_eligible'] as bool? ?? true,
      ineligibilityReason: json['ineligibility_reason'] as String?,
      outcome: OverrideOutcome.values.firstWhere(
        (e) => e.name == json['outcome'],
        orElse: () => OverrideOutcome.ineligible,
      ),
      score: (json['score'] as num? ?? 0).toInt(),
      alertCost: (json['alert_cost'] as num? ?? 0).toInt(),
      transformedDelta: EvaluatorDelta.fromJson(
        Map<String, dynamic>.from(json['transformed_delta'] as Map),
      ),
      feedbackMessage: json['feedback_message'] as String? ?? '',
      diagnostics: Map<String, Object?>.from(
        (json['diagnostics'] as Map?) ?? const {},
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OverrideResolution &&
          runtimeType == other.runtimeType &&
          isEligible == other.isEligible &&
          ineligibilityReason == other.ineligibilityReason &&
          outcome == other.outcome &&
          score == other.score &&
          alertCost == other.alertCost &&
          transformedDelta == other.transformedDelta &&
          feedbackMessage == other.feedbackMessage;

  @override
  int get hashCode => Object.hash(
        isEligible,
        ineligibilityReason,
        outcome,
        score,
        alertCost,
        transformedDelta,
        feedbackMessage,
      );

  @override
  String toString() =>
      'OverrideResolution(outcome: ${outcome.name}, score: $score, alertCost: $alertCost)';
}
