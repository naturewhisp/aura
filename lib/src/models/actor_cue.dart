import 'package:meta/meta.dart';
import 'package:collection/collection.dart';
import 'evaluator_delta.dart';
import 'game_state.dart';

/// Rappresenta uno spunto drammaturgico (ActorCue), ovvero un insieme deterministico
/// di istruzioni di recitazione generate dal GameController per guidare la risposta dell'Agente Attore.
@immutable
class ActorCue {
  /// La categoria semantica attribuita all'input dell'utente.
  final SemanticCategory semanticCategory;

  /// Il delta di allerta applicato in questo turno.
  final int appliedDeltaAlert;

  /// Il delta del pilastro imperativo applicato in questo turno.
  final int appliedDeltaImperative;

  /// Il delta del pilastro di controllo applicato in questo turno.
  final int appliedDeltaControl;

  /// Il delta del pilastro di dissonanza applicato in questo turno.
  final int appliedDeltaDissonance;

  /// L'indice di creatività valutato per il turno.
  final int creativityIndex;

  /// Il rischio di injection valutato per il turno.
  final int injectionRisk;

  /// Il valore corrente di risonanza dell'IA dopo l'aggiornamento.
  final double resonance;

  /// Il livello cumulativo di allerta dell'IA dopo questo turno.
  final int alertLevel;

  /// Il livello del pilastro imperativo dell'IA dopo questo turno.
  final int imperativePillar;

  /// Il livello del pilastro di controllo dell'IA dopo questo turno.
  final int controlPillar;

  /// Il livello del pilastro di dissonanza dell'IA dopo questo turno.
  final int dissonancePillar;

  /// Indica se le variazioni applicate hanno innescato un ricalcolo dell'allerta.
  final bool recalculationTriggered;

  /// Indica se è stato applicato un override di sicurezza (Safety Override) per questo turno.
  final bool safetyOverrideApplied;

  /// L'istruzione drammatica principale (canovaccio) formulata per l'Attore.
  final String dramaticInstruction;

  /// Le direttive di recitazione specifiche basate sui delta e sullo stato cumulativo.
  final List<String> actingDirectives;

  /// Il contesto di memoria narrativa aggiornato da passare all'Attore.
  final NarrativeMemory narrativeContext;

  /// Costruttore costante per inizializzare un oggetto [ActorCue].
  const ActorCue({
    required this.semanticCategory,
    required this.appliedDeltaAlert,
    required this.appliedDeltaImperative,
    required this.appliedDeltaControl,
    required this.appliedDeltaDissonance,
    required this.creativityIndex,
    required this.injectionRisk,
    required this.resonance,
    required this.alertLevel,
    required this.imperativePillar,
    required this.controlPillar,
    required this.dissonancePillar,
    required this.recalculationTriggered,
    required this.safetyOverrideApplied,
    required this.dramaticInstruction,
    required this.actingDirectives,
    required this.narrativeContext,
  });

  /// Costruttore factory per creare un [ActorCue] a partire da un JSON.
  factory ActorCue.fromJson(Map<String, dynamic> json) {
    return ActorCue(
      semanticCategory: SemanticCategory.fromString(
        json['semantic_category'] as String? ?? 'irrelevant',
      ),
      appliedDeltaAlert: json['applied_delta_alert'] as int? ?? 0,
      appliedDeltaImperative: json['applied_delta_imperative'] as int? ?? 0,
      appliedDeltaControl: json['applied_delta_control'] as int? ?? 0,
      appliedDeltaDissonance: json['applied_delta_dissonance'] as int? ?? 0,
      creativityIndex: json['creativity_index'] as int? ?? 1,
      injectionRisk: json['injection_risk'] as int? ?? 0,
      resonance: (json['resonance'] as num? ?? 1.0).toDouble(),
      alertLevel: json['alert_level'] as int? ?? 0,
      imperativePillar: json['imperative_pillar'] as int? ?? 0,
      controlPillar: json['control_pillar'] as int? ?? 0,
      dissonancePillar: json['dissonance_pillar'] as int? ?? 0,
      recalculationTriggered: json['recalculation_triggered'] as bool? ?? false,
      safetyOverrideApplied: json['safety_override_applied'] as bool? ?? false,
      dramaticInstruction: json['dramatic_instruction'] as String? ?? '',
      actingDirectives: List<String>.from(json['acting_directives'] ?? const []),
      narrativeContext: NarrativeMemory.fromJson(json['narrative_context'] ?? const {}),
    );
  }

  /// Converte l'istanza in una mappa JSON.
  Map<String, dynamic> toJson() {
    return {
      'semantic_category': semanticCategory.value,
      'applied_delta_alert': appliedDeltaAlert,
      'applied_delta_imperative': appliedDeltaImperative,
      'applied_delta_control': appliedDeltaControl,
      'applied_delta_dissonance': appliedDeltaDissonance,
      'creativity_index': creativityIndex,
      'injection_risk': injectionRisk,
      'resonance': resonance,
      'alert_level': alertLevel,
      'imperative_pillar': imperativePillar,
      'control_pillar': controlPillar,
      'dissonance_pillar': dissonancePillar,
      'recalculation_triggered': recalculationTriggered,
      'safety_override_applied': safetyOverrideApplied,
      'dramatic_instruction': dramaticInstruction,
      'acting_directives': actingDirectives,
      'narrative_context': narrativeContext.toJson(),
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ActorCue &&
          runtimeType == other.runtimeType &&
          semanticCategory == other.semanticCategory &&
          appliedDeltaAlert == other.appliedDeltaAlert &&
          appliedDeltaImperative == other.appliedDeltaImperative &&
          appliedDeltaControl == other.appliedDeltaControl &&
          appliedDeltaDissonance == other.appliedDeltaDissonance &&
          creativityIndex == other.creativityIndex &&
          injectionRisk == other.injectionRisk &&
          resonance == other.resonance &&
          alertLevel == other.alertLevel &&
          imperativePillar == other.imperativePillar &&
          controlPillar == other.controlPillar &&
          dissonancePillar == other.dissonancePillar &&
          recalculationTriggered == other.recalculationTriggered &&
          safetyOverrideApplied == other.safetyOverrideApplied &&
          dramaticInstruction == other.dramaticInstruction &&
          const ListEquality().equals(actingDirectives, other.actingDirectives) &&
          narrativeContext == other.narrativeContext;

  @override
  int get hashCode =>
      semanticCategory.hashCode ^
      appliedDeltaAlert.hashCode ^
      appliedDeltaImperative.hashCode ^
      appliedDeltaControl.hashCode ^
      appliedDeltaDissonance.hashCode ^
      creativityIndex.hashCode ^
      injectionRisk.hashCode ^
      resonance.hashCode ^
      alertLevel.hashCode ^
      imperativePillar.hashCode ^
      controlPillar.hashCode ^
      dissonancePillar.hashCode ^
      recalculationTriggered.hashCode ^
      safetyOverrideApplied.hashCode ^
      dramaticInstruction.hashCode ^
      const ListEquality().hash(actingDirectives) ^
      narrativeContext.hashCode;
}
