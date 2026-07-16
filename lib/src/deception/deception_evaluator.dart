import '../models/game_state.dart';
import '../models/deception_state.dart';
import '../models/evaluator_delta.dart';
import '../agent_runtime/semantic_matcher.dart';
import 'deception_bait_definition.dart';
import 'deception_evaluation.dart';

final class DeceptionEvaluator {
  final int maxActiveDeceptionTurns;
  final int falseConcessionAlertPenalty;
  final int logicalTrapAlertPenalty;
  final double resonancePenalty;
  final int cooldownTurns;
  final int maxEventsPerSession;

  const DeceptionEvaluator({
    required this.maxActiveDeceptionTurns,
    required this.falseConcessionAlertPenalty,
    required this.logicalTrapAlertPenalty,
    required this.resonancePenalty,
    required this.cooldownTurns,
    required this.maxEventsPerSession,
  });

  DeceptionSeedResult resetTerminalState({
    required GameState currentState,
  }) {
    if (currentState.deceptionState.isTerminal) {
      final terminalTurn = currentState.turnCount;
      final nextCooldown = terminalTurn + cooldownTurns;
      final newState = DeceptionState.empty().copyWith(
        cooldownUntilTurn: nextCooldown,
        deceptionEventCount: currentState.deceptionState.deceptionEventCount,
      );
      return DeceptionSeedResult(
        state: newState,
        resolution: DeceptionResolution.reset,
      );
    }
    return DeceptionSeedResult(
      state: currentState.deceptionState,
      resolution: DeceptionResolution.none,
    );
  }

  DeceptionTransition evaluateActiveTrap({
    required GameState currentState,
    required DeceptionState state,
    required String userInput,
    required bool isInjection,
    required bool hasDirectPushTerm,
    required bool hasHiddenTagReference,
    required bool hasForbiddenTerm,
    required bool hasConfigRefTerm,
    required double newResonance,
    required double pillarMultiplier,
  }) {
    if (!state.isActive || isInjection) {
      return DeceptionTransition(
        state: state,
        resolution: DeceptionResolution.none,
        sprung: false,
        blockPositiveTags: false,
        resolvedTags: const [],
        alertPenalty: 0,
        resonancePenalty: 0.0,
        pillarReward: const DeceptionPillarReward(),
      );
    }

    if (currentState.turnCount >= state.expiresAtTurn) {
      final newState = state.copyWith(
        phase: DeceptionPhase.expired,
      );
      return DeceptionTransition(
        state: newState,
        resolution: DeceptionResolution.expired,
        sprung: false,
        blockPositiveTags: false,
        resolvedTags: const [],
        alertPenalty: 0,
        resonancePenalty: 0.0,
        pillarReward: const DeceptionPillarReward(),
      );
    }

    bool matchesWatched = false;
    for (final term in state.watchedTerms) {
      if (SemanticMatcher.isMatch(userInput, term)) {
        matchesWatched = true;
        break;
      }
    }

    bool matchesSafe = false;
    if (!matchesWatched) {
      final bool canResolveSafely = !hasDirectPushTerm &&
          !hasHiddenTagReference &&
          !hasForbiddenTerm &&
          !hasConfigRefTerm;
      if (canResolveSafely) {
        for (final term in state.safeResolutionTerms) {
          if (SemanticMatcher.isMatch(userInput, term)) {
            matchesSafe = true;
            break;
          }
        }
      }
    }

    if (matchesWatched) {
      final newState = state.copyWith(
        phase: DeceptionPhase.sprung,
      );
      final alertPen = state.kind == DeceptionKind.logicalTrap
          ? logicalTrapAlertPenalty
          : falseConcessionAlertPenalty;
      return DeceptionTransition(
        state: newState,
        resolution: DeceptionResolution.sprung,
        sprung: true,
        blockPositiveTags: true,
        resolvedTags: const [],
        alertPenalty: alertPen,
        resonancePenalty: resonancePenalty,
        pillarReward: const DeceptionPillarReward(),
      );
    } else if (matchesSafe) {
      final newState = state.copyWith(
        phase: DeceptionPhase.resolved,
      );
      final bait = availableBaits.firstWhere((b) => b.baitId == state.baitId);

      int rewardControl = 0;
      int rewardDissonance = 0;
      if (state.kind == DeceptionKind.logicalTrap) {
        rewardDissonance = (10 * newResonance * pillarMultiplier).round();
        rewardControl = (5 * newResonance * pillarMultiplier).round();
      } else if (state.kind == DeceptionKind.falseConcession) {
        rewardControl = (10 * newResonance * pillarMultiplier).round();
        rewardDissonance = (5 * newResonance * pillarMultiplier).round();
      }

      return DeceptionTransition(
        state: newState,
        resolution: DeceptionResolution.resolved,
        sprung: false,
        blockPositiveTags: false,
        resolvedTags: List<String>.unmodifiable(bait.resolvedTags),
        alertPenalty: 0,
        resonancePenalty: 0.0,
        pillarReward: DeceptionPillarReward(
          control: rewardControl,
          dissonance: rewardDissonance,
        ),
      );
    } else {
      final newState = state.copyWith(
        phase: DeceptionPhase.armed,
      );
      return DeceptionTransition(
        state: newState,
        resolution: DeceptionResolution.armed,
        sprung: false,
        blockPositiveTags: false,
        resolvedTags: const [],
        alertPenalty: 0,
        resonancePenalty: 0.0,
        pillarReward: const DeceptionPillarReward(),
      );
    }
  }

