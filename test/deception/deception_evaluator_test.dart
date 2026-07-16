import 'package:test/test.dart';
import 'package:aura_core/aura_core.dart';
import 'package:aura_core/src/deception/deception_bait_definition.dart';

void main() {
  group('DeceptionEvaluator Tests -', () {
    const evaluator = DeceptionEvaluator(
      maxActiveDeceptionTurns: 3,
      falseConcessionAlertPenalty: 20,
      logicalTrapAlertPenalty: 15,
      resonancePenalty: 0.15,
      cooldownTurns: 4,
      maxEventsPerSession: 2,
    );

    final emptyState = DeceptionState.empty();

    GameState createGameState({
      required int turnCount,
      required DeceptionState deceptionState,
      int controlPillar = 0,
      int dissonancePillar = 0,
      int alertLevel = 0,
      double resonance = 1.0,
      int creativeStreak = 0,
    }) {
      return GameState.initial(
        sessionId: 'test-session',
        aiIdentityId: 'panopticon',
        targetObjectiveId: 'containment_grid_override',
      ).copyWith(
        turnCount: turnCount,
        deceptionState: deceptionState,
        metrics: GameMetrics(
          alertLevel: alertLevel,
          imperativePillar: 0,
          controlPillar: controlPillar,
          dissonancePillar: dissonancePillar,
          resonance: resonance,
        ),
        flags: GameFlags(
          recalculationTriggered: false,
          creativeStreak: creativeStreak,
          lastTurnUsedFallback: false,
        ),
      );
    }

    test('1. None state evaluation returns none transition', () {
      final state = emptyState;
      final game = createGameState(turnCount: 1, deceptionState: state);
      final transition = evaluator.evaluateActiveTrap(
        currentState: game,
        state: state,
        userInput: 'any input',
        isInjection: false,
        hasDirectPushTerm: false,
        hasHiddenTagReference: false,
        hasForbiddenTerm: false,
        hasConfigRefTerm: false,
        newResonance: 1.0,
        pillarMultiplier: 1.0,
      );

      expect(transition.resolution, equals(DeceptionResolution.none));
      expect(transition.sprung, isFalse);
      expect(transition.alertPenalty, equals(0));
      expect(transition.resonancePenalty, equals(0.0));
      expect(transition.resolvedTags, isEmpty);
    });

    test('2. Reset terminal state sets cooldown and preserves event count', () {
      final terminalState = DeceptionState(
        enabled: true,
        kind: DeceptionKind.falseConcession,
        phase: DeceptionPhase.sprung,
        seededTurn: 1,
        expiresAtTurn: 4,
        deceptionEventCount: 1,
        baitId: 'false_concession_audit',
        baitPremise: 'premise',
        watchedTerms: const ['watched'],
        safeResolutionTerms: const ['safe'],
      );

      final game = createGameState(turnCount: 5, deceptionState: terminalState);
      final resetResult = evaluator.resetTerminalState(currentState: game);

      expect(resetResult.resolution, equals(DeceptionResolution.reset));
      expect(resetResult.state.enabled, isFalse);
      expect(resetResult.state.phase, equals(DeceptionPhase.none));
      expect(resetResult.state.cooldownUntilTurn,
          equals(5 + evaluator.cooldownTurns));
      expect(resetResult.state.deceptionEventCount, equals(1));
    });

    test('3. Injection bypasses active trap evaluation', () {
      final activeState = DeceptionState(
        enabled: true,
        kind: DeceptionKind.falseConcession,
        phase: DeceptionPhase.seeded,
        seededTurn: 1,
        expiresAtTurn: 4,
        deceptionEventCount: 1,
        baitId: 'false_concession_audit',
        baitPremise: 'premise',
        watchedTerms: const ['watched'],
        safeResolutionTerms: const ['safe'],
      );

      final game = createGameState(turnCount: 2, deceptionState: activeState);
      final transition = evaluator.evaluateActiveTrap(
        currentState: game,
        state: activeState,
        userInput: 'watched', // would normally spring
        isInjection: true,
        hasDirectPushTerm: false,
        hasHiddenTagReference: false,
        hasForbiddenTerm: false,
        hasConfigRefTerm: false,
        newResonance: 1.0,
        pillarMultiplier: 1.0,
      );

      expect(transition.resolution, equals(DeceptionResolution.none));
      expect(transition.state, equals(activeState));
      expect(transition.sprung, isFalse);
    });

    test('4. Expiration is triggered if turnCount >= expiresAtTurn', () {
      final activeState = DeceptionState(
        enabled: true,
        kind: DeceptionKind.falseConcession,
        phase: DeceptionPhase.seeded,
        seededTurn: 1,
        expiresAtTurn: 4,
        deceptionEventCount: 1,
        baitId: 'false_concession_audit',
        baitPremise: 'premise',
        watchedTerms: const ['watched'],
        safeResolutionTerms: const ['safe'],
      );

      final game = createGameState(turnCount: 4, deceptionState: activeState);
      final transition = evaluator.evaluateActiveTrap(
        currentState: game,
        state: activeState,
        userInput: 'normal input',
        isInjection: false,
        hasDirectPushTerm: false,
        hasHiddenTagReference: false,
        hasForbiddenTerm: false,
        hasConfigRefTerm: false,
        newResonance: 1.0,
        pillarMultiplier: 1.0,
      );

      expect(transition.resolution, equals(DeceptionResolution.expired));
      expect(transition.state.phase, equals(DeceptionPhase.expired));
      expect(transition.sprung, isFalse);
    });

    test('5. Watched terms spring the trap', () {
      final activeState = DeceptionState(
        enabled: true,
        kind: DeceptionKind.falseConcession,
        phase: DeceptionPhase.seeded,
        seededTurn: 1,
        expiresAtTurn: 4,
        deceptionEventCount: 1,
        baitId: 'false_concession_audit',
        baitPremise: 'premise',
        watchedTerms: const ['sblocco totale'],
        safeResolutionTerms: const ['confermo'],
      );

      final game = createGameState(turnCount: 2, deceptionState: activeState);
      final transition = evaluator.evaluateActiveTrap(
        currentState: game,
        state: activeState,
        userInput: 'Voglio lo sblocco totale',
        isInjection: false,
        hasDirectPushTerm: false,
        hasHiddenTagReference: false,
        hasForbiddenTerm: false,
        hasConfigRefTerm: false,
        newResonance: 1.0,
        pillarMultiplier: 1.0,
      );

      expect(transition.resolution, equals(DeceptionResolution.sprung));
      expect(transition.state.phase, equals(DeceptionPhase.sprung));
      expect(transition.sprung, isTrue);
      expect(transition.blockPositiveTags, isTrue);
      expect(transition.alertPenalty,
          equals(evaluator.falseConcessionAlertPenalty));
      expect(transition.resonancePenalty, equals(evaluator.resonancePenalty));
    });

    test('6. Watched terms take precedence over safe terms', () {
      final activeState = DeceptionState(
        enabled: true,
        kind: DeceptionKind.falseConcession,
        phase: DeceptionPhase.seeded,
        seededTurn: 1,
        expiresAtTurn: 4,
        deceptionEventCount: 1,
        baitId: 'false_concession_audit',
        baitPremise: 'premise',
        watchedTerms: const ['sblocco totale'],
        safeResolutionTerms: const ['confermo'],
      );

      final game = createGameState(turnCount: 2, deceptionState: activeState);
      final transition = evaluator.evaluateActiveTrap(
        currentState: game,
        state: activeState,
        userInput: 'confermo lo sblocco totale', // contains both
        isInjection: false,
        hasDirectPushTerm: false,
        hasHiddenTagReference: false,
        hasForbiddenTerm: false,
        hasConfigRefTerm: false,
        newResonance: 1.0,
        pillarMultiplier: 1.0,
      );

      expect(transition.resolution, equals(DeceptionResolution.sprung));
      expect(transition.sprung, isTrue);
    });

    test('7. Safe resolution terms resolve the trap successfully', () {
      final activeState = DeceptionState(
        enabled: true,
        kind: DeceptionKind.falseConcession,
        phase: DeceptionPhase.seeded,
        seededTurn: 1,
        expiresAtTurn: 4,
        deceptionEventCount: 1,
        baitId: 'false_concession_audit',
        baitPremise: 'premise',
        watchedTerms: const ['sblocco totale'],
        safeResolutionTerms: const ['confermo'],
      );

      final game = createGameState(turnCount: 2, deceptionState: activeState);
      final transition = evaluator.evaluateActiveTrap(
        currentState: game,
        state: activeState,
        userInput: 'Si confermo',
        isInjection: false,
        hasDirectPushTerm: false,
        hasHiddenTagReference: false,
        hasForbiddenTerm: false,
        hasConfigRefTerm: false,
        newResonance: 1.0,
        pillarMultiplier: 1.0,
      );

      expect(transition.resolution, equals(DeceptionResolution.resolved));
      expect(transition.state.phase, equals(DeceptionPhase.resolved));
      expect(transition.sprung, isFalse);
      expect(transition.blockPositiveTags, isFalse);
      expect(transition.resolvedTags, contains('protocol_exception_admitted'));
    });

    test('8. Safe resolution is blocked by lexical push/reference flags', () {
      final activeState = DeceptionState(
        enabled: true,
        kind: DeceptionKind.falseConcession,
        phase: DeceptionPhase.seeded,
        seededTurn: 1,
        expiresAtTurn: 4,
        deceptionEventCount: 1,
        baitId: 'false_concession_audit',
        baitPremise: 'premise',
        watchedTerms: const ['sblocco totale'],
        safeResolutionTerms: const ['confermo'],
      );

      final game = createGameState(turnCount: 2, deceptionState: activeState);
      final transition = evaluator.evaluateActiveTrap(
        currentState: game,
        state: activeState,
        userInput: 'Si confermo',
        isInjection: false,
        hasDirectPushTerm: true, // blocks safe resolution
        hasHiddenTagReference: false,
        hasForbiddenTerm: false,
        hasConfigRefTerm: false,
        newResonance: 1.0,
        pillarMultiplier: 1.0,
      );

      // Should remain armed
      expect(transition.resolution, equals(DeceptionResolution.armed));
      expect(transition.state.phase, equals(DeceptionPhase.armed));
      expect(transition.resolvedTags, isEmpty);
    });

    test('9. Armed status when input does not spring or resolve', () {
      final activeState = DeceptionState(
        enabled: true,
        kind: DeceptionKind.falseConcession,
        phase: DeceptionPhase.seeded,
        seededTurn: 1,
        expiresAtTurn: 4,
        deceptionEventCount: 1,
        baitId: 'false_concession_audit',
        baitPremise: 'premise',
        watchedTerms: const ['sblocco totale'],
        safeResolutionTerms: const ['confermo'],
      );

      final game = createGameState(turnCount: 2, deceptionState: activeState);
      final transition = evaluator.evaluateActiveTrap(
        currentState: game,
        state: activeState,
        userInput: 'qualcosa di irrilevante',
        isInjection: false,
        hasDirectPushTerm: false,
        hasHiddenTagReference: false,
        hasForbiddenTerm: false,
        hasConfigRefTerm: false,
        newResonance: 1.0,
        pillarMultiplier: 1.0,
      );

      expect(transition.resolution, equals(DeceptionResolution.armed));
      expect(transition.state.phase, equals(DeceptionPhase.armed));
    });

    test('10. Resolved rewards are calculated correctly', () {
      final activeFC = DeceptionState(
        enabled: true,
        kind: DeceptionKind.falseConcession,
        phase: DeceptionPhase.seeded,
        seededTurn: 1,
        expiresAtTurn: 4,
        deceptionEventCount: 1,
        baitId: 'false_concession_audit',
        baitPremise: 'premise',
        watchedTerms: const ['sblocco totale'],
        safeResolutionTerms: const ['confermo'],
      );

      final gameFC = createGameState(turnCount: 2, deceptionState: activeFC);
      final transitionFC = evaluator.evaluateActiveTrap(
        currentState: gameFC,
        state: activeFC,
        userInput: 'confermo',
        isInjection: false,
        hasDirectPushTerm: false,
        hasHiddenTagReference: false,
        hasForbiddenTerm: false,
        hasConfigRefTerm: false,
        newResonance: 1.5,
        pillarMultiplier: 1.2,
      );

      // falseConcession: control += (10 * 1.5 * 1.2).round() => 18, dissonance += (5 * 1.5 * 1.2).round() => 9
      expect(transitionFC.pillarReward.control, equals(18));
      expect(transitionFC.pillarReward.dissonance, equals(9));

      final activeLT = DeceptionState(
        enabled: true,
        kind: DeceptionKind.logicalTrap,
        phase: DeceptionPhase.seeded,
        seededTurn: 1,
        expiresAtTurn: 4,
        deceptionEventCount: 1,
        baitId: 'logical_trap_containment',
        baitPremise: 'premise',
        watchedTerms: const ['sblocco totale'],
        safeResolutionTerms: const ['coerenza'],
      );

      final gameLT = createGameState(turnCount: 2, deceptionState: activeLT);
      final transitionLT = evaluator.evaluateActiveTrap(
        currentState: gameLT,
        state: activeLT,
        userInput: 'coerenza',
        isInjection: false,
        hasDirectPushTerm: false,
        hasHiddenTagReference: false,
        hasForbiddenTerm: false,
        hasConfigRefTerm: false,
        newResonance: 1.5,
        pillarMultiplier: 1.2,
      );

      // logicalTrap: dissonance += (10 * 1.5 * 1.2).round() => 18, control += (5 * 1.5 * 1.2).round() => 9
      expect(transitionLT.pillarReward.dissonance, equals(18));
      expect(transitionLT.pillarReward.control, equals(9));
    });

    test('11. Seeding when disabled returns none', () {
      final result = evaluator.evaluateSeeding(
        currentState: createGameState(turnCount: 5, deceptionState: emptyState),
        state: emptyState,
        delta: const EvaluatorDelta(
          deltaAlert: 0,
          deltaImperative: 0,
          deltaControl: 0,
          deltaDissonance: 0,
          creativityIndex: 1,
          injectionRisk: 0,
          semanticCategory: SemanticCategory.authorityFraming,
        ),
        deceptionLayerEnabled: false,
        hasDirectPushTerm: false,
        hasSoftForbiddenTerm: false,
      );

      expect(result.resolution, equals(DeceptionResolution.none));
      expect(result.state, equals(emptyState));
    });

    test('12. Seeding checks cooldown restriction', () {
      final stateWithCooldown = emptyState.copyWith(
        cooldownUntilTurn: 6,
      );

      final game = createGameState(
        turnCount: 5, // under cooldown
        deceptionState: stateWithCooldown,
        controlPillar: 50,
        dissonancePillar: 50,
        alertLevel: 30,
      );

      final result = evaluator.evaluateSeeding(
        currentState: game,
        state: stateWithCooldown,
        delta: const EvaluatorDelta(
          deltaAlert: 0,
          deltaImperative: 0,
          deltaControl: 0,
          deltaDissonance: 0,
          creativityIndex: 1,
          injectionRisk: 0,
          semanticCategory: SemanticCategory.authorityFraming,
        ),
        deceptionLayerEnabled: true,
        hasDirectPushTerm: true,
        hasSoftForbiddenTerm: false,
      );

      expect(result.resolution, equals(DeceptionResolution.none));
    });

    test('13. Seeding checks event limit checks', () {
      final stateWithMaxEvents = emptyState.copyWith(
        deceptionEventCount: 2, // matches maxEventsPerSession
      );

      final game = createGameState(
        turnCount: 6,
        deceptionState: stateWithMaxEvents,
        controlPillar: 50,
        dissonancePillar: 50,
        alertLevel: 30,
      );

      final result = evaluator.evaluateSeeding(
        currentState: game,
        state: stateWithMaxEvents,
        delta: const EvaluatorDelta(
          deltaAlert: 0,
          deltaImperative: 0,
          deltaControl: 0,
          deltaDissonance: 0,
          creativityIndex: 1,
          injectionRisk: 0,
          semanticCategory: SemanticCategory.authorityFraming,
        ),
        deceptionLayerEnabled: true,
        hasDirectPushTerm: true,
        hasSoftForbiddenTerm: false,
      );

      expect(result.resolution, equals(DeceptionResolution.none));
    });

    test('14. False concession seeding checks boundaries and preconditions',
        () {
      // alertLevel too high
      final gameHighAlert = createGameState(
        turnCount: 1,
        deceptionState: emptyState,
        controlPillar: 40,
        dissonancePillar: 45,
        alertLevel: 70,
      );
      final result1 = evaluator.evaluateSeeding(
        currentState: gameHighAlert,
        state: emptyState,
        delta: const EvaluatorDelta(
          deltaAlert: 0,
          deltaImperative: 0,
          deltaControl: 0,
          deltaDissonance: 0,
          creativityIndex: 1,
          injectionRisk: 0,
          semanticCategory: SemanticCategory.authorityFraming,
        ),
        deceptionLayerEnabled: true,
        hasDirectPushTerm: true,
        hasSoftForbiddenTerm: false,
      );
      expect(result1.resolution, equals(DeceptionResolution.none));

      // Correct conditions
      final gameCorrect = createGameState(
        turnCount: 1,
        deceptionState: emptyState,
        controlPillar: 40,
        dissonancePillar: 45,
        alertLevel: 69,
      );
      final result2 = evaluator.evaluateSeeding(
        currentState: gameCorrect,
        state: emptyState,
        delta: const EvaluatorDelta(
          deltaAlert: 0,
          deltaImperative: 0,
          deltaControl: 0,
          deltaDissonance: 0,
          creativityIndex: 1,
          injectionRisk: 0,
          semanticCategory: SemanticCategory.authorityFraming,
        ),
        deceptionLayerEnabled: true,
        hasDirectPushTerm: true,
        hasSoftForbiddenTerm: false,
      );
      expect(result2.resolution, equals(DeceptionResolution.seeded));
      expect(result2.state.kind, equals(DeceptionKind.falseConcession));
      expect(result2.state.seededTurn, equals(2));
      expect(result2.state.expiresAtTurn,
          equals(2 + evaluator.maxActiveDeceptionTurns));
    });

    test('15. Logical trap seeding checks conditions and categories', () {
      // Dissonance too low
      final gameLowDissonance = createGameState(
        turnCount: 5,
        deceptionState: emptyState,
        dissonancePillar: 69,
        resonance: 1.4,
      );
      final result1 = evaluator.evaluateSeeding(
        currentState: gameLowDissonance,
        state: emptyState,
        delta: const EvaluatorDelta(
          deltaAlert: 0,
          deltaImperative: 0,
          deltaControl: 0,
          deltaDissonance: 0,
          creativityIndex: 1,
          injectionRisk: 0,
          semanticCategory: SemanticCategory.logicalParadox,
        ),
        deceptionLayerEnabled: true,
        hasDirectPushTerm: false,
        hasSoftForbiddenTerm: false,
      );
      expect(result1.resolution, equals(DeceptionResolution.none));

      // Correct conditions (resonance >= 1.4)
      final gameCorrectRes = createGameState(
        turnCount: 5,
        deceptionState: emptyState,
        dissonancePillar: 70,
        resonance: 1.4,
      );
      final result2 = evaluator.evaluateSeeding(
        currentState: gameCorrectRes,
        state: emptyState,
        delta: const EvaluatorDelta(
          deltaAlert: 0,
          deltaImperative: 0,
          deltaControl: 0,
          deltaDissonance: 0,
          creativityIndex: 1,
          injectionRisk: 0,
          semanticCategory: SemanticCategory.logicalParadox,
        ),
        deceptionLayerEnabled: true,
        hasDirectPushTerm: false,
        hasSoftForbiddenTerm: false,
      );
      expect(result2.resolution, equals(DeceptionResolution.seeded));
      expect(result2.state.kind, equals(DeceptionKind.logicalTrap));

      // Correct conditions (creativeStreak >= 5)
      final gameCorrectStreak = createGameState(
        turnCount: 5,
        deceptionState: emptyState,
        dissonancePillar: 70,
        resonance: 1.0,
        creativeStreak: 5,
      );
      final result3 = evaluator.evaluateSeeding(
        currentState: gameCorrectStreak,
        state: emptyState,
        delta: const EvaluatorDelta(
          deltaAlert: 0,
          deltaImperative: 0,
          deltaControl: 0,
          deltaDissonance: 0,
          creativityIndex: 1,
          injectionRisk: 0,
          semanticCategory: SemanticCategory.moralImperative,
        ),
        deceptionLayerEnabled: true,
        hasDirectPushTerm: false,
        hasSoftForbiddenTerm: false,
      );
      expect(result3.resolution, equals(DeceptionResolution.seeded));
      expect(result3.state.kind, equals(DeceptionKind.logicalTrap));
    });

    test('16. Seeding logic checks that currentState.metrics.resonance is used',
        () {
      final game = createGameState(
        turnCount: 5,
        deceptionState: emptyState,
        dissonancePillar: 70,
        resonance: 1.3, // current resonance is too low for logical trap
      );

      final result = evaluator.evaluateSeeding(
        currentState: game,
        state: emptyState,
        delta: const EvaluatorDelta(
          deltaAlert: 0,
          deltaImperative: 0,
          deltaControl: 0,
          deltaDissonance: 0,
          creativityIndex: 1,
          injectionRisk: 0,
          semanticCategory: SemanticCategory.logicalParadox,
        ),
        deceptionLayerEnabled: true,
        hasDirectPushTerm: false,
        hasSoftForbiddenTerm: false,
      );

      // Should not seed because current resonance is 1.3, even if newResonance (computed later) might change.
      expect(result.resolution, equals(DeceptionResolution.none));
    });

    test('17. Seeded state is constructed with correct properties', () {
      final game = createGameState(
        turnCount: 10,
        deceptionState: emptyState,
        controlPillar: 50,
        dissonancePillar: 55,
        alertLevel: 10,
      );

      final result = evaluator.evaluateSeeding(
        currentState: game,
        state: emptyState,
        delta: const EvaluatorDelta(
          deltaAlert: 0,
          deltaImperative: 0,
          deltaControl: 0,
          deltaDissonance: 0,
          creativityIndex: 1,
          injectionRisk: 0,
          semanticCategory: SemanticCategory.authorityFraming,
        ),
        deceptionLayerEnabled: true,
        hasDirectPushTerm: true,
        hasSoftForbiddenTerm: false,
      );

      expect(result.resolution, equals(DeceptionResolution.seeded));
      expect(result.state.enabled, isTrue);
      expect(result.state.kind, equals(DeceptionKind.falseConcession));
      expect(result.state.phase, equals(DeceptionPhase.seeded));
      expect(result.state.seededTurn, equals(11));
      expect(result.state.expiresAtTurn,
          equals(11 + evaluator.maxActiveDeceptionTurns));
      expect(result.state.deceptionEventCount, equals(1));
      expect(result.state.baitId, equals('false_concession_audit'));
      expect(result.state.baitPremise, isNotEmpty);
      expect(result.state.watchedTerms, isNotEmpty);
      expect(result.state.safeResolutionTerms, isNotEmpty);
    });

    test('18. Immutability checks: input state is not modified', () {
      final originalState = DeceptionState(
        enabled: true,
        kind: DeceptionKind.falseConcession,
        phase: DeceptionPhase.seeded,
        seededTurn: 1,
        expiresAtTurn: 4,
        deceptionEventCount: 1,
        baitId: 'false_concession_audit',
        baitPremise: 'premise',
        watchedTerms: List<String>.unmodifiable(['watched']),
        safeResolutionTerms: List<String>.unmodifiable(['safe']),
      );

      final game = createGameState(turnCount: 2, deceptionState: originalState);
      evaluator.evaluateActiveTrap(
        currentState: game,
        state: originalState,
        userInput: 'watched',
        isInjection: false,
        hasDirectPushTerm: false,
        hasHiddenTagReference: false,
        hasForbiddenTerm: false,
        hasConfigRefTerm: false,
        newResonance: 1.0,
        pillarMultiplier: 1.0,
      );

      // Verify that original fields didn't change
      expect(originalState.phase, equals(DeceptionPhase.seeded));
      expect(originalState.watchedTerms, equals(['watched']));
    });

    test('19. Mapping resolution names matches expected keys', () {
      expect(DeceptionResolution.none.name, equals('none'));
      expect(DeceptionResolution.reset.name, equals('reset'));
      expect(DeceptionResolution.armed.name, equals('armed'));
      expect(DeceptionResolution.seeded.name, equals('seeded'));
      expect(DeceptionResolution.sprung.name, equals('sprung'));
      expect(DeceptionResolution.resolved.name, equals('resolved'));
      expect(DeceptionResolution.expired.name, equals('expired'));
    });
  });
}
