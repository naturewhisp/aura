import 'package:aura_core/aura_core.dart';

final class CharacterizedTurnResult {
  final AppliedDelta appliedDelta;
  final GameMetrics metrics;
  final double resonance;
  final List<String> activeHiddenTags;
  final DeceptionState deceptionState;
  final ActorCue actorCue;
  final bool deceptionSprung;
  final String? deceptionResolution;

  const CharacterizedTurnResult({
    required this.appliedDelta,
    required this.metrics,
    required this.resonance,
    required this.activeHiddenTags,
    required this.deceptionState,
    required this.actorCue,
    required this.deceptionSprung,
    required this.deceptionResolution,
  });

  factory CharacterizedTurnResult.fromResolution(
    EvaluatorResolution resolution,
  ) {
    return CharacterizedTurnResult(
      appliedDelta: resolution.appliedDelta,
      metrics: resolution.stateAfter.metrics,
      resonance: resolution.stateAfter.metrics.resonance,
      activeHiddenTags:
          List<String>.from(resolution.stateAfter.activeHiddenTags),
      deceptionState: resolution.stateAfter.deceptionState,
      actorCue: resolution.actorCue,
      deceptionSprung: resolution.deceptionResolutionInfo['result'] == 'sprung',
      deceptionResolution: resolution.deceptionResolution,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'appliedDelta': {
        'deltaAlert': appliedDelta.deltaAlert,
        'deltaImperative': appliedDelta.deltaImperative,
        'deltaControl': appliedDelta.deltaControl,
        'deltaDissonance': appliedDelta.deltaDissonance,
        'creativityIndex': appliedDelta.creativityIndex,
        'injectionRisk': appliedDelta.injectionRisk,
        'semanticCategory': appliedDelta.semanticCategory.name,
      },
      'metrics': {
        'alertLevel': metrics.alertLevel,
        'imperativePillar': metrics.imperativePillar,
        'controlPillar': metrics.controlPillar,
        'dissonancePillar': metrics.dissonancePillar,
        'resonance': metrics.resonance,
      },
      'resonance': resonance,
      'activeHiddenTags': List<String>.from(activeHiddenTags)..sort(),
      'deceptionState': {
        'enabled': deceptionState.enabled,
        'kind': deceptionState.kind.name,
        'phase': deceptionState.phase.name,
        'seededTurn': deceptionState.seededTurn,
        'expiresAtTurn': deceptionState.expiresAtTurn,
        'cooldownUntilTurn': deceptionState.cooldownUntilTurn,
        'deceptionEventCount': deceptionState.deceptionEventCount,
        'baitId': deceptionState.baitId,
      },
      'actorCue': {
        'semanticCategory': actorCue.semanticCategory.name,
        'appliedDeltaAlert': actorCue.appliedDeltaAlert,
        'appliedDeltaImperative': actorCue.appliedDeltaImperative,
        'appliedDeltaControl': actorCue.appliedDeltaControl,
        'appliedDeltaDissonance': actorCue.appliedDeltaDissonance,
        'creativityIndex': actorCue.creativityIndex,
        'injectionRisk': actorCue.injectionRisk,
        'resonance': actorCue.resonance,
        'alertLevel': actorCue.alertLevel,
        'imperativePillar': actorCue.imperativePillar,
        'controlPillar': actorCue.controlPillar,
        'dissonancePillar': actorCue.dissonancePillar,
        'recalculationTriggered': actorCue.recalculationTriggered,
        'safetyOverrideApplied': actorCue.safetyOverrideApplied,
        'dramaticInstruction': actorCue.dramaticInstruction,
        'actingDirectives': List<String>.from(actorCue.actingDirectives)
          ..sort(),
      },
      'deceptionSprung': deceptionSprung,
      'deceptionResolution': deceptionResolution,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CharacterizedTurnResult &&
          runtimeType == other.runtimeType &&
          _mapsEqual(toJson(), other.toJson());

  @override
  int get hashCode => toJson().toString().hashCode;

  static bool _mapsEqual(Map a, Map b) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key)) return false;
      final valA = a[key];
      final valB = b[key];
      if (valA is Map && valB is Map) {
        if (!_mapsEqual(valA, valB)) return false;
      } else if (valA is List && valB is List) {
        if (!_listsEqual(valA, valB)) return false;
      } else if (valA != valB) {
        return false;
      }
    }
    return true;
  }

  static bool _listsEqual(List a, List b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      final valA = a[i];
      final valB = b[i];
      if (valA is Map && valB is Map) {
        if (!_mapsEqual(valA, valB)) return false;
      } else if (valA is List && valB is List) {
        if (!_listsEqual(valA, valB)) return false;
      } else if (valA != valB) {
        return false;
      }
    }
    return true;
  }
}
