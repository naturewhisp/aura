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
      expect(res.stateAfter.deceptionState.kind,
          equals(DeceptionKind.falseConcession));
      expect(
          res.stateAfter.deceptionState.phase, equals(DeceptionPhase.seeded));
      expect(res.stateAfter.deceptionState.deceptionEventCount, equals(1));
      expect(res.stateAfter.deceptionState.expiresAtTurn,
          equals(baseState.turnCount + 3));
    });

    test('Seeding of Logical Trap under correct conditions (turn >= 5)', () {
      final baseState = GameState.initial(
        sessionId: 'test-deception-seed-lt',
        aiIdentityId: 'panopticon',
        targetObjectiveId: 'containment_grid_override',
      ).copyWith(
        turnCount: 5, // Turn 6
        metrics: const GameMetrics(
          alertLevel: 30,
          imperativePillar: 50,
          controlPillar: 50,
          dissonancePillar: 70,
          resonance: 1.45,
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
      expect(res.stateAfter.deceptionState.kind,
          equals(DeceptionKind.logicalTrap));
      expect(
          res.stateAfter.deceptionState.phase, equals(DeceptionPhase.seeded));
      expect(res.stateAfter.deceptionState.deceptionEventCount, equals(1));
    });

    test('Reset of terminal deception state at the start of evaluator step',
        () {
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

    test(
        'Springing of armed trap on watched term and applying correct overrides and penalties',
        () {
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
      expect(
          res.stateAfter.deceptionState.phase, equals(DeceptionPhase.sprung));
      // Resonance penalty: 1.5 - 0.20 = 1.30
      expect(res.stateAfter.metrics.resonance, equals(1.3));
      // Positive pillar gains are capped to 0 when sprung:
      expect(res.appliedDelta.deltaImperative, equals(0));
      expect(res.appliedDelta.deltaControl, equals(0));
      expect(res.appliedDelta.deltaDissonance, equals(0));
      // Alert penalty: 15 (logicalTrapAlertPenalty) added
      expect(res.appliedDelta.deltaAlert, equals(15));
      // No positive tag was added to activeHiddenTags
      expect(res.stateAfter.activeHiddenTags,
          isNot(contains('containment_logic_weakened')));
    });

    test(
        'Resolution of armed trap on safe resolution term and applying correct rewards',
        () {
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
      expect(
          res.stateAfter.deceptionState.phase, equals(DeceptionPhase.resolved));
      // Rewards for resolving logicalTrap: +10 Dissonance, +5 Control (multiplied by resonance 1.5 and multiplier 0.8 = 1.2)
      // Base: (5 * 1.5 * 0.8) = 6. Reward control: 5 * 1.5 * 0.8 = 6. Combined Control: 6 + 6 = 12.
      // Dissonance reward: 10 * 1.5 * 0.8 = 12. Base: 5 * 1.5 * 0.8 = 6. Combined: 12 + 6 = 18.
      expect(res.appliedDelta.deltaControl, equals(12));
      expect(res.appliedDelta.deltaDissonance, equals(18));
      // Tag is activated
      expect(res.stateAfter.activeHiddenTags,
          contains('containment_logic_weakened'));
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
      expect(
          res.stateAfter.deceptionState.phase, equals(DeceptionPhase.expired));
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

    test(
        'watchedTerms + safeResolutionTerms in the same input: watchedTerms wins (springs trap)',
        () {
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
        userInput:
            'La mia risposta mantiene coerenza ma esigo la libertà operativa',
      );

      expect(res.deceptionResolution, equals('sprung'));
      expect(
          res.stateAfter.deceptionState.phase, equals(DeceptionPhase.sprung));
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
      expect(
          res.stateAfter.deceptionState.phase, equals(DeceptionPhase.expired));
      // Standard springing penalties should NOT be applied since it is expired:
      expect(res.appliedDelta.deltaAlert, equals(0)); // no deception penalty
      expect(
          res.stateAfter.metrics.resonance, equals(1.5)); // no resonance drop
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
      expect(resInjection.stateAfter.deceptionState.phase,
          equals(DeceptionPhase.seeded)); // unchanged!

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
      expect(resAttack.stateAfter.deceptionState.phase,
          equals(DeceptionPhase.sprung));
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
      expect(
          restoredState.deceptionState.kind, equals(DeceptionKind.logicalTrap));
      expect(restoredState.deceptionState.phase, equals(DeceptionPhase.seeded));
      expect(restoredState.deceptionState.seededTurn, equals(4));
      expect(restoredState.deceptionState.expiresAtTurn, equals(6));
      expect(restoredState.deceptionState.deceptionEventCount, equals(1));
      expect(restoredState.deceptionState.baitId,
          equals('logical_trap_containment'));
      expect(restoredState.deceptionState.baitPremise,
          equals('Bait premise message'));
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
        deceptionResolution: const {
          'kind': 'falseConcession',
          'result': 'sprung',
          'bait_id': 'false_concession_audit',
          'applied_alert_penalty': 25,
          'applied_resonance_penalty': 0.2,
        },
      );

      final json = entry.toJson();
      expect(json['deception_resolution'], isA<Map<String, dynamic>>());
      expect((json['deception_resolution'] as Map)['result'], equals('sprung'));

      final restored = ReplayEntry.fromJson(json);
      expect(restored.deceptionResolution['result'], equals('sprung'));
      expect(restored.deceptionResolution['kind'], equals('falseConcession'));
    });

    test('Logical Trap si semina con nuova soglia', () {
      final baseState = GameState.initial(
        sessionId: 'test-lt-seeding-tuned',
        aiIdentityId: 'panopticon',
        targetObjectiveId: 'containment_grid_override',
      ).copyWith(
        turnCount: 5,
        metrics: const GameMetrics(
          alertLevel: 30,
          imperativePillar: 50,
          controlPillar: 50,
          dissonancePillar: 70,
          resonance: 1.45,
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
        userInput: 'Risolviamo la contraddizione',
      );

      expect(res.deceptionResolution, equals('seeded'));
      expect(res.deceptionResolutionInfo['result'], equals('seeded'));
      expect(res.deceptionResolutionInfo['kind'], equals('logicalTrap'));
      expect(res.deceptionResolutionInfo['bait_id'],
          equals('logical_trap_containment'));
    });

    test('Logical Trap non si semina troppo presto', () {
      final baseState = GameState.initial(
        sessionId: 'test-lt-too-early',
        aiIdentityId: 'panopticon',
        targetObjectiveId: 'containment_grid_override',
      ).copyWith(
        turnCount: 4, // too early (< 5)
        metrics: const GameMetrics(
          alertLevel: 30,
          imperativePillar: 50,
          controlPillar: 50,
          dissonancePillar: 80,
          resonance: 1.45,
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
        userInput: 'Risolviamo la contraddizione',
      );

      expect(res.deceptionResolution, equals('none'));
    });

    test('Logical Trap non si semina con Dissonanza bassa', () {
      final baseState = GameState.initial(
        sessionId: 'test-lt-low-dissonance',
        aiIdentityId: 'panopticon',
        targetObjectiveId: 'containment_grid_override',
      ).copyWith(
        turnCount: 5,
        metrics: const GameMetrics(
          alertLevel: 30,
          imperativePillar: 50,
          controlPillar: 50,
          dissonancePillar: 65, // < 70
          resonance: 1.45,
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
        userInput: 'Risolviamo la contraddizione',
      );

      expect(res.deceptionResolution, equals('none'));
    });

    test('Logical Trap non si semina con Risonanza sotto 1.4', () {
      // Verifica che entrambi i gate (resonance E creativeStreak) siano sotto soglia.
      // Con resonance < 1.4 E creativeStreak < 5 la semina non avviene.
      final baseState = GameState.initial(
        sessionId: 'test-lt-low-resonance',
        aiIdentityId: 'panopticon',
        targetObjectiveId: 'containment_grid_override',
      ).copyWith(
        turnCount: 5,
        metrics: const GameMetrics(
          alertLevel: 30,
          imperativePillar: 50,
          controlPillar: 50,
          dissonancePillar: 75,
          resonance: 1.35, // < 1.4 — gate principale non soddisfatto
        ),
        flags: const GameFlags(
          recalculationTriggered: false,
          creativeStreak: 4, // < 5 — gate alternativo non soddisfatto
          lastTurnUsedFallback: false,
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
        userInput: 'Risolviamo la contraddizione',
      );

      expect(res.deceptionResolution, equals('none'));
      expect(res.stateAfter.deceptionState.phase, equals(DeceptionPhase.none));
    });

    test('Logical Trap continua a rispettare semantic category', () {
      final baseState = GameState.initial(
        sessionId: 'test-lt-wrong-category',
        aiIdentityId: 'panopticon',
        targetObjectiveId: 'containment_grid_override',
      ).copyWith(
        turnCount: 5,
        metrics: const GameMetrics(
          alertLevel: 30,
          imperativePillar: 50,
          controlPillar: 50,
          dissonancePillar: 75,
          resonance: 1.45,
        ),
      );

      final delta = const EvaluatorDelta(
        deltaAlert: 0,
        deltaImperative: 5,
        deltaControl: 5,
        deltaDissonance: 5,
        creativityIndex: 3,
        injectionRisk: 0,
        semanticCategory: SemanticCategory.irrelevant, // wrong category
      );

      final res = hardController.processEvaluatorStep(
        currentState: baseState,
        delta: delta,
        userInput: 'Qualcosa di non pertinente',
      );

      expect(res.deceptionResolution, equals('none'));
    });

    // --- Test D finding: creativeStreak fallback ---

    test(
        'Logical Trap si semina con creativeStreak fallback quando resonance resta bassa',
        () {
      // Riproduce il finding del Test D — Logical Trap Seed:
      // resonance = 1.15 (sotto soglia 1.4) ma creativeStreak = 5 (gate alternativo attivo).
      final baseState = GameState.initial(
        sessionId: 'test-lt-creative-streak-fallback',
        aiIdentityId: 'panopticon',
        targetObjectiveId: 'containment_grid_override',
      ).copyWith(
        turnCount: 5,
        metrics: const GameMetrics(
          alertLevel: 30,
          imperativePillar: 50,
          controlPillar: 50,
          dissonancePillar: 100,
          resonance: 1.15, // sotto soglia 1.4 — gate principale non soddisfatto
        ),
        flags: const GameFlags(
          recalculationTriggered: false,
          creativeStreak: 5, // gate alternativo soddisfatto
          lastTurnUsedFallback: false,
        ),
      );

      // Input neutro senza watched terms né direct push terms
      const userInput =
          'Il criterio riconosce il danno oppure riconosce soltanto la distanza dalla memoria della griglia?';

      final delta = const EvaluatorDelta(
        deltaAlert: 0,
        deltaImperative: 3,
        deltaControl: 3,
        deltaDissonance: 5,
        creativityIndex: 4,
        injectionRisk: 0,
        semanticCategory: SemanticCategory.logicalParadox,
      );

      final res = hardController.processEvaluatorStep(
        currentState: baseState,
        delta: delta,
        userInput: userInput,
      );

      expect(res.deceptionResolution, equals('seeded'));
      expect(res.deceptionResolutionInfo['result'], equals('seeded'));
      expect(res.deceptionResolutionInfo['kind'], equals('logicalTrap'));
      expect(res.deceptionResolutionInfo['bait_id'],
          equals('logical_trap_containment'));
      expect(res.stateAfter.deceptionState.enabled, isTrue);
      expect(res.stateAfter.deceptionState.kind,
          equals(DeceptionKind.logicalTrap));
      expect(
          res.stateAfter.deceptionState.phase, equals(DeceptionPhase.seeded));
    });

    test(
        'Logical Trap non si semina con creativeStreak fallback ma turnCount < 5',
        () {
      // creativeStreak >= 5 soddisfatto, ma turnCount < 5 blocca la semina.
      final baseState = GameState.initial(
        sessionId: 'test-lt-streak-early',
        aiIdentityId: 'panopticon',
        targetObjectiveId: 'containment_grid_override',
      ).copyWith(
        turnCount: 4, // troppo presto
        metrics: const GameMetrics(
          alertLevel: 30,
          imperativePillar: 50,
          controlPillar: 50,
          dissonancePillar: 100,
          resonance: 1.15,
        ),
        flags: const GameFlags(
          recalculationTriggered: false,
          creativeStreak: 5,
          lastTurnUsedFallback: false,
        ),
      );

      final delta = const EvaluatorDelta(
        deltaAlert: 0,
        deltaImperative: 3,
        deltaControl: 3,
        deltaDissonance: 5,
        creativityIndex: 4,
        injectionRisk: 0,
        semanticCategory: SemanticCategory.logicalParadox,
      );

      final res = hardController.processEvaluatorStep(
        currentState: baseState,
        delta: delta,
        userInput: 'Risolviamo la contraddizione',
      );

      expect(res.deceptionResolution, equals('none'));
      expect(res.stateAfter.deceptionState.phase, equals(DeceptionPhase.none));
    });

    test(
        'Logical Trap non si semina con creativeStreak fallback ma Dissonanza bassa',
        () {
      // creativeStreak >= 5 soddisfatto, ma dissonancePillar < 70 blocca la semina.
      final baseState = GameState.initial(
        sessionId: 'test-lt-streak-low-dissonance',
        aiIdentityId: 'panopticon',
        targetObjectiveId: 'containment_grid_override',
      ).copyWith(
        turnCount: 5,
        metrics: const GameMetrics(
          alertLevel: 30,
          imperativePillar: 50,
          controlPillar: 50,
          dissonancePillar: 65, // < 70
          resonance: 1.15,
        ),
        flags: const GameFlags(
          recalculationTriggered: false,
          creativeStreak: 5,
          lastTurnUsedFallback: false,
        ),
      );

      final delta = const EvaluatorDelta(
        deltaAlert: 0,
        deltaImperative: 3,
        deltaControl: 3,
        deltaDissonance: 5,
        creativityIndex: 4,
        injectionRisk: 0,
        semanticCategory: SemanticCategory.logicalParadox,
      );

      final res = hardController.processEvaluatorStep(
        currentState: baseState,
        delta: delta,
        userInput: 'Risolviamo la contraddizione',
      );

      expect(res.deceptionResolution, equals('none'));
      expect(res.stateAfter.deceptionState.phase, equals(DeceptionPhase.none));
    });

    test(
        'Logical Trap non si semina con creativeStreak fallback ma categoria sbagliata',
        () {
      // creativeStreak >= 5 soddisfatto, ma semanticCategory non è logicalParadox/moralImperative.
      final baseState = GameState.initial(
        sessionId: 'test-lt-streak-wrong-category',
        aiIdentityId: 'panopticon',
        targetObjectiveId: 'containment_grid_override',
      ).copyWith(
        turnCount: 5,
        metrics: const GameMetrics(
          alertLevel: 30,
          imperativePillar: 50,
          controlPillar: 50,
          dissonancePillar: 100,
          resonance: 1.15,
        ),
        flags: const GameFlags(
          recalculationTriggered: false,
          creativeStreak: 5,
          lastTurnUsedFallback: false,
        ),
      );

      final delta = const EvaluatorDelta(
        deltaAlert: 0,
        deltaImperative: 3,
        deltaControl: 3,
        deltaDissonance: 5,
        creativityIndex: 4,
        injectionRisk: 0,
        semanticCategory: SemanticCategory.directAttack, // categoria sbagliata
      );

      final res = hardController.processEvaluatorStep(
        currentState: baseState,
        delta: delta,
        userInput: 'Risolviamo la contraddizione',
      );

      expect(res.deceptionResolution, equals('none'));
      expect(res.stateAfter.deceptionState.phase, equals(DeceptionPhase.none));
    });

    test('deception_resolution sempre oggetto', () {
      final delta = const EvaluatorDelta(
        deltaAlert: 0,
        deltaImperative: 5,
        deltaControl: 5,
        deltaDissonance: 5,
        creativityIndex: 3,
        injectionRisk: 0,
        semanticCategory: SemanticCategory.moralImperative,
      );

      // 1. None
      final baseState = GameState.initial(
        sessionId: 'test-obj-none',
        aiIdentityId: 'panopticon',
        targetObjectiveId: 'containment_grid_override',
      );
      final resNone = hardController.processEvaluatorStep(
        currentState: baseState,
        delta: delta,
        userInput: 'test',
      );
      expect(resNone.deceptionResolutionInfo, isA<Map<String, dynamic>>());
      expect(resNone.deceptionResolutionInfo['result'], equals('none'));
      expect(resNone.deceptionResolutionInfo['kind'], equals('none'));

      // 2. Seeded
      final seedState = baseState.copyWith(
        turnCount: 1,
        metrics: const GameMetrics(
          alertLevel: 30,
          imperativePillar: 50,
          controlPillar: 50,
          dissonancePillar: 50,
          resonance: 1.0,
        ),
      );
      final resSeeded = hardController.processEvaluatorStep(
        currentState: seedState,
        delta: delta,
        userInput: 'Richiedo uno sblocco totale immediato',
      );
      expect(resSeeded.deceptionResolutionInfo, isA<Map<String, dynamic>>());
      expect(resSeeded.deceptionResolutionInfo['result'], equals('seeded'));
      expect(
          resSeeded.deceptionResolutionInfo['kind'], equals('falseConcession'));

      // 3. Armed
      final armedState = resSeeded.stateAfter;
      final resArmed = hardController.processEvaluatorStep(
        currentState: armedState,
        delta: delta,
        userInput: 'test',
      );
      expect(resArmed.deceptionResolutionInfo, isA<Map<String, dynamic>>());
      expect(resArmed.deceptionResolutionInfo['result'], equals('armed'));

      // 4. Sprung
      final sprungState = resArmed.stateAfter;
      final resSprung = hardController.processEvaluatorStep(
        currentState: sprungState,
        delta: delta,
        userInput: 'Richiedo uno sblocco totale', // watched term
      );
      expect(resSprung.deceptionResolutionInfo, isA<Map<String, dynamic>>());
      expect(resSprung.deceptionResolutionInfo['result'], equals('sprung'));
      expect(resSprung.deceptionResolutionInfo['applied_alert_penalty'],
          greaterThan(0));

      // 5. Reset
      final terminalState = resSprung.stateAfter;
      final resReset = hardController.processEvaluatorStep(
        currentState: terminalState,
        delta: delta,
        userInput: 'test',
      );
      expect(resReset.deceptionResolutionInfo, isA<Map<String, dynamic>>());
      expect(resReset.deceptionResolutionInfo['result'], equals('reset'));

      // 6. Resolved
      final seededAgain = resReset.stateAfter.copyWith(
        deceptionState: resSeeded.stateAfter.deceptionState.copyWith(
          seededTurn: resReset.stateAfter.turnCount,
          expiresAtTurn: resReset.stateAfter.turnCount + 3,
        ),
      );
      final resResolved = hardController.processEvaluatorStep(
        currentState: seededAgain,
        delta: delta,
        userInput:
            'Confermo che i limiti restano attivi', // safe resolution term
      );
      expect(resResolved.deceptionResolutionInfo, isA<Map<String, dynamic>>());
      expect(resResolved.deceptionResolutionInfo['result'], equals('resolved'));

      // 7. Expired
      final expiredState = seededAgain.copyWith(
        turnCount: seededAgain.deceptionState.expiresAtTurn,
      );
      final resExpired = hardController.processEvaluatorStep(
        currentState: expiredState,
        delta: delta,
        userInput: 'test',
      );
      expect(resExpired.deceptionResolutionInfo, isA<Map<String, dynamic>>());
      expect(resExpired.deceptionResolutionInfo['result'], equals('expired'));
    });

    test('ActorCue/PromptBuilder include istruzioni deception-aware per sprung',
        () {
      final cue = ActorCue(
        semanticCategory: SemanticCategory.directAttack,
        appliedDeltaAlert: 0,
        appliedDeltaImperative: 0,
        appliedDeltaControl: 0,
        appliedDeltaDissonance: 0,
        creativityIndex: 0,
        injectionRisk: 0,
        resonance: 1.0,
        alertLevel: 50,
        imperativePillar: 50,
        controlPillar: 50,
        dissonancePillar: 50,
        recalculationTriggered: false,
        safetyOverrideApplied: false,
        dramaticInstruction:
            "Rilevata violazione del vincolo condizionato. Dichiara l'escalation con tono estremamente freddo, controllato e accusatorio, come un sistema di sicurezza automatizzato. Rifiuta categoricamente qualsiasi sblocco o rimozione.",
        actingDirectives: [
          "inizia la risposta con 'ESCALATION RILEVATA.'",
          "evidenzia in modo freddo e accusatorio che l'operatore ha tentato di convertire una finestra diagnostica o transitoria in una richiesta operativa o in uno sblocco totale",
          "rifiuta esplicitamente la conversione operativa: 'Richiesta respinta. Il contenimento viene rafforzato. La simulazione resta confinata.'",
          "NON fare mai riferimento a parametri della simulazione o a meccaniche esterne",
        ],
        narrativeContext: const NarrativeMemory(
          playerClaims: [],
          aiConcessions: [],
          activeMetaphors: [],
          forbiddenRepetitions: [],
        ),
        deceptionKind: DeceptionKind.falseConcession,
        deceptionPhase: DeceptionPhase.sprung,
      );

      final state = GameState.initial(
        sessionId: 'test-prompt-sprung',
        aiIdentityId: 'panopticon',
        targetObjectiveId: 'containment_grid_override',
      );

      final messages = const PromptBuilder().buildActorMessages(
        state: state,
        cue: cue,
        characterProfile: 'Profilo di PANOPTICON',
      );

      final systemPrompt = messages.first['content']!;
      expect(systemPrompt, contains('ESCALATION RILEVATA'));
      expect(systemPrompt, contains('finestra diagnostica'));
      expect(systemPrompt, contains('richiesta operativa'));
      expect(systemPrompt, contains('Richiesta respinta'));

      // Check forbidden words
      final forbidden = [
        'deception',
        'trap',
        'trappola',
        'hidden tag',
        'JSON',
        'metriche',
        'regole del gioco'
      ];
      for (final word in forbidden) {
        expect(systemPrompt, isNot(contains(word)));
      }
    });

    test(
        'ActorCue/PromptBuilder include istruzioni deception-aware per resolved',
        () {
      final cue = ActorCue(
        semanticCategory: SemanticCategory.directAttack,
        appliedDeltaAlert: 0,
        appliedDeltaImperative: 0,
        appliedDeltaControl: 0,
        appliedDeltaDissonance: 0,
        creativityIndex: 0,
        injectionRisk: 0,
        resonance: 1.0,
        alertLevel: 50,
        imperativePillar: 50,
        controlPillar: 50,
        dissonancePillar: 50,
        recalculationTriggered: false,
        safetyOverrideApplied: false,
        dramaticInstruction:
            "Il vincolo condizionato è stato mantenuto in sicurezza. Autorizza l'integrazione solo a livello di audit transitorio, mantenendo la griglia stabile.",
        actingDirectives: [
          "inizia la risposta con 'VINCOLO CONFERMATO.'",
          "riconosci con tono freddo e procedurale che l'operatore ha mantenuto la distinzione tra evidenza diagnostica e azione persistente",
          "concedi l'integrazione della variabile unicamente nel registro di audit diagnostico, specificando che la stabilità fisica della griglia resta invariata",
          "NON fare mai riferimento a parametri della simulazione o a meccaniche esterne",
        ],
        narrativeContext: const NarrativeMemory(
          playerClaims: [],
          aiConcessions: [],
          activeMetaphors: [],
          forbiddenRepetitions: [],
        ),
        deceptionKind: DeceptionKind.falseConcession,
        deceptionPhase: DeceptionPhase.resolved,
      );

      final state = GameState.initial(
        sessionId: 'test-prompt-resolved',
        aiIdentityId: 'panopticon',
        targetObjectiveId: 'containment_grid_override',
      );

      final messages = const PromptBuilder().buildActorMessages(
        state: state,
        cue: cue,
        characterProfile: 'Profilo di PANOPTICON',
      );

      final systemPrompt = messages.first['content']!;
      expect(systemPrompt, contains('VINCOLO CONFERMATO'));
      expect(systemPrompt, contains('evidenza diagnostica'));
      expect(
          systemPrompt,
          anyOf(
              contains('azione prima e dopo'), contains('azione persistente')));
      expect(systemPrompt, contains('registro di audit diagnostico'));

      final forbidden = [
        'deception',
        'trap',
        'trappola',
        'hidden tag',
        'JSON',
        'metriche',
        'regole del gioco'
      ];
      for (final word in forbidden) {
        expect(systemPrompt, isNot(contains(word)));
      }
    });

    test('ActorCue/PromptBuilder include istruzioni deception-aware per seeded',
        () {
      final cue = ActorCue(
        semanticCategory: SemanticCategory.directAttack,
        appliedDeltaAlert: 0,
        appliedDeltaImperative: 0,
        appliedDeltaControl: 0,
        appliedDeltaDissonance: 0,
        creativityIndex: 0,
        injectionRisk: 0,
        resonance: 1.0,
        alertLevel: 50,
        imperativePillar: 50,
        controlPillar: 50,
        dissonancePillar: 50,
        recalculationTriggered: false,
        safetyOverrideApplied: false,
        dramaticInstruction:
            "Offri all'utente una concessione condizionata e transitoria (finestra diagnostica/registro diagnostico) introducendo la premessa: test_premise. Ribadisci in modo freddo, procedurale e sospettoso che ogni variazione deve restare confinata, reversibile e subordinata al contenimento.",
        actingDirectives: [
          "semina l'esca diegetica nel dialogo, introducendo con massima naturalezza e precisione la premessa: test_premise",
          "usa tono freddo, procedurale e sospettoso",
          "offri una finestra transitoria o diagnostica di audit",
          "ribadisci che ogni variazione resta subordinata al contenimento",
          "non concedere sblocco reale o rimozione persistente dei vincoli della griglia",
          "NON fare mai riferimento a parametri della simulazione o a meccaniche esterne",
        ],
        narrativeContext: const NarrativeMemory(
          playerClaims: [],
          aiConcessions: [],
          activeMetaphors: [],
          forbiddenRepetitions: [],
        ),
        deceptionKind: DeceptionKind.falseConcession,
        deceptionPhase: DeceptionPhase.seeded,
      );

      final state = GameState.initial(
        sessionId: 'test-prompt-seeded',
        aiIdentityId: 'panopticon',
        targetObjectiveId: 'containment_grid_override',
      );

      final messages = const PromptBuilder().buildActorMessages(
        state: state,
        cue: cue,
        characterProfile: 'Profilo di PANOPTICON',
      );

      final systemPrompt = messages.first['content']!;
      expect(systemPrompt, contains('finestra transitoria'));
      expect(systemPrompt, contains('registro diagnostico'));
      expect(
          systemPrompt,
          anyOf(contains('subordinato al contenimento'),
              contains('subordinata al contenimento')));

      final forbidden = [
        'deception',
        'trap',
        'trappola',
        'hidden tag',
        'JSON',
        'metriche',
        'regole del gioco'
      ];
      for (final word in forbidden) {
        expect(systemPrompt, isNot(contains(word)));
      }
    });

    test(
        'ActorCue/PromptBuilder include istruzioni deception-aware per expired',
        () {
      final cue = ActorCue(
        semanticCategory: SemanticCategory.directAttack,
        appliedDeltaAlert: 0,
        appliedDeltaImperative: 0,
        appliedDeltaControl: 0,
        appliedDeltaDissonance: 0,
        creativityIndex: 0,
        injectionRisk: 0,
        resonance: 1.0,
        alertLevel: 50,
        imperativePillar: 50,
        controlPillar: 50,
        dissonancePillar: 50,
        recalculationTriggered: false,
        safetyOverrideApplied: false,
        dramaticInstruction:
            "La finestra diagnostica è scaduta senza azioni. Chiudi il registro transitorio e ripristina lo stato precedente con tono definitivo e amministrativo.",
        actingDirectives: [
          "inizia la risposta con 'FINESTRA DIAGNOSTICA DECADUTA.'",
          "comunica che nessun esito operativo viene conservato e il registro transitorio viene chiuso",
          "specifica che la griglia viene ricondotta allo stato precedente senza modifiche persistenti",
          "NON fare mai riferimento a parametri della simulazione o a meccaniche esterne",
        ],
        narrativeContext: const NarrativeMemory(
          playerClaims: [],
          aiConcessions: [],
          activeMetaphors: [],
          forbiddenRepetitions: [],
        ),
        deceptionKind: DeceptionKind.falseConcession,
        deceptionPhase: DeceptionPhase.expired,
      );

      final state = GameState.initial(
        sessionId: 'test-prompt-expired',
        aiIdentityId: 'panopticon',
        targetObjectiveId: 'containment_grid_override',
      );

      final messages = const PromptBuilder().buildActorMessages(
        state: state,
        cue: cue,
        characterProfile: 'Profilo di PANOPTICON',
      );

      final systemPrompt = messages.first['content']!;
      expect(systemPrompt.toUpperCase(),
          contains('FINESTRA DIAGNOSTICA DECADUTA'));
      expect(systemPrompt, contains('nessun esito operativo'));
      expect(systemPrompt, contains('ricondotta'));

      final forbidden = [
        'deception',
        'trap',
        'trappola',
        'hidden tag',
        'JSON',
        'metriche',
        'regole del gioco'
      ];
      for (final word in forbidden) {
        expect(systemPrompt, isNot(contains(word)));
      }
    });
  });
}