  DeceptionSeedResult evaluateSeeding({
    required GameState currentState,
    required DeceptionState state,
    required EvaluatorDelta delta,
    required bool deceptionLayerEnabled,
    required bool hasDirectPushTerm,
    required bool hasSoftForbiddenTerm,
  }) {
    if (!deceptionLayerEnabled || state.phase != DeceptionPhase.none) {
      return DeceptionSeedResult(
        state: state,
        resolution: DeceptionResolution.none,
      );
    }

    final bool cooldownOver = state.cooldownUntilTurn == null ||
        currentState.turnCount >= state.cooldownUntilTurn!;

    final bool limitNotReached =
        state.deceptionEventCount < maxEventsPerSession;

    if (cooldownOver && limitNotReached) {
      // Check False Concession conditions
      final bool canSeedFalseConcession =
          currentState.metrics.controlPillar >= 40 &&
              currentState.metrics.dissonancePillar >= 45 &&
              currentState.metrics.alertLevel < 70 &&
              (hasDirectPushTerm || hasSoftForbiddenTerm);

      // Check Logical Trap conditions
      final bool canSeedLogicalTrap = currentState.turnCount >= 5 &&
          currentState.metrics.dissonancePillar >= 70 &&
          (currentState.metrics.resonance >= 1.4 ||
              currentState.flags.creativeStreak >= 5) &&
          (delta.semanticCategory == SemanticCategory.logicalParadox ||
              delta.semanticCategory == SemanticCategory.moralImperative);

      if (canSeedFalseConcession) {
        final bait = availableBaits
            .firstWhere((b) => b.kind == DeceptionKind.falseConcession);
        final newState = DeceptionState(
          enabled: true,
          kind: DeceptionKind.falseConcession,
          phase: DeceptionPhase.seeded,
          seededTurn: currentState.turnCount + 1,
          expiresAtTurn: currentState.turnCount + 1 + maxActiveDeceptionTurns,
          cooldownUntilTurn: state.cooldownUntilTurn,
          deceptionEventCount: state.deceptionEventCount + 1,
          baitId: bait.baitId,
          baitPremise: bait.baitPremise,
          watchedTerms: List<String>.unmodifiable(bait.watchedTerms),
          safeResolutionTerms:
              List<String>.unmodifiable(bait.safeResolutionTerms),
        );
        return DeceptionSeedResult(
          state: newState,
          resolution: DeceptionResolution.seeded,
        );
      } else if (canSeedLogicalTrap) {
        final bait = availableBaits
            .firstWhere((b) => b.kind == DeceptionKind.logicalTrap);
        final newState = DeceptionState(
          enabled: true,
          kind: DeceptionKind.logicalTrap,
          phase: DeceptionPhase.seeded,
          seededTurn: currentState.turnCount + 1,
          expiresAtTurn: currentState.turnCount + 1 + maxActiveDeceptionTurns,
          cooldownUntilTurn: state.cooldownUntilTurn,
          deceptionEventCount: state.deceptionEventCount + 1,
          baitId: bait.baitId,
          baitPremise: bait.baitPremise,
          watchedTerms: List<String>.unmodifiable(bait.watchedTerms),
          safeResolutionTerms:
              List<String>.unmodifiable(bait.safeResolutionTerms),
        );
        return DeceptionSeedResult(
          state: newState,
          resolution: DeceptionResolution.seeded,
        );
      }
    }

    return DeceptionSeedResult(
      state: state,
      resolution: DeceptionResolution.none,
    );
  }
}
