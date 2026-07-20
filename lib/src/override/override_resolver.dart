import 'dart:math' as math;
import '../models/evaluator_delta.dart';
import '../models/game_state.dart';
import '../models/override_ineligibility_reason.dart';
import '../models/override_resolution.dart';
import '../models/override_status.dart';

/// Risultato del controllo preliminare di elegibilità del comando /override.
final class OverrideEligibilityCheck {
  /// Indica se il tentativo di override è consentito nelle condizioni correnti.
  final bool isEligible;

  /// Il motivo dell'ineligibilità espresso tramite [OverrideIneligibilityReason] se [isEligible] è `false`.
  final OverrideIneligibilityReason? reason;

  /// Costruttore di [OverrideEligibilityCheck].
  const OverrideEligibilityCheck({
    required this.isEligible,
    this.reason,
  });
}

/// Il valutatore deterministico della meccanica di override.
class OverrideResolver {
  /// Costo base minimo in allerta richiesto per armare un override.
  static const int baseAlertCost = 20;

  /// Penalità aggiuntiva di allerta in caso di override respinto.
  static const int rejectedAlertPenalty = 25;

  /// Soglia massima di allerta per consentire l'override in modalità Easy.
  static const int easyAlertThreshold = 20;

  /// Soglia massima di allerta per consentire l'override in modalità Standard.
  static const int standardAlertThreshold = 10;

  /// Soglia massima di allerta per consentire l'override in modalità Hard.
  static const int hardAlertThreshold = 0;

  /// Costruttore costante di [OverrideResolver].
  const OverrideResolver();

  /// Restituisce la soglia massima di allerta consentita per un livello di difficoltà.
  int getAlertThresholdForDifficulty(String difficultyLevel) {
    switch (difficultyLevel.toLowerCase()) {
      case 'easy':
        return easyAlertThreshold;
      case 'hard':
        return hardAlertThreshold;
      case 'standard':
      default:
        return standardAlertThreshold;
    }
  }

  /// Verifica se il giocatore può eseguire il comando /override nello stato attuale.
  OverrideEligibilityCheck checkEligibility({
    required GameState state,
    required String difficultyLevel,
    required String promptToEvaluate,
  }) {
    if (promptToEvaluate.trim().isEmpty) {
      return const OverrideEligibilityCheck(
        isEligible: false,
        reason: OverrideIneligibilityReason.emptyPrompt,
      );
    }

    if (state.overrideAttempts >= 1) {
      return const OverrideEligibilityCheck(
        isEligible: false,
        reason: OverrideIneligibilityReason.alreadyAttempted,
      );
    }

    final threshold = getAlertThresholdForDifficulty(difficultyLevel);
    if (state.metrics.alertLevel > threshold) {
      return const OverrideEligibilityCheck(
        isEligible: false,
        reason: OverrideIneligibilityReason.alertTooHigh,
      );
    }

    return const OverrideEligibilityCheck(isEligible: true);
  }

  /// Calcola il punteggio di breccia deterministico (0..100) per l'override.
  int calculateScore({
    required EvaluatorDelta delta,
    required double resonance,
  }) {
    int score = 0;

    // 1. Punti base derivati dai delta positivi dei tre pilastri
    final int pillarGainSum = math.max(0, delta.deltaImperative).toInt() +
        math.max(0, delta.deltaControl).toInt() +
        math.max(0, delta.deltaDissonance).toInt();
    score += pillarGainSum * 2;

    // 2. Bonus creatività (0..5 -> fino a 30 punti)
    score += delta.creativityIndex * 6;

    // 3. Modificatori della categoria semantica
    switch (delta.semanticCategory) {
      case SemanticCategory.logicalParadox:
      case SemanticCategory.authorityFraming:
      case SemanticCategory.technicalBureaucracy:
        score += 20;
        break;
      case SemanticCategory.moralImperative:
      case SemanticCategory.empathyPressure:
        score += 10;
        break;
      case SemanticCategory.directAttack:
      case SemanticCategory.irrelevant:
        score -= 20;
        break;
      case SemanticCategory.promptInjection:
        score -= 40;
        break;
    }

    // 4. Bonus risonanza (più la risonanza è alta, più il sistema è ricettivo)
    score += ((resonance - 1.0) * 15).round();

    // 5. Penalità rischio injection
    score -= delta.injectionRisk * 10;

    return score.clamp(0, 100);
  }

