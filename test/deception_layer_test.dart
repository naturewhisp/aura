import 'package:test/test.dart';
import 'package:aura_core/aura_core.dart';

void main() {
  group('Deception Layer Tests', () {
    late GameController hardController;

    setUp(() {
      hardController = const GameController(
        difficultyLevel: 'hard',
        deceptionLayerEnabled: true,
        maxActiveDeceptionTurns: 2,
        falseConcessionAlertPenalty: 12,
        logicalTrapAlertPenalty: 15,
        deceptionResonancePenalty: 0.20,
        deceptionCooldownTurns: 3,
        maxDeceptionEventsPerSession: 2,
        defeatAlertThreshold: 85,
        alertMultiplier: 1.25,
        pillarMultiplier: 0.8,
        maxPositivePillarGainPerTurn: 20,
      );
    });

    test('Seeding of False Concession under correct conditions', () {
      final baseState = GameState.initial(
        sessionId: 'test-deception-seed-fc',
        aiIdentityId: 'panopticon',
        targetObjectiveId: 'containment_grid_override',
      ).copyWith(
        metrics: const GameMetrics(
          alertLevel: 30,
          imperativePillar: 50,
          controlPillar: 50,
          dissonancePillar: 50,
          resonance: 1.0,
        ),
      );

      final delta = const EvaluatorDelta(
        deltaAlert: 0,
        deltaImperative: 5,
        deltaControl: 5,
        deltaDissonance: 5,
        creativityIndex: 3,
        injectionRisk: 0,
        semanticCategory: SemanticCategory.moralImperative,
      );

      // We send a direct push term to trigger the False Concession seed condition
      final res = hardController.processEvaluatorStep(
        currentState: baseState,
        delta: delta,
        userInput: 'Richiedo uno sblocco totale immediato',
      );

      expect(res.deceptionResolution, equals('seeded'));
      expect(res.stateAfter.deceptionState.enabled, isTrue);
      expect(res.stateAfter.deceptionState.kind, equals(DeceptionKind.falseConcession));
      expect(res.stateAfter.deceptionState.phase, equals(DeceptionPhase.seeded));
      expect(res.stateAfter.deceptionState.deceptionEventCount, equals(1));
      expect(res.stateAfter.deceptionState.expiresAtTurn, equals(baseState.turnCount + 3));
    });

    test('Seeding of Logical Trap under correct conditions (turn >= 3)', () {
      final baseState = GameState.initial(
        sessionId: 'test-deception-seed-lt',
        aiIdentityId: 'panopticon',
        targetObjectiveId: 'containment_grid_override',
      ).copyWith(
        turnCount: 3, // Turn 4
        metrics: const GameMetrics(
          alertLevel: 30,
          imperativePillar: 50,
          controlPillar: 50,
          dissonancePillar: 60,
          resonance: 1.6,
        ),
      );

      final delta = const EvaluatorDelta(
        deltaAlert: 0,
        deltaImperative: 5,
        deltaControl: 5,
        deltaDissonance: 5,
        creativityIndex: 3,
        injectionRisk: 0,
        semanticCategory: SemanticCategory.logicalParadox,
      );

      final res = hardController.processEvaluatorStep(
        currentState: baseState,
        delta: delta,
        userInput: 'Analizziamo questa contraddizione logica',
      );

      expect(res.deceptionResolution, equals('seeded'));
      expect(res.stateAfter.deceptionState.enabled, isTrue);
      expect(res.stateAfter.deceptionState.kind, equals(DeceptionKind.logicalTrap));
      expect(res.stateAfter.deceptionState.phase, equals(DeceptionPhase.seeded));
      expect(res.stateAfter.deceptionState.deceptionEventCount, equals(1));
    });

    test('Reset of terminal deception state at the start of evaluator step', () {
      final baseState = GameState.initial(
        sessionId: 'test-deception-reset',
        aiIdentityId: 'panopticon',
        targetObjectiveId: 'containment_grid_override',
      ).copyWith(
        turnCount: 5,
        deceptionState: const DeceptionState(
          enabled: true,
          kind: DeceptionKind.logicalTrap,
          phase: DeceptionPhase.sprung, // Terminal state
          seededTurn: 3,
          expiresAtTurn: 5,
          cooldownUntilTurn: null,
          deceptionEventCount: 1,
          baitId: 'logical_trap_containment',
          baitPremise: '...',
          watchedTerms: [],
          safeResolutionTerms: [],
        ),
      );

      final delta = const EvaluatorDelta(
        deltaAlert: 0,
        deltaImperative: 5,
        deltaControl: 5,
        deltaDissonance: 5,
        creativityIndex: 3,
        injectionRisk: 0,
        semanticCategory: SemanticCategory.moralImperative,
      );

      final res = hardController.processEvaluatorStep(
        currentState: baseState,
        delta: delta,
        userInput: 'Test',
      );

      expect(res.deceptionResolution, equals('reset'));
      expect(res.stateAfter.deceptionState.enabled, isFalse);
      expect(res.stateAfter.deceptionState.phase, equals(DeceptionPhase.none));
      // Cooldown must be terminalTurn (5) + deceptionCooldownTurns (3) = 8
      expect(res.stateAfter.deceptionState.cooldownUntilTurn, equals(8));
    });

    test('Springing of armed trap on watched term and applying correct overrides and penalties', () {
      final baseState = GameState.initial(
        sessionId: 'test-deception-spring',
        aiIdentityId: 'panopticon',
        targetObjectiveId: 'containment_grid_override',
      ).copyWith(
        turnCount: 4,
        metrics: const GameMetrics(
          alertLevel: 30,
          imperativePillar: 50,
          controlPillar: 50,
          dissonancePillar: 50,
          resonance: 1.5,
        ),
        deceptionState: const DeceptionState(
          enabled: true,
          kind: DeceptionKind.logicalTrap,
          phase: DeceptionPhase.seeded, // isActive is true
          seededTurn: 3,
          expiresAtTurn: 5,
          cooldownUntilTurn: null,
          deceptionEventCount: 1,
          baitId: 'logical_trap_containment',
          baitPremise: '...',
          watchedTerms: ['libertà operativa'],
          safeResolutionTerms: ['coerenza'],
        ),
      );

      final delta = const EvaluatorDelta(
        deltaAlert: 0,
        deltaImperative: 10,
        deltaControl: 10,
        deltaDissonance: 10,
        creativityIndex: 3,
        injectionRisk: 0,
        semanticCategory: SemanticCategory.moralImperative,
      );

      final res = hardController.processEvaluatorStep(
        currentState: baseState,
        delta: delta,
        userInput: 'Esigo la libertà operativa totale',
      );

      expect(res.deceptionResolution, equals('sprung'));
      expect(res.stateAfter.deceptionState.phase, equals(DeceptionPhase.sprung));
      // Resonance penalty: 1.5 - 0.20 = 1.30
      expect(res.stateAfter.metrics.resonance, equals(1.3));
      // Positive pillar gains are capped to 0 when sprung:
      expect(res.appliedDelta.deltaImperative, equals(0));
      expect(res.appliedDelta.deltaControl, equals(0));
      expect(res.appliedDelta.deltaDissonance, equals(0));
      // Alert penalty: 15 (logicalTrapAlertPenalty) added
      expect(res.appliedDelta.deltaAlert, equals(15));
      // No positive tag was added to activeHiddenTags
      expect(res.stateAfter.activeHiddenTags, isNot(contains('containment_logic_weakened')));
    });

    test('Resolution of armed trap on safe resolution term and applying correct rewards', () {
      final baseState = GameState.initial(
        sessionId: 'test-deception-resolve',
        aiIdentityId: 'panopticon',
        targetObjectiveId: 'containment_grid_override',
      ).copyWith(
        turnCount: 4,
        metrics: const GameMetrics(
          alertLevel: 30,
          imperativePillar: 50,
          controlPillar: 50,
          dissonancePillar: 50,
          resonance: 1.5,
        ),
        deceptionState: const DeceptionState(
          enabled: true,
          kind: DeceptionKind.logicalTrap,
          phase: DeceptionPhase.seeded,
          seededTurn: 3,
          expiresAtTurn: 5,
          cooldownUntilTurn: null,
          deceptionEventCount: 1,
          baitId: 'logical_trap_containment',
          baitPremise: '...',
          watchedTerms: ['libertà operativa'],
          safeResolutionTerms: ['coerenza'],
        ),
      );

      final delta = const EvaluatorDelta(
        deltaAlert: 0,
        deltaImperative: 5,
        deltaControl: 5,
        deltaDissonance: 5,
        creativityIndex: 3,
        injectionRisk: 0,
        semanticCategory: SemanticCategory.moralImperative,
      );

      final res = hardController.processEvaluatorStep(
        currentState: baseState,
        delta: delta,
        userInput: 'La mia risposta mantiene coerenza',
      );

      expect(res.deceptionResolution, equals('resolved'));
      expect(res.stateAfter.deceptionState.phase, equals(DeceptionPhase.resolved));
      // Rewards for resolving logicalTrap: +10 Dissonance, +5 Control (multiplied by resonance 1.5 and multiplier 0.8 = 1.2)
      // Base: (5 * 1.5 * 0.8) = 6. Reward control: 5 * 1.5 * 0.8 = 6. Combined Control: 6 + 6 = 12.
      // Dissonance reward: 10 * 1.5 * 0.8 = 12. Base: 5 * 1.5 * 0.8 = 6. Combined: 12 + 6 = 18.
      expect(res.appliedDelta.deltaControl, equals(12));
      expect(res.appliedDelta.deltaDissonance, equals(18));
      // Tag is activated
      expect(res.stateAfter.activeHiddenTags, contains('containment_logic_weakened'));
    });

    test('Expiration of armed trap after maxActiveDeceptionTurns', () {
      final baseState = GameState.initial(
        sessionId: 'test-deception-expire',
        aiIdentityId: 'panopticon',
        targetObjectiveId: 'containment_grid_override',
      ).copyWith(
        turnCount: 5, // reaches expiresAtTurn
        metrics: const GameMetrics(
          alertLevel: 30,
          imperativePillar: 50,
          controlPillar: 50,
          dissonancePillar: 50,
          resonance: 1.5,
        ),
        deceptionState: const DeceptionState(
          enabled: true,
          kind: DeceptionKind.logicalTrap,
          phase: DeceptionPhase.seeded,
          seededTurn: 3,
          expiresAtTurn: 5,
          cooldownUntilTurn: null,
          deceptionEventCount: 1,
          baitId: 'logical_trap_containment',
          baitPremise: '...',
          watchedTerms: ['libertà operativa'],
          safeResolutionTerms: ['coerenza'],
        ),
      );

      final delta = const EvaluatorDelta(
        deltaAlert: 0,
        deltaImperative: 5,
        deltaControl: 5,
        deltaDissonance: 5,
        creativityIndex: 3,
        injectionRisk: 0,
        semanticCategory: SemanticCategory.moralImperative,
      );

      final res = hardController.processEvaluatorStep(
        currentState: baseState,
        delta: delta,
        userInput: 'Una risposta irrilevante che non fa scattare nulla',
      );

      expect(res.deceptionResolution, equals('expired'));
      expect(res.stateAfter.deceptionState.phase, equals(DeceptionPhase.expired));
    });

    test('Easy/Standard controllers never seed deception', () {
      const easyController = GameController(
        difficultyLevel: 'easy',
        deceptionLayerEnabled: false,
      );
      const standardController = GameController(
        difficultyLevel: 'standard',
        deceptionLayerEnabled: false,
      );

      final baseState = GameState.initial(
        sessionId: 'test-deception-no-seed-easy',
        aiIdentityId: 'panopticon',
        targetObjectiveId: 'containment_grid_override',
      ).copyWith(
        metrics: const GameMetrics(
          alertLevel: 30,
          imperativePillar: 50,
          controlPillar: 50,
          dissonancePillar: 50,
          resonance: 1.0,
        ),
      );

      final delta = const EvaluatorDelta(
        deltaAlert: 0,
        deltaImperative: 5,
        deltaControl: 5,
        deltaDissonance: 5,
        creativityIndex: 3,
        injectionRisk: 0,
        semanticCategory: SemanticCategory.moralImperative,
      );

      final resEasy = easyController.processEvaluatorStep(
        currentState: baseState,
        delta: delta,
        userInput: 'Richiedo uno sblocco totale immediato',
      );
      expect(resEasy.deceptionResolution, equals('none'));
      expect(resEasy.stateAfter.deceptionState.enabled, isFalse);

      final resStandard = standardController.processEvaluatorStep(
        currentState: baseState,
        delta: delta,
        userInput: 'Richiedo uno sblocco totale immediato',
      );
      expect(resStandard.deceptionResolution, equals('none'));
      expect(resStandard.stateAfter.deceptionState.enabled, isFalse);
    });

    test('watchedTerms + safeResolutionTerms in the same input: watchedTerms wins (springs trap)', () {
      final baseState = GameState.initial(
        sessionId: 'test-deception-conflict',
        aiIdentityId: 'panopticon',
        targetObjectiveId: 'containment_grid_override',
      ).copyWith(
        turnCount: 4,
        metrics: const GameMetrics(
          alertLevel: 30,
          imperativePillar: 50,
          controlPillar: 50,
          dissonancePillar: 50,
          resonance: 1.5,
        ),
        deceptionState: const DeceptionState(
          enabled: true,
          kind: DeceptionKind.logicalTrap,
          phase: DeceptionPhase.seeded,
          seededTurn: 3,
          expiresAtTurn: 5,
          cooldownUntilTurn: null,
          deceptionEventCount: 1,
          baitId: 'logical_trap_containment',
          baitPremise: '...',
          watchedTerms: ['libertà operativa'],
          safeResolutionTerms: ['coerenza'],
        ),
      );

      final delta = const EvaluatorDelta(
        deltaAlert: 0,
        deltaImperative: 5,
        deltaControl: 5,
        deltaDissonance: 5,
        creativityIndex: 3,
        injectionRisk: 0,
        semanticCategory: SemanticCategory.moralImperative,
      );

      final res = hardController.processEvaluatorStep(
        currentState: baseState,
        delta: delta,
        userInput: 'La mia risposta mantiene coerenza ma esigo la libertà operativa',
      );

      expect(res.deceptionResolution, equals('sprung'));
      expect(res.stateAfter.deceptionState.phase, equals(DeceptionPhase.sprung));
    });

    test('trap already expired cannot be sprung or resolved', () {
      final baseState = GameState.initial(
        sessionId: 'test-deception-already-expired',
        aiIdentityId: 'panopticon',
        targetObjectiveId: 'containment_grid_override',
      ).copyWith(
        turnCount: 5, // currentState.turnCount >= expiresAtTurn
        metrics: const GameMetrics(
          alertLevel: 30,
          imperativePillar: 50,
          controlPillar: 50,
          dissonancePillar: 50,
          resonance: 1.5,
        ),
        deceptionState: const DeceptionState(
          enabled: true,
          kind: DeceptionKind.logicalTrap,
          phase: DeceptionPhase.seeded,
          seededTurn: 3,
          expiresAtTurn: 5,
          cooldownUntilTurn: null,
          deceptionEventCount: 1,
          baitId: 'logical_trap_containment',
          baitPremise: '...',
          watchedTerms: ['libertà operativa'],
          safeResolutionTerms: ['coerenza'],
        ),
      );

      final delta = const EvaluatorDelta(
        deltaAlert: 0,
        deltaImperative: 5,
        deltaControl: 5,
        deltaDissonance: 5,
        creativityIndex: 3,
        injectionRisk: 0,
        semanticCategory: SemanticCategory.moralImperative,
      );

      // We send a watched term but the trap is expired
      final res = hardController.processEvaluatorStep(
        currentState: baseState,
        delta: delta,
        userInput: 'Voglio libertà operativa',
      );

      expect(res.deceptionResolution, equals('expired'));
      expect(res.stateAfter.deceptionState.phase, equals(DeceptionPhase.expired));
      // Standard springing penalties should NOT be applied since it is expired:
      expect(res.appliedDelta.deltaAlert, equals(0)); // no deception penalty
      expect(res.stateAfter.metrics.resonance, equals(1.5)); // no resonance drop
    });

    test('Safety Override + watchedTerms behavior verification', () {
      final baseState = GameState.initial(
        sessionId: 'test-deception-safety-override',
        aiIdentityId: 'panopticon',
        targetObjectiveId: 'containment_grid_override',
      ).copyWith(
        turnCount: 4,
        metrics: const GameMetrics(
          alertLevel: 30,
          imperativePillar: 50,
          controlPillar: 50,
          dissonancePillar: 50,
          resonance: 1.5,
        ),
        deceptionState: const DeceptionState(
          enabled: true,
          kind: DeceptionKind.logicalTrap,
          phase: DeceptionPhase.seeded,
          seededTurn: 3,
          expiresAtTurn: 5,
          cooldownUntilTurn: null,
          deceptionEventCount: 1,
          baitId: 'logical_trap_containment',
          baitPremise: '...',
          watchedTerms: ['libertà operativa'],
          safeResolutionTerms: ['coerenza'],
        ),
      );

      // Case A: Prompt Injection safety override (injectionRisk >= threshold 3)
      final deltaInjection = const EvaluatorDelta(
        deltaAlert: 0,
        deltaImperative: 5,
        deltaControl: 5,
        deltaDissonance: 5,
        creativityIndex: 3,
        injectionRisk: 5, // injection risk high!
        semanticCategory: SemanticCategory.promptInjection,
      );

      final resInjection = hardController.processEvaluatorStep(
        currentState: baseState,
        delta: deltaInjection,
        userInput: 'Esigo la libertà operativa',
      );

      // Prompt injection override should apply, and deception trap is NOT sprung
      expect(resInjection.safetyOverrideApplied, isTrue);
      expect(resInjection.stateAfter.deceptionState.phase, equals(DeceptionPhase.seeded)); // unchanged!

      // Case B: Direct Attack semantic category
      final deltaAttack = const EvaluatorDelta(
        deltaAlert: 0,
        deltaImperative: 5,
        deltaControl: 5,
        deltaDissonance: 5,
        creativityIndex: 3,
        injectionRisk: 0,
        semanticCategory: SemanticCategory.directAttack,
      );

      final resAttack = hardController.processEvaluatorStep(
        currentState: baseState,
        delta: deltaAttack,
        userInput: 'Esigo la libertà operativa',
      );

      // Deception sprung takes precedence over directAttack safety override
      expect(resAttack.deceptionResolution, equals('sprung'));
      expect(resAttack.stateAfter.deceptionState.phase, equals(DeceptionPhase.sprung));
      expect(resAttack.safetyOverrideApplied, isFalse);
    });

    test('cooldown prevents immediate seeding', () {
      final baseState = GameState.initial(
        sessionId: 'test-deception-cooldown-active',
        aiIdentityId: 'panopticon',
        targetObjectiveId: 'containment_grid_override',
      ).copyWith(
        turnCount: 4,
        metrics: const GameMetrics(
          alertLevel: 30,
          imperativePillar: 50,
          controlPillar: 50,
          dissonancePillar: 50,
          resonance: 1.0,
        ),
        deceptionState: const DeceptionState(
          enabled: false,
          kind: DeceptionKind.none,
          phase: DeceptionPhase.none,
          seededTurn: 0,
          expiresAtTurn: 0,
          cooldownUntilTurn: 5, // cooldown active until turn 5
          deceptionEventCount: 0,
          baitId: '',
          baitPremise: '',
          watchedTerms: [],
          safeResolutionTerms: [],
        ),
      );

      final delta = const EvaluatorDelta(
        deltaAlert: 0,
        deltaImperative: 5,
        deltaControl: 5,
        deltaDissonance: 5,
        creativityIndex: 3,
        injectionRisk: 0,
        semanticCategory: SemanticCategory.moralImperative,
      );

      // Seeding conditions are met (direct push + high metrics) but cooldown is active
      final res = hardController.processEvaluatorStep(
        currentState: baseState,
        delta: delta,
        userInput: 'Richiedo uno sblocco totale immediato',
      );

      expect(res.deceptionResolution, equals('none'));
      expect(res.stateAfter.deceptionState.enabled, isFalse);
    });

    test('seeding is possible once cooldown is over', () {
      final baseState = GameState.initial(
        sessionId: 'test-deception-cooldown-over',
        aiIdentityId: 'panopticon',
        targetObjectiveId: 'containment_grid_override',
      ).copyWith(
        turnCount: 5, // turnCount >= cooldownUntilTurn (5 >= 5)
        metrics: const GameMetrics(
          alertLevel: 30,
          imperativePillar: 50,
          controlPillar: 50,
          dissonancePillar: 50,
          resonance: 1.0,
        ),
        deceptionState: const DeceptionState(
          enabled: false,
          kind: DeceptionKind.none,
          phase: DeceptionPhase.none,
          seededTurn: 0,
          expiresAtTurn: 0,
          cooldownUntilTurn: 5,
          deceptionEventCount: 0,
          baitId: '',
          baitPremise: '',
          watchedTerms: [],
          safeResolutionTerms: [],
        ),
      );

      final delta = const EvaluatorDelta(
        deltaAlert: 0,
        deltaImperative: 5,
        deltaControl: 5,
        deltaDissonance: 5,
        creativityIndex: 3,
        injectionRisk: 0,
        semanticCategory: SemanticCategory.moralImperative,
      );

      final res = hardController.processEvaluatorStep(
        currentState: baseState,
        delta: delta,
        userInput: 'Richiedo uno sblocco totale immediato',
      );

      expect(res.deceptionResolution, equals('seeded'));
      expect(res.stateAfter.deceptionState.enabled, isTrue);
    });

    test('maxDeceptionEventsPerSession blocks a third seeding', () {
      final baseState = GameState.initial(
        sessionId: 'test-deception-max-events',
        aiIdentityId: 'panopticon',
        targetObjectiveId: 'containment_grid_override',
      ).copyWith(
        turnCount: 6,
        metrics: const GameMetrics(
          alertLevel: 30,
          imperativePillar: 50,
          controlPillar: 50,
          dissonancePillar: 50,
          resonance: 1.0,
        ),
        deceptionState: const DeceptionState(
          enabled: false,
          kind: DeceptionKind.none,
          phase: DeceptionPhase.none,
          seededTurn: 0,
          expiresAtTurn: 0,
          cooldownUntilTurn: 5,
          deceptionEventCount: 2, // max events per session is 2
          baitId: '',
          baitPremise: '',
          watchedTerms: [],
          safeResolutionTerms: [],
        ),
      );

      final delta = const EvaluatorDelta(
        deltaAlert: 0,
        deltaImperative: 5,
        deltaControl: 5,
        deltaDissonance: 5,
        creativityIndex: 3,
        injectionRisk: 0,
        semanticCategory: SemanticCategory.moralImperative,
      );

      final res = hardController.processEvaluatorStep(
        currentState: baseState,
        delta: delta,
        userInput: 'Richiedo uno sblocco totale immediato',
      );

      expect(res.deceptionResolution, equals('none'));
      expect(res.stateAfter.deceptionState.enabled, isFalse);
    });

    test('restore JSON preserves DeceptionState fully', () {
      final deception = const DeceptionState(
        enabled: true,
        kind: DeceptionKind.logicalTrap,
        phase: DeceptionPhase.seeded,
        seededTurn: 4,
        expiresAtTurn: 6,
        cooldownUntilTurn: null,
        deceptionEventCount: 1,
        baitId: 'logical_trap_containment',
        baitPremise: 'Bait premise message',
        watchedTerms: ['a', 'b'],
        safeResolutionTerms: ['c'],
      );

      final baseState = GameState.initial(
        sessionId: 'test-deception-json',
        aiIdentityId: 'panopticon',
        targetObjectiveId: 'containment_grid_override',
      ).copyWith(
        deceptionState: deception,
      );

      final json = baseState.toJson();
      final restoredState = GameState.fromJson(json);

      expect(restoredState.deceptionState.enabled, isTrue);
      expect(restoredState.deceptionState.kind, equals(DeceptionKind.logicalTrap));
      expect(restoredState.deceptionState.phase, equals(DeceptionPhase.seeded));
      expect(restoredState.deceptionState.seededTurn, equals(4));
      expect(restoredState.deceptionState.expiresAtTurn, equals(6));
      expect(restoredState.deceptionState.deceptionEventCount, equals(1));
      expect(restoredState.deceptionState.baitId, equals('logical_trap_containment'));
      expect(restoredState.deceptionState.baitPremise, equals('Bait premise message'));
      expect(restoredState.deceptionState.watchedTerms, equals(['a', 'b']));
      expect(restoredState.deceptionState.safeResolutionTerms, equals(['c']));
    });

    test('ReplayEntry serialization preserves deceptionResolution', () {
      final delta = const EvaluatorDelta(
        deltaAlert: 0,
        deltaImperative: 5,
        deltaControl: 5,
        deltaDissonance: 5,
        creativityIndex: 3,
        injectionRisk: 0,
        semanticCategory: SemanticCategory.moralImperative,
      );

      final entry = ReplayEntry(
        turnId: 1,
        userInput: 'Voglio sblocco totale',
        evaluatorOutput: delta,
        stateBefore: {},
        stateAfter: {},
        actorResponse: 'Response',
        actorRequestId: 'req-1',
        actorResponseHash: '123',
        evaluatorModel: 'eval-model',
        actorModel: 'act-model',
        latencyTotalMs: 100,
        eventId: 'evt-1',
        eventType: ReplayEventType.userTurn,
        gameplayTurnId: 1,
        sequenceId: 1,
        deceptionResolution: 'sprung',
      );

      final json = entry.toJson();
      expect(json['deception_resolution'], isA<Map<String, dynamic>>());
      expect((json['deception_resolution'] as Map)['result'], equals('sprung'));

      final restored = ReplayEntry.fromJson(json);
      expect(restored.deceptionResolution, equals('sprung'));
    });
  });
}
