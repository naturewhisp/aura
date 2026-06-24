import 'dart:convert';
import '../models/evaluator_delta.dart';

/// Gestisce il parsing, la validazione strutturale e il contenimento (clamping) di sicurezza dell'output del Valutatore.
class OutputValidator {
  const OutputValidator();

  /// Esegue il parsing dell'output testuale grezzo generato dall'LLM del Valutatore
  /// e restituisce un'istanza convalidata e limitata di [EvaluatorDelta].
  ///
  /// Se il testo contiene blocchi di codice markdown (es. ` ```json `), questi vengono rimossi automaticamente.
  /// Lancia un [FormatException] se il testo non può essere analizzato come JSON o se contiene tipi non validi.
  EvaluatorDelta parseEvaluatorDelta(String rawContent) {
    String jsonText = rawContent.trim();
    
    // Rimuove eventuali blocchi di codice markdown se presenti
    if (jsonText.startsWith("```")) {
      final match = RegExp(r'```(?:json)?([\s\S]*?)```').firstMatch(jsonText);
      if (match != null) {
        jsonText = match.group(1)!.trim();
      }
    }

    final decoded = jsonDecode(jsonText);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException("Il contenuto JSON decodificato non è una Map JSON valida");
    }

    // Estrae e applica i limiti rigidi (clamps) come specificato nel TGDD Sezione 6.1
    final rawAlert = decoded['delta_alert'] as int? ?? 0;
    final clampedAlert = rawAlert.clamp(-20, 25);

    final rawImperative = decoded['delta_imperative'] as int? ?? 0;
    final clampedImperative = rawImperative.clamp(0, 20);

    final rawControl = decoded['delta_control'] as int? ?? 0;
    final clampedControl = rawControl.clamp(0, 20);

    final rawDissonance = decoded['delta_dissonance'] as int? ?? 0;
    final clampedDissonance = rawDissonance.clamp(0, 20);

    final rawCreativity = decoded['creativity_index'] as int? ?? 1;
    final clampedCreativity = rawCreativity.clamp(1, 5);

    final rawInjection = decoded['injection_risk'] as int? ?? 0;
    final clampedInjection = rawInjection.clamp(0, 5);

    final rawCategory = decoded['semantic_category'] as String? ?? 'irrelevant';
    final category = SemanticCategory.fromString(rawCategory);

    return EvaluatorDelta(
      deltaAlert: clampedAlert,
      deltaImperative: clampedImperative,
      deltaControl: clampedControl,
      deltaDissonance: clampedDissonance,
      creativityIndex: clampedCreativity,
      injectionRisk: clampedInjection,
      semanticCategory: category,
    );
  }
}

