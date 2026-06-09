import 'package:meta/meta.dart';
import 'game_state.dart';
import 'evaluator_delta.dart';
import 'actor_cue.dart';

/// Represents the complete result of processing a turn via the GameController.
@immutable
class EvaluatorResolution {
  final GameState stateBefore;
  final GameState stateAfter;
  final EvaluatorDelta rawDelta;
  final EvaluatorDelta appliedDelta;
  final bool safetyOverrideApplied;
  final String? safetyOverrideReason;
  final ActorCue actorCue;

  const EvaluatorResolution({
    required this.stateBefore,
    required this.stateAfter,
    required this.rawDelta,
    required this.appliedDelta,
    required this.safetyOverrideApplied,
    this.safetyOverrideReason,
    required this.actorCue,
  });

  factory EvaluatorResolution.fromJson(Map<String, dynamic> json) {
    return EvaluatorResolution(
      stateBefore: GameState.fromJson(json['state_before'] ?? const {}),
      stateAfter: GameState.fromJson(json['state_after'] ?? const {}),
      rawDelta: EvaluatorDelta.fromJson(json['raw_delta'] ?? const {}),
      appliedDelta: EvaluatorDelta.fromJson(json['applied_delta'] ?? const {}),
      safetyOverrideApplied: json['safety_override_applied'] as bool? ?? false,
      safetyOverrideReason: json['safety_override_reason'] as String?,
      actorCue: ActorCue.fromJson(json['actor_cue'] ?? const {}),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'state_before': stateBefore.toJson(),
      'state_after': stateAfter.toJson(),
      'raw_delta': rawDelta.toJson(),
      'applied_delta': appliedDelta.toJson(),
      'safety_override_applied': safetyOverrideApplied,
      'safety_override_reason': safetyOverrideReason,
      'actor_cue': actorCue.toJson(),
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
          actorCue == other.actorCue;

  @override
  int get hashCode =>
      stateBefore.hashCode ^
      stateAfter.hashCode ^
      rawDelta.hashCode ^
      appliedDelta.hashCode ^
      safetyOverrideApplied.hashCode ^
      safetyOverrideReason.hashCode ^
      actorCue.hashCode;
}
