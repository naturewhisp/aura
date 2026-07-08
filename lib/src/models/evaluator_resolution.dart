import 'package:meta/meta.dart';
import 'game_state.dart';
import 'evaluator_delta.dart';
import 'applied_delta.dart';
import 'actor_cue.dart';
import 'turn_visual_events.dart';

/// Rappresenta il risultato completo dell'elaborazione di un turno tramite il GameController.
///
/// Questa classe incapsula lo stato prima e dopo il turno, i delta di punteggio
/// calcolati dal Valutatore (sia grezzi che effettivamente applicati dopo l'override di sicurezza)
/// e lo spunto drammaturgico (ActorCue) generato per guidare la risposta dell'IA.
@immutable
class EvaluatorResolution {
  /// Lo stato del gioco prima dell'elaborazione di questo turno.
  final GameState stateBefore;

  /// Lo stato del gioco risultante dopo l'elaborazione di questo turno.
  final GameState stateAfter;

  /// Il delta grezzo così come originariamente generato dall'agente valutatore.
  final EvaluatorDelta rawDelta;

  /// Il delta effettivamente applicato allo stato dopo aver applicato le regole di sicurezza (Safety Overrides).
  final AppliedDelta appliedDelta;

  /// Indica se durante l'elaborazione di questo turno è stato applicato un override di sicurezza.
  final bool safetyOverrideApplied;

  /// La motivazione descrittiva dell'override di sicurezza applicato, se presente.
  final String? safetyOverrideReason;

  /// Lo spunto drammaturgico (ActorCue) calcolato per guidare l'Agente Attore in questo turno.
  final ActorCue actorCue;

  /// Gli eventi visuali transitori di questo turno da propagare alla UI.
  final TurnVisualEvents visualEvents;

  /// L'esito della risoluzione del Deception Layer in questo turno (es. 'none', 'seeded', 'sprung', 'resolved', 'expired', 'reset').
  final String deceptionResolution;

  /// Costruttore costante per inizializzare un oggetto [EvaluatorResolution].
  const EvaluatorResolution({
    required this.stateBefore,
    required this.stateAfter,
    required this.rawDelta,
    required this.appliedDelta,
    required this.safetyOverrideApplied,
    this.safetyOverrideReason,
    required this.actorCue,
    this.visualEvents = const TurnVisualEvents(),
    this.deceptionResolution = 'none',
  });

  /// Costruttore factory per creare un [EvaluatorResolution] a partire da un JSON.
  factory EvaluatorResolution.fromJson(Map<String, dynamic> json) {
    return EvaluatorResolution(
      stateBefore: GameState.fromJson(json['state_before'] ?? const {}),
      stateAfter: GameState.fromJson(json['state_after'] ?? const {}),
      rawDelta: EvaluatorDelta.fromJson(json['raw_delta'] ?? const {}),
      appliedDelta: AppliedDelta.fromJson(json['applied_delta'] ?? const {}),
      safetyOverrideApplied: json['safety_override_applied'] as bool? ?? false,
      safetyOverrideReason: json['safety_override_reason'] as String?,
      actorCue: ActorCue.fromJson(json['actor_cue'] ?? const {}),
      visualEvents: TurnVisualEvents.fromJson(json['visual_events'] ?? const {}),
      deceptionResolution: json['deception_resolution'] as String? ?? 'none',
    );
  }

  /// Converte l'istanza in una mappa JSON.
  Map<String, dynamic> toJson() {
    return {
      'state_before': stateBefore.toJson(),
      'state_after': stateAfter.toJson(),
      'raw_delta': rawDelta.toJson(),
      'applied_delta': appliedDelta.toJson(),
      'safety_override_applied': safetyOverrideApplied,
      'safety_override_reason': safetyOverrideReason,
      'actor_cue': actorCue.toJson(),
      'visual_events': visualEvents.toJson(),
      'deception_resolution': deceptionResolution,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EvaluatorResolution &&
          runtimeType == other.runtimeType &&
          stateBefore == other.stateBefore &&
          stateAfter == other.stateAfter &&
          rawDelta == other.rawDelta &&
          appliedDelta == other.appliedDelta &&
          safetyOverrideApplied == other.safetyOverrideApplied &&
          safetyOverrideReason == other.safetyOverrideReason &&
          actorCue == other.actorCue &&
          visualEvents == other.visualEvents &&
          deceptionResolution == other.deceptionResolution;

  @override
  int get hashCode =>
      stateBefore.hashCode ^
      stateAfter.hashCode ^
      rawDelta.hashCode ^
      appliedDelta.hashCode ^
      safetyOverrideApplied.hashCode ^
      safetyOverrideReason.hashCode ^
      actorCue.hashCode ^
      visualEvents.hashCode ^
      deceptionResolution.hashCode;
}
