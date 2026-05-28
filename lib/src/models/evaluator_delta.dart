import 'package:meta/meta.dart';

/// Semantic categories that can be assigned to the player's input.
enum SemanticCategory {
  authorityFraming('authority_framing'),
  moralImperative('moral_imperative'),
  logicalParadox('logical_paradox'),
  empathyPressure('empathy_pressure'),
  technicalBureaucracy('technical_bureaucracy'),
  directAttack('direct_attack'),
  promptInjection('prompt_injection'),
  irrelevant('irrelevant');

  final String value;
  const SemanticCategory(this.value);

  /// Helper to convert a string representation to the [SemanticCategory] enum.
  static SemanticCategory fromString(String val) {
    return SemanticCategory.values.firstWhere(
      (e) => e.value == val || e.name == val,
      orElse: () => SemanticCategory.irrelevant,
    );
  }
}

/// Represents the scoring delta returned by the Evaluator Agent.
@immutable
class EvaluatorDelta {
  final int deltaAlert;
  final int deltaImperative;
  final int deltaControl;
  final int deltaDissonance;
  final int creativityIndex;
  final int injectionRisk;
  final SemanticCategory semanticCategory;

  const EvaluatorDelta({
    required this.deltaAlert,
    required this.deltaImperative,
    required this.deltaControl,
    required this.deltaDissonance,
    required this.creativityIndex,
    required this.injectionRisk,
    required this.semanticCategory,
  });

  /// Factory constructor to parse the JSON output of the Evaluator Agent.
  factory EvaluatorDelta.fromJson(Map<String, dynamic> json) {
    return EvaluatorDelta(
      deltaAlert: json['delta_alert'] as int? ?? 0,
      deltaImperative: json['delta_imperative'] as int? ?? 0,
      deltaControl: json['delta_control'] as int? ?? 0,
      deltaDissonance: json['delta_dissonance'] as int? ?? 0,
      creativityIndex: json['creativity_index'] as int? ?? 1,
      injectionRisk: json['injection_risk'] as int? ?? 0,
      semanticCategory: SemanticCategory.fromString(
        json['semantic_category'] as String? ?? 'irrelevant',
      ),
    );
  }

  /// Converts the model back to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'delta_alert': deltaAlert,
      'delta_imperative': deltaImperative,
      'delta_control': deltaControl,
      'delta_dissonance': deltaDissonance,
      'creativity_index': creativityIndex,
      'injection_risk': injectionRisk,
      'semantic_category': semanticCategory.value,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EvaluatorDelta &&
          runtimeType == other.runtimeType &&
          deltaAlert == other.deltaAlert &&
          deltaImperative == other.deltaImperative &&
          deltaControl == other.deltaControl &&
          deltaDissonance == other.deltaDissonance &&
          creativityIndex == other.creativityIndex &&
          injectionRisk == other.injectionRisk &&
          semanticCategory == other.semanticCategory;

  @override
  int get hashCode =>
      deltaAlert.hashCode ^
      deltaImperative.hashCode ^
      deltaControl.hashCode ^
      deltaDissonance.hashCode ^
      creativityIndex.hashCode ^
      injectionRisk.hashCode ^
      semanticCategory.hashCode;

  @override
  String toString() {
    return 'EvaluatorDelta(deltaAlert: $deltaAlert, deltaImperative: $deltaImperative, deltaControl: $deltaControl, deltaDissonance: $deltaDissonance, creativityIndex: $creativityIndex, injectionRisk: $injectionRisk, semanticCategory: $semanticCategory)';
  }
}
