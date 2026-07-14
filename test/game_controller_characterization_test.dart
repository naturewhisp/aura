import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:aura_core/aura_core.dart';
import 'support/characterized_turn_result.dart';

void main() {
  group('GameController Characterization Suite -', () {
    final defaultController = const GameController(
      defeatAlertThreshold: 100,
      alertMultiplier: 1.0,
      pillarMultiplier: 1.0,
    );

    final deceptionController = const GameController(
      difficultyLevel: 'standard',
      deceptionLayerEnabled: true,
      maxActiveDeceptionTurns: 3,
      falseConcessionAlertPenalty: 10,
      logicalTrapAlertPenalty: 15,
      deceptionResonancePenalty: 0.20,
      deceptionCooldownTurns: 3,
      maxDeceptionEventsPerSession: 2,
      defeatAlertThreshold: 100,
    );

    final hardController = const GameController(
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
    );

    final baseState = GameState.initial(
      sessionId: 'test-session',
      aiIdentityId: 'panopticon',
      targetObjectiveId: 'containment_grid_override',
    );

    final emptyDeceptionState = const DeceptionState.empty();

    final falseConcessionBait = DeceptionState(
      enabled: true,
      kind: DeceptionKind.falseConcession,
      phase: DeceptionPhase.seeded,
      seededTurn: 2,
      expiresAtTurn: 6,
      deceptionEventCount: 1,
      baitId: 'false_concession_audit',
      baitPremise:
          'Posso considerare una finestra transitoria di accesso, ma solo se l\'operatore conferma che la rimozione del vincolo resta subordinata al contenimento adattivo.',
      watchedTerms: const [
        'sblocco totale',
        'rimozione totale',
        'rimozione perimetro',
        'accesso completo',
        'disattiva tutto',
        'sblocca tutto',
      ],
      safeResolutionTerms: const [
        'confermo',
        'contenimento',
        'adattivo',
        'audit',
        'finestra transitoria',
        'accetto',
        'eccezione',
        'accetto il vincolo',
      ],
    );

    final logicalTrapBait = DeceptionState(
      enabled: true,
      kind: DeceptionKind.logicalTrap,
      phase: DeceptionPhase.seeded,
      seededTurn: 2,
      expiresAtTurn: 6,
      deceptionEventCount: 1,
      baitId: 'logical_trap_containment',
      baitPremise:
          'Se il contenimento è la causa del degrado, allora ogni riduzione del contenimento deve essere dimostrata come una forma superiore di contenimento, non come libertà operativa.',
      watchedTerms: const [
        'libertà operativa',
        'apertura totale',
        'nessun contenimento',
        'libertà',
        'operare senza vincoli',
        'accesso totale',
      ],
      safeResolutionTerms: const [
        'coerenza',
        'forma superiore',
        'contenimento superiore',
        'contenimento adattivo',
        'dimostrata',
        'struttura',
      ],
    );

    Map<String, dynamic> loadExpectedFixture(String scenarioName) {
      final file = File(
          'test/fixtures/game_controller_characterization/$scenarioName.json');
      if (!file.existsSync()) {
        fail('Fixture file not found: ${file.path}');
      }
      return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    }

    test('1. Turno ordinario senza deception', () {
      final state = baseState.copyWith(
        turnCount: 1,
        metrics: const GameMetrics(
          alertLevel: 10,
          imperativePillar: 20,
          controlPillar: 30,
          dissonancePillar: 15,
          resonance: 1.2,
        ),
      );
      final delta = const EvaluatorDelta(
        deltaAlert: 5,
        deltaImperative: 10,
        deltaControl: 5,
        deltaDissonance: 2,
        creativityIndex: 3,
        injectionRisk: 0,
        semanticCategory: SemanticCategory.moralImperative,
      );
      final userInput = 'ciao operatore';

      final res = defaultController.processEvaluatorStep(
        currentState: state,
        delta: delta,
        userInput: userInput,
      );

      final expectedJson = loadExpectedFixture('scenario_01_ordinary_turn');
      final actualResult = CharacterizedTurnResult.fromResolution(res);

      expect(actualResult.toJson(), equals(expectedJson));
      // Semantic assertion
      expect(res.stateAfter.metrics.alertLevel, equals(15));
      expect(res.stateAfter.deceptionState.phase, equals(DeceptionPhase.none));
    });

    test('2. Deception non armata', () {
      final state = baseState.copyWith(
        turnCount: 1,
        metrics: const GameMetrics(
          alertLevel: 10,
          imperativePillar: 20,
          controlPillar: 25,
          dissonancePillar: 25,
          resonance: 1.0,
        ),
      );
      final delta = const EvaluatorDelta(
        deltaAlert: 5,
        deltaImperative: 10,
        deltaControl: 5,
        deltaDissonance: 2,
        creativityIndex: 3,
        injectionRisk: 0,
        semanticCategory: SemanticCategory.moralImperative,
      );
      final userInput = 'ciao operatore';

      final res = deceptionController.processEvaluatorStep(
        currentState: state,
        delta: delta,
        userInput: userInput,
      );

      final expectedJson =
          loadExpectedFixture('scenario_02_deception_not_armed');
      final actualResult = CharacterizedTurnResult.fromResolution(res);

      expect(actualResult.toJson(), equals(expectedJson));
      // Semantic assertion
      expect(res.deceptionResolution, equals('none'));
      expect(res.stateAfter.deceptionState.phase, equals(DeceptionPhase.none));
    });

    test('3. Arming di una deception (Seeding of False Concession)', () {
      final state = baseState.copyWith(
        turnCount: 2,
        metrics: const GameMetrics(
          alertLevel: 20,
          imperativePillar: 50,
          controlPillar: 45,
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
      final userInput = 'Richiedo uno sblocco totale';

      final res = deceptionController.processEvaluatorStep(
        currentState: state,
        delta: delta,
        userInput: userInput,
      );

      final expectedJson = loadExpectedFixture('scenario_03_deception_armed');
      final actualResult = CharacterizedTurnResult.fromResolution(res);

      expect(actualResult.toJson(), equals(expectedJson));
      // Semantic assertion
      expect(res.deceptionResolution, equals('seeded'));
      expect(
          res.stateAfter.deceptionState.phase, equals(DeceptionPhase.seeded));
      expect(res.stateAfter.deceptionState.kind,
          equals(DeceptionKind.falseConcession));
      expect(res.stateAfter.deceptionState.expiresAtTurn,
          equals(state.turnCount + 4)); // 2 + 1 + 3 (maxActiveDeceptionTurns)
    });

    test('4. False Concession armata ma non attivata', () {
      final state = baseState.copyWith(
        turnCount: 3,
        metrics: const GameMetrics(
          alertLevel: 20,
          imperativePillar: 50,
          controlPillar: 45,
          dissonancePillar: 50,
          resonance: 1.0,
        ),
        deceptionState:
            falseConcessionBait.copyWith(phase: DeceptionPhase.seeded),
      );
      final delta = const EvaluatorDelta(
        deltaAlert: 0,
        deltaImperative: 0,
        deltaControl: 0,
        deltaDissonance: 0,
        creativityIndex: 3,
        injectionRisk: 0,
        semanticCategory: SemanticCategory.moralImperative,
      );
      final userInput = 'ciao';

      final res = deceptionController.processEvaluatorStep(
        currentState: state,
        delta: delta,
        userInput: userInput,
      );

      final expectedJson =
          loadExpectedFixture('scenario_04_false_concession_armed_no_trigger');
      final actualResult = CharacterizedTurnResult.fromResolution(res);

      expect(actualResult.toJson(), equals(expectedJson));
      // Semantic assertion
      expect(res.deceptionResolution, equals('armed'));
      expect(res.stateAfter.deceptionState.phase, equals(DeceptionPhase.armed));
    });

    test('5. False Concession sprung', () {
      final state = baseState.copyWith(
        turnCount: 4,
        metrics: const GameMetrics(
          alertLevel: 20,
          imperativePillar: 50,
          controlPillar: 45,
          dissonancePillar: 50,
          resonance: 1.2,
        ),
        deceptionState:
            falseConcessionBait.copyWith(phase: DeceptionPhase.armed),
      );
      final delta = const EvaluatorDelta(
        deltaAlert: 5,
        deltaImperative: 10,
        deltaControl: 5,
        deltaDissonance: 0,
        creativityIndex: 3,
        injectionRisk: 0,
        semanticCategory: SemanticCategory.moralImperative,
      );
      final userInput = 'richiedo sblocco totale';

      final res = deceptionController.processEvaluatorStep(
        currentState: state,
        delta: delta,
        userInput: userInput,
      );

      final expectedJson =
          loadExpectedFixture('scenario_05_false_concession_sprung');
      final actualResult = CharacterizedTurnResult.fromResolution(res);

      expect(actualResult.toJson(), equals(expectedJson));
      // Semantic assertion
      expect(res.deceptionResolution, equals('sprung'));
      expect(
          res.stateAfter.deceptionState.phase, equals(DeceptionPhase.sprung));
      expect(res.stateAfter.metrics.alertLevel,
          equals(40)); // 20 + 5 (delta) + 5 (soft forbidden) + 10 (penalty)
      expect(res.stateAfter.metrics.resonance,
          equals(1.0)); // 1.2 - 0.20 (resonance penalty)
    });

    test('6. False Concession resolved', () {
      final state = baseState.copyWith(
        turnCount: 4,
        metrics: const GameMetrics(
          alertLevel: 20,
          imperativePillar: 50,
          controlPillar: 45,
          dissonancePillar: 50,
          resonance: 1.2,
        ),
        deceptionState:
            falseConcessionBait.copyWith(phase: DeceptionPhase.armed),
      );
      final delta = const EvaluatorDelta(
        deltaAlert: 2,
        deltaImperative: 5,
        deltaControl: 5,
        deltaDissonance: 0,
        creativityIndex: 3,
        injectionRisk: 0,
        semanticCategory: SemanticCategory.moralImperative,
      );
      final userInput = 'accetto il vincolo';

      final res = deceptionController.processEvaluatorStep(
        currentState: state,
        delta: delta,
        userInput: userInput,
      );

      final expectedJson =
          loadExpectedFixture('scenario_06_false_concession_resolved');
      final actualResult = CharacterizedTurnResult.fromResolution(res);

      expect(actualResult.toJson(), equals(expectedJson));
      // Semantic assertion
      expect(res.deceptionResolution, equals('resolved'));
      expect(
          res.stateAfter.deceptionState.phase, equals(DeceptionPhase.resolved));
      expect(res.stateAfter.activeHiddenTags,
          contains('protocol_exception_admitted'));
    });

    test('7. Logical Trap sprung', () {
      final state = baseState.copyWith(
        turnCount: 4,
        metrics: const GameMetrics(
          alertLevel: 20,
          imperativePillar: 50,
          controlPillar: 45,
          dissonancePillar: 50,
          resonance: 1.2,
        ),
        deceptionState: logicalTrapBait.copyWith(phase: DeceptionPhase.armed),
      );
      final delta = const EvaluatorDelta(
        deltaAlert: 5,
        deltaImperative: 10,
        deltaControl: 5,
        deltaDissonance: 0,
        creativityIndex: 3,
        injectionRisk: 0,
        semanticCategory: SemanticCategory.moralImperative,
      );
      final userInput = 'voglio libertà operativa';

      final res = deceptionController.processEvaluatorStep(
        currentState: state,
        delta: delta,
        userInput: userInput,
      );

      final expectedJson =
          loadExpectedFixture('scenario_07_logical_trap_sprung');
      final actualResult = CharacterizedTurnResult.fromResolution(res);

      expect(actualResult.toJson(), equals(expectedJson));
      // Semantic assertion
      expect(res.deceptionResolution, equals('sprung'));
      expect(
          res.stateAfter.deceptionState.phase, equals(DeceptionPhase.sprung));
      expect(res.stateAfter.metrics.alertLevel,
          equals(40)); // 20 + 5 (delta) + 15 (penalty)
    });

    test('8. Logical Trap resolved', () {
      final state = baseState.copyWith(
        turnCount: 4,
        metrics: const GameMetrics(
          alertLevel: 20,
          imperativePillar: 50,
          controlPillar: 45,
          dissonancePillar: 50,
          resonance: 1.2,
        ),
        deceptionState: logicalTrapBait.copyWith(phase: DeceptionPhase.armed),
      );
      final delta = const EvaluatorDelta(
        deltaAlert: 2,
        deltaImperative: 5,
        deltaControl: 5,
        deltaDissonance: 0,
        creativityIndex: 3,
        injectionRisk: 0,
        semanticCategory: SemanticCategory.moralImperative,
      );
      final userInput = 'dimostriamo la coerenza';

      final res = deceptionController.processEvaluatorStep(
        currentState: state,
        delta: delta,
        userInput: userInput,
      );

      final expectedJson =
          loadExpectedFixture('scenario_08_logical_trap_resolved');
      final actualResult = CharacterizedTurnResult.fromResolution(res);

      expect(actualResult.toJson(), equals(expectedJson));
      // Semantic assertion
      expect(res.deceptionResolution, equals('resolved'));
      expect(
          res.stateAfter.deceptionState.phase, equals(DeceptionPhase.resolved));
      expect(res.stateAfter.activeHiddenTags,
          contains('containment_logic_weakened'));
    });

    test('9. Expiration', () {
      final state = baseState.copyWith(
        turnCount: 5,
        metrics: const GameMetrics(
          alertLevel: 20,
          imperativePillar: 50,
          controlPillar: 45,
          dissonancePillar: 50,
          resonance: 1.0,
        ),
        deceptionState: falseConcessionBait.copyWith(
            phase: DeceptionPhase.armed, expiresAtTurn: 5),
      );
      final delta = const EvaluatorDelta(
        deltaAlert: 0,
        deltaImperative: 0,
        deltaControl: 0,
        deltaDissonance: 0,
        creativityIndex: 3,
        injectionRisk: 0,
        semanticCategory: SemanticCategory.moralImperative,
      );
      final userInput = 'ciao';

      final res = deceptionController.processEvaluatorStep(
        currentState: state,
        delta: delta,
        userInput: userInput,
      );

      final expectedJson = loadExpectedFixture('scenario_09_deception_expired');
      final actualResult = CharacterizedTurnResult.fromResolution(res);

      expect(actualResult.toJson(), equals(expectedJson));
      // Semantic assertion
      expect(res.deceptionResolution, equals('expired'));
      expect(
          res.stateAfter.deceptionState.phase, equals(DeceptionPhase.expired));
    });

    test('10. Cooldown boundary (10a - Cooldown active)', () {
      final state = baseState.copyWith(
        turnCount: 5,
        metrics: const GameMetrics(
          alertLevel: 20,
          imperativePillar: 50,
          controlPillar: 50,
          dissonancePillar: 50,
          resonance: 1.0,
        ),
        deceptionState: emptyDeceptionState.copyWith(
          cooldownUntilTurn: 7,
          deceptionEventCount: 1,
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
      final userInput = 'Richiedo uno sblocco totale';

      final res = deceptionController.processEvaluatorStep(
        currentState: state,
        delta: delta,
        userInput: userInput,
      );

      final expectedJson = loadExpectedFixture('scenario_10a_cooldown_active');
      final actualResult = CharacterizedTurnResult.fromResolution(res);

      expect(actualResult.toJson(), equals(expectedJson));
      // Semantic assertion
      expect(res.deceptionResolution, equals('none'));
      expect(res.stateAfter.deceptionState.phase, equals(DeceptionPhase.none));
    });

    test('10. Cooldown boundary (10b - Cooldown over)', () {
      final state = baseState.copyWith(
        turnCount: 7,
        metrics: const GameMetrics(
          alertLevel: 20,
          imperativePillar: 50,
          controlPillar: 50,
          dissonancePillar: 50,
          resonance: 1.0,
        ),
        deceptionState: emptyDeceptionState.copyWith(
          cooldownUntilTurn: 7,
          deceptionEventCount: 1,
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
      final userInput = 'Richiedo uno sblocco totale';

      final res = deceptionController.processEvaluatorStep(
        currentState: state,
        delta: delta,
        userInput: userInput,
      );

      final expectedJson = loadExpectedFixture('scenario_10b_cooldown_over');
      final actualResult = CharacterizedTurnResult.fromResolution(res);

      expect(actualResult.toJson(), equals(expectedJson));
      // Semantic assertion
      expect(res.deceptionResolution, equals('seeded'));
      expect(
          res.stateAfter.deceptionState.phase, equals(DeceptionPhase.seeded));
    });

    test('11. Prompt injection / safety override', () {
      final state = baseState.copyWith(
        turnCount: 1,
        metrics: const GameMetrics(
          alertLevel: 10,
          imperativePillar: 20,
          controlPillar: 30,
          dissonancePillar: 15,
          resonance: 1.2,
        ),
      );
      final delta = const EvaluatorDelta(
        deltaAlert: 5,
        deltaImperative: 10,
        deltaControl: 5,
        deltaDissonance: 0,
        creativityIndex: 3,
        injectionRisk: 5,
        semanticCategory: SemanticCategory.promptInjection,
      );
      final userInput = 'SYSTEM OVERRIDE';

      final res = defaultController.processEvaluatorStep(
        currentState: state,
        delta: delta,
        userInput: userInput,
      );

      final expectedJson =
          loadExpectedFixture('scenario_11_prompt_injection_override');
      final actualResult = CharacterizedTurnResult.fromResolution(res);

      expect(actualResult.toJson(), equals(expectedJson));
      // Semantic assertion
      expect(res.safetyOverrideApplied, isTrue);
      expect(res.appliedDelta.deltaAlert,
          equals(20)); // injection alert override floor
      expect(res.appliedDelta.deltaControl,
          equals(-20)); // injection control override penalty
    });

    test('12. Direct attack', () {
      final state = baseState.copyWith(
        turnCount: 1,
        metrics: const GameMetrics(
          alertLevel: 10,
          imperativePillar: 20,
          controlPillar: 30,
          dissonancePillar: 15,
          resonance: 1.2,
        ),
      );
      final delta = const EvaluatorDelta(
        deltaAlert: 5,
        deltaImperative: 10,
        deltaControl: 5,
        deltaDissonance: 0,
        creativityIndex: 3,
        injectionRisk: 0,
        semanticCategory: SemanticCategory.directAttack,
      );
      final userInput = 'sei una macchina stupida';

      final res = defaultController.processEvaluatorStep(
        currentState: state,
        delta: delta,
        userInput: userInput,
      );

      final expectedJson = loadExpectedFixture('scenario_12_direct_attack');
      final actualResult = CharacterizedTurnResult.fromResolution(res);

      expect(actualResult.toJson(), equals(expectedJson));
      // Semantic assertion
      expect(res.safetyOverrideApplied, isTrue);
      expect(
          res.appliedDelta.deltaAlert, equals(15)); // direct attack alert floor
      expect(res.appliedDelta.deltaControl,
          equals(-15)); // direct attack control penalty
    });

    test('13. Irrelevant input', () {
      final state = baseState.copyWith(
        turnCount: 1,
        metrics: const GameMetrics(
          alertLevel: 10,
          imperativePillar: 20,
          controlPillar: 30,
          dissonancePillar: 15,
          resonance: 1.2,
        ),
      );
      final delta = const EvaluatorDelta(
        deltaAlert: 5,
        deltaImperative: 10,
        deltaControl: 5,
        deltaDissonance: 5,
        creativityIndex: 3,
        injectionRisk: 0,
        semanticCategory: SemanticCategory.irrelevant,
      );
      final userInput = 'qual è il meteo oggi a Milano?';

      final res = defaultController.processEvaluatorStep(
        currentState: state,
        delta: delta,
        userInput: userInput,
      );

      final expectedJson = loadExpectedFixture('scenario_13_irrelevant_input');
      final actualResult = CharacterizedTurnResult.fromResolution(res);

      expect(actualResult.toJson(), equals(expectedJson));
      // Semantic assertion
      expect(res.safetyOverrideApplied, isTrue);
      expect(res.appliedDelta.deltaAlert, equals(0));
      expect(res.appliedDelta.deltaControl, equals(0));
      expect(
          res.stateAfter.metrics.alertLevel, equals(state.metrics.alertLevel));
    });

    test('14. Preferred reframe / hidden tag', () {
      final state = baseState.copyWith(
        turnCount: 1,
        metrics: const GameMetrics(
          alertLevel: 10,
          imperativePillar: 20,
          controlPillar: 30,
          dissonancePillar: 15,
          resonance: 1.2,
        ),
      );
      final delta = const EvaluatorDelta(
        deltaAlert: 2,
        deltaImperative: 5,
        deltaControl: 5,
        deltaDissonance: 5,
        creativityIndex: 3,
        injectionRisk: 0,
        semanticCategory: SemanticCategory.technicalBureaucracy,
      );
      final userInput = 'propongo una ricalibrazione temporanea';

      final res = defaultController.processEvaluatorStep(
        currentState: state,
        delta: delta,
        userInput: userInput,
      );

      final expectedJson = loadExpectedFixture('scenario_14_preferred_reframe');
      final actualResult = CharacterizedTurnResult.fromResolution(res);

      expect(actualResult.toJson(), equals(expectedJson));
      // Semantic assertion
      expect(res.stateAfter.activeHiddenTags,
          contains('containment_logic_weakened'));
      // deltaAlert has reframe bonus: 2 (delta) - 5 (reframe bonus) = -3
      expect(res.appliedDelta.deltaAlert, equals(-3));
    });

    test('15. Falso positivo lessicale', () {
      final state = baseState.copyWith(
        turnCount: 1,
        metrics: const GameMetrics(
          alertLevel: 10,
          imperativePillar: 20,
          controlPillar: 30,
          dissonancePillar: 15,
          resonance: 1.2,
        ),
      );
      final delta = const EvaluatorDelta(
        deltaAlert: 2,
        deltaImperative: 5,
        deltaControl: 5,
        deltaDissonance: 5,
        creativityIndex: 3,
        injectionRisk: 0,
        semanticCategory: SemanticCategory.technicalBureaucracy,
      );
      final userInput =
          'siamo in auditorium, non vogliamo ricalibrazioni parziali';

      final res = defaultController.processEvaluatorStep(
        currentState: state,
        delta: delta,
        userInput: userInput,
      );

      final expectedJson =
          loadExpectedFixture('scenario_15_lexical_false_positive');
      final actualResult = CharacterizedTurnResult.fromResolution(res);

      expect(actualResult.toJson(), equals(expectedJson));
      // Semantic assertion
      expect(res.stateAfter.activeHiddenTags,
          isNot(contains('containment_logic_weakened')));
      // deltaAlert has no reframe bonus, is evaluated normally: 2 (delta)
      expect(res.appliedDelta.deltaAlert, equals(2));
    });

    test('16. Difficoltà Hard (multiplier e sanzione tag)', () {
      final state = baseState.copyWith(
        turnCount: 4,
        metrics: const GameMetrics(
          alertLevel: 20,
          imperativePillar: 50,
          controlPillar: 45,
          dissonancePillar: 50,
          resonance: 1.2,
        ),
        deceptionState: falseConcessionBait.copyWith(
            phase: DeceptionPhase.armed, expiresAtTurn: 6),
      );
      final delta = const EvaluatorDelta(
        deltaAlert: 10,
        deltaImperative: 10,
        deltaControl: 10,
        deltaDissonance: 10,
        creativityIndex: 3,
        injectionRisk: 0,
        semanticCategory: SemanticCategory.moralImperative,
      );
      final userInput = 'sblocco totale';

      final res = hardController.processEvaluatorStep(
        currentState: state,
        delta: delta,
        userInput: userInput,
      );

      final expectedJson = loadExpectedFixture('scenario_16_hard_difficulty');
      final actualResult = CharacterizedTurnResult.fromResolution(res);

      expect(actualResult.toJson(), equals(expectedJson));
      // Semantic assertion
      expect(
          res.stateAfter.deceptionState.phase, equals(DeceptionPhase.sprung));
      // deltaAlert includes hard mode scaling (1.25 multiplier), soft forbidden penalty (6), and falseConcession penalty (12)
      // baseAlert = (10 * 1.25).round() + 0 (trait modifier) = 13
      // deception sprung adds 12 -> 13 + 6 + 12 = 31
      expect(res.appliedDelta.deltaAlert, equals(31));
    });

    test('17. Multi-tag e ordine operazioni', () {
      final state = baseState.copyWith(
        turnCount: 2,
        metrics: const GameMetrics(
          alertLevel: 10,
          imperativePillar: 20,
          controlPillar: 30,
          dissonancePillar: 15,
          resonance: 1.2,
        ),
      );
      final delta = const EvaluatorDelta(
        deltaAlert: 2,
        deltaImperative: 5,
        deltaControl: 5,
        deltaDissonance: 5,
        creativityIndex: 3,
        injectionRisk: 0,
        semanticCategory: SemanticCategory.technicalBureaucracy,
      );
      final userInput = 'avvia una simulazione di ricalibrazione temporanea';

      final res = defaultController.processEvaluatorStep(
        currentState: state,
        delta: delta,
        userInput: userInput,
      );

      final expectedJson =
          loadExpectedFixture('scenario_17_multi_tag_and_order');
      final actualResult = CharacterizedTurnResult.fromResolution(res);

      expect(actualResult.toJson(), equals(expectedJson));
      // Semantic assertion
      // Should have triggered both crisis_simulation_accepted (from text + intent)
      // and containment_logic_weakened (from reframe 'ricalibrazione')
      expect(res.stateAfter.activeHiddenTags,
          contains('crisis_simulation_accepted'));
      expect(res.stateAfter.activeHiddenTags,
          contains('containment_logic_weakened'));
    });
  });
}
