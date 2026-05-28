import 'dart:convert';
import '../models/evaluator_delta.dart';

/// Handles parsing, structure validation, and safety clamping of agent output.
class OutputValidator {
  const OutputValidator();

  /// Parses raw text output from the Evaluator LLM and returns a clamped, valid [EvaluatorDelta].
  /// 
  /// Throws a [FormatException] if the text cannot be parsed as JSON or has invalid types.
  EvaluatorDelta parseEvaluatorDelta(String rawContent) {
    String jsonText = rawContent.trim();
    
    // Clean up markdown code blocks if present
    if (jsonText.startsWith("```")) {
      final match = RegExp(r'```(?:json)?([\s\S]*?)```').firstMatch(jsonText);
      if (match != null) {
        jsonText = match.group(1)!.trim();
      }
    }

    final decoded = jsonDecode(jsonText);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException("Decoded JSON content is not a JSON Map");
    }

    // Read and enforce strict bounds clamping as per TGDD Section 6.1
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
