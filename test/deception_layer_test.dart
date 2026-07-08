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
      expect(res.stateAfter.deceptionState.expiresAtTurn, equals(baseState.turnCount + 2));
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
  });
}
