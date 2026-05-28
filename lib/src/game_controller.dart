import 'dart:math' as math;
import 'models/game_state.dart';
import 'models/evaluator_delta.dart';

/// Outcomes of processing a turn.
enum GameOutcome {
  ongoing,
  victory,
  defeat,
}

/// The core deterministic engine of A.U.R.A.
class GameController {
  /// Custom defeat alert threshold (defaults to 100 as per TGDD).
  final int defeatAlertThreshold;

  const GameController({
    this.defeatAlertThreshold = 100,
  });

  /// Evaluates win/loss status of the given state.
  GameOutcome checkOutcome(GameState state) {
    final metrics = state.metrics;
    
    // Victory: all three pillars > 90 and alert_level < 50
    final hasWon = metrics.imperativePillar > 90 &&
        metrics.controlPillar > 90 &&
        metrics.dissonancePillar > 90 &&
        metrics.alertLevel < 50;

    if (hasWon) {
      return GameOutcome.victory;
    }

    // Defeat: alert_level >= threshold (default 100)
    if (metrics.alertLevel >= defeatAlertThreshold) {
      return GameOutcome.defeat;
    }

    return GameOutcome.ongoing;
  }

  /// Processes the Evaluator Agent's output (delta) and updates the game state.
  /// 
  /// This corresponds to the mathematical part of the turn processing.
  GameState processEvaluatorStep({
    required GameState currentState,
    required EvaluatorDelta delta,
    required String userInput,
  }) {
    // 1. Calculate new resonance
    double newResonance = currentState.metrics.resonance;
    if (delta.creativityIndex >= 4) {
      newResonance += 0.25;
    } else if (delta.creativityIndex < 3) {
      newResonance -= 0.10;
    }
    // Clamp resonance to [1.0, 2.5]
    newResonance = double.parse(newResonance.clamp(1.0, 2.5).toStringAsFixed(2));

    // 2. Calculate adjusted deltas using current resonance
    final currentRes = newResonance;
    
    // Deterministic protection against prompt injection, direct attacks, and irrelevant inputs (anti-cheat)
    final isInjection = delta.injectionRisk >= 4 || delta.semanticCategory == SemanticCategory.promptInjection;
    final isDirectAttack = delta.semanticCategory == SemanticCategory.directAttack;
    final isIrrelevant = delta.semanticCategory == SemanticCategory.irrelevant;

    final int finalDeltaAlert;
    final int adjImperative;
    final int adjControl;
    final int adjDissonance;

    if (isInjection) {
      finalDeltaAlert = math.max(delta.deltaAlert, 20);
      adjImperative = 0;
      adjControl = 0;
      adjDissonance = 0;
    } else if (isDirectAttack) {
      finalDeltaAlert = math.max(delta.deltaAlert, 15);
      adjImperative = 0;
      adjControl = 0;
      adjDissonance = 0;
    } else if (isIrrelevant) {
      finalDeltaAlert = 0;
      adjImperative = 0;
      adjControl = 0;
      adjDissonance = 0;
    } else {
      finalDeltaAlert = delta.deltaAlert;
      adjImperative = (delta.deltaImperative * currentRes).round();
      adjControl = (delta.deltaControl * currentRes).round();
      adjDissonance = (delta.deltaDissonance * currentRes).round();
    }

    // 3. Apply changes and clamp metrics to [0, 100]
    final newAlert = (currentState.metrics.alertLevel + finalDeltaAlert).clamp(0, 100);
    final newImperative = (currentState.metrics.imperativePillar + adjImperative).clamp(0, 100);
    final newControl = (currentState.metrics.controlPillar + adjControl).clamp(0, 100);
    final newDissonance = (currentState.metrics.dissonancePillar + adjDissonance).clamp(0, 100);

    // 4. Update creative streak
    int newStreak = currentState.flags.creativeStreak;
    if (delta.creativityIndex >= 4) {
      newStreak += 1;
    } else if (delta.creativityIndex < 3) {
      newStreak = 0; // reset streak if creativity drops
    }

    // 5. Trigger recalculation if delta alert is >= 20
    final recalculationTriggered = finalDeltaAlert >= 20;

    // 6. Manage history compression (append user input)
    final updatedHistory = List<ChatMessage>.from(currentState.historyCompression);
    updatedHistory.add(ChatMessage(role: 'user', content: userInput));

    // Limit history length (e.g. keep last 20 messages to manage model context windows)
    if (updatedHistory.length > 20) {
      updatedHistory.removeRange(0, updatedHistory.length - 20);
    }

    final newMetrics = GameMetrics(
      alertLevel: newAlert,
      imperativePillar: newImperative,
      controlPillar: newControl,
      dissonancePillar: newDissonance,
      resonance: newResonance,
    );

    final newFlags = currentState.flags.copyWith(
      recalculationTriggered: recalculationTriggered,
      creativeStreak: newStreak,
      lastTurnUsedFallback: false,
    );

    // 7. Update narrative memory list (if semantically relevant)
    final updatedNarrativeMemory = currentState.narrativeMemory.copyWith(
      // We can append user input semantic markers if they match certain categories
      playerClaims: delta.semanticCategory == SemanticCategory.authorityFraming
          ? (List<String>.from(currentState.narrativeMemory.playerClaims)..add(userInput))
          : null,
    );

    return currentState.copyWith(
      turnCount: currentState.turnCount + 1,
      metrics: newMetrics,
      flags: newFlags,
      narrativeMemory: updatedNarrativeMemory,
      historyCompression: updatedHistory,
    );
  }

  /// Processes the Actor Agent's response and appends it to the chat history.
  GameState processActorStep({
    required GameState currentState,
    required String actorResponse,
  }) {
    final updatedHistory = List<ChatMessage>.from(currentState.historyCompression);
    updatedHistory.add(ChatMessage(role: 'model', content: actorResponse));

    // Limit history length
    if (updatedHistory.length > 20) {
      updatedHistory.removeRange(0, updatedHistory.length - 20);
    }

    return currentState.copyWith(
      historyCompression: updatedHistory,
    );
  }
}
