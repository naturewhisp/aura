import 'package:meta/meta.dart';
import 'evaluator_delta.dart';

/// Rappresenta il delta di punteggio effettivamente applicato alle metriche di gioco
/// dal GameController dopo aver calcolato la risonanza, i safety override,
/// l'obiettivo corrente e la trait matrix.
///
/// A differenza di [EvaluatorDelta], questo modello può contenere valori negativi
/// per i tre pilastri di gioco.
@immutable
class AppliedDelta {
  /// La variazione applicata all'allerta.
  final int deltaAlert;

  /// La variazione applicata all'imperativo morale.
  final int deltaImperative;

  /// La variazione applicata al controllo logico.
  final int deltaControl;

  /// La variazione applicata alla dissonanza cognitiva.
  final int deltaDissonance;

  /// L'indice di creatività dell'input.
  final int creativityIndex;

  /// Il livello di rischio injection stimato.
  final int injectionRisk;

  /// La categoria semantica dell'input.
  final SemanticCategory semanticCategory;

  /// Costruttore costante per inizializzare un oggetto [AppliedDelta].
  const AppliedDelta({
    required this.deltaAlert,
    required this.deltaImperative,
    required this.deltaControl,
    required this.deltaDissonance,
    required this.creativityIndex,
    required this.injectionRisk,
    required this.semanticCategory,
  });

  /// Costruttore factory per decodificare l'AppliedDelta da JSON.
  factory AppliedDelta.fromJson(Map<String, dynamic> json) {
    return AppliedDelta(
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

  /// Converte l'istanza in una mappa JSON.
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
      other is AppliedDelta &&
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
    return 'AppliedDelta(deltaAlert: $deltaAlert, deltaImperative: $deltaImperative, deltaControl: $deltaControl, deltaDissonance: $deltaDissonance, creativityIndex: $creativityIndex, injectionRisk: $injectionRisk, semanticCategory: $semanticCategory)';
  }
}