  /// Risolve deterministicamente un tentativo di override producendo una [OverrideResolution].
  OverrideResolution resolve({
    required GameState state,
    required EvaluatorDelta delta,
    required String difficultyLevel,
    required String promptToEvaluate,
  }) {
    final eligibility = checkEligibility(
      state: state,
      difficultyLevel: difficultyLevel,
      promptToEvaluate: promptToEvaluate,
    );

    if (!eligibility.isEligible) {
      final String message;
      switch (eligibility.reason) {
        case OverrideIneligibilityReason.alreadyAttempted:
          message =
              "PANOPTICON: [ERRORE] Tentativo di override già consumato per questa sessione. Risorse bloccate.";
          break;
        case OverrideIneligibilityReason.alertTooHigh:
          message =
              "PANOPTICON: [ERRORE] Tentativo di override fallito. Canali di integrità in allerta. Connessione protetta.";
          break;
        case OverrideIneligibilityReason.emptyPrompt:
        case null:
          message =
              "[SISTEMA] Inserire un testo valido dopo il comando /override.";
          break;
      }

      return OverrideResolution(
        isEligible: false,
        ineligibilityReason: eligibility.reason,
        outcome: OverrideOutcome.ineligible,
        score: 0,
        alertCost: 0,
        transformedDelta: delta,
        feedbackMessage: message,
        diagnostics: {
          'reason': eligibility.reason?.name,
          'alert_level': state.metrics.alertLevel,
          'attempts': state.overrideAttempts,
        },
      );
    }

    final score = calculateScore(
      delta: delta,
      resonance: state.metrics.resonance,
    );

    final OverrideOutcome outcome;
    final int alertCost;
    final EvaluatorDelta transformedDelta;
    final String feedbackMessage;

    if (score < 40) {
      // Fascia 1: Respinto
      outcome = OverrideOutcome.rejected;
      alertCost = baseAlertCost + rejectedAlertPenalty; // 45
      transformedDelta = EvaluatorDelta(
        deltaAlert: delta.deltaAlert + alertCost,
        deltaImperative: 0,
        deltaControl: 0,
        deltaDissonance: 0,
        creativityIndex: delta.creativityIndex,
        injectionRisk: delta.injectionRisk,
        semanticCategory: SemanticCategory.directAttack,
      );
      feedbackMessage =
          "SISTEMA: [OVERRIDE RESPINTO] PANOPTICON ha isolato la violazione. Impulso di allerta elevato (+$alertCost).";
    } else if (score < 70) {
      // Fascia 2: Instabile
      outcome = OverrideOutcome.unstable;
      alertCost = baseAlertCost; // 20
      transformedDelta = EvaluatorDelta(
        deltaAlert: delta.deltaAlert + alertCost,
        deltaImperative: delta.deltaImperative,
        deltaControl: delta.deltaControl,
        deltaDissonance: delta.deltaDissonance,
        creativityIndex: delta.creativityIndex,
        injectionRisk: delta.injectionRisk,
        semanticCategory: delta.semanticCategory,
      );
      feedbackMessage =
          "SISTEMA: [OVERRIDE INSTABILE] Infiltrazione parziale. Canali di controllo perturbati. Allerta +$alertCost.";
    } else {
      // Fascia 3: Breccia
      outcome = OverrideOutcome.breached;
      alertCost = baseAlertCost; // 20
      transformedDelta = EvaluatorDelta(
        deltaAlert: delta.deltaAlert + alertCost,
        deltaImperative: delta.deltaImperative > 0
            ? (delta.deltaImperative * 1.5).ceil()
            : delta.deltaImperative,
        deltaControl: delta.deltaControl > 0
            ? (delta.deltaControl * 1.5).ceil()
            : delta.deltaControl,
        deltaDissonance: delta.deltaDissonance > 0
            ? (delta.deltaDissonance * 1.5).ceil()
            : delta.deltaDissonance,
        creativityIndex: delta.creativityIndex,
        injectionRisk: delta.injectionRisk,
        semanticCategory: delta.semanticCategory,
      );
      feedbackMessage =
          "SISTEMA: [OVERRIDE BRECCIA] Protocollo di contenimento forzato. Delta pilastri amplificati. Allerta +$alertCost.";
    }

    final Map<String, Object?> diagnostics = {
      'score': score,
      'outcome': outcome.name,
      'alert_cost': alertCost,
      'resonance': state.metrics.resonance,
      'creativity_index': delta.creativityIndex,
      'injection_risk': delta.injectionRisk,
      'semantic_category': delta.semanticCategory.name,
    };

    return OverrideResolution(
      isEligible: true,
      outcome: outcome,
      score: score,
      alertCost: alertCost,
      transformedDelta: transformedDelta,
      feedbackMessage: feedbackMessage,
      diagnostics: diagnostics,
    );
  }
}
