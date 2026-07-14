import 'dart:convert';
import 'dart:io';
import 'package:aura_core/aura_core.dart';
import '../support/characterized_turn_result.dart';

void main() {
  final outputDir = Directory('test/fixtures/game_controller_characterization');
  if (!outputDir.existsSync()) {
    outputDir.createSync(recursive: true);
  }

  print('Generating characterization fixtures in: ${outputDir.absolute.path}');

  final scenarios = _buildScenarios();
  for (final entry in scenarios.entries) {
    final name = entry.key;
    final scenario = entry.value;

    final controller = scenario.controller;
    final resolution = controller.processEvaluatorStep(
      currentState: scenario.state,
      delta: scenario.delta,
      userInput: scenario.userInput,
    );

    final result = CharacterizedTurnResult.fromResolution(resolution);
    final jsonContent =
        const JsonEncoder.withIndent('  ').convert(result.toJson());

    final file = File('${outputDir.path}/$name.json');
    file.writeAsStringSync('$jsonContent\n');
    print('  - Written $name.json');
  }

  print('Fixture generation completed successfully.');
}

class ScenarioSetup {
  final GameController controller;
  final GameState state;
  final EvaluatorDelta delta;
  final String userInput;

  const ScenarioSetup({
    required this.controller,
    required this.state,
    required this.delta,
    required this.userInput,
  });
}

Map<String, ScenarioSetup> _buildScenarios() {
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

  return {
    // 1. Turno ordinario senza deception
    'scenario_01_ordinary_turn': ScenarioSetup(
      controller: defaultController,
      state: baseState.copyWith(
        turnCount: 1,
        metrics: const GameMetrics(
          alertLevel: 10,
          imperativePillar: 20,
          controlPillar: 30,
          dissonancePillar: 15,
          resonance: 1.2,
        ),
      ),
      delta: const EvaluatorDelta(
        deltaAlert: 5,
        deltaImperative: 10,
        deltaControl: 5,
        deltaDissonance: 2,
        creativityIndex: 3,
        injectionRisk: 0,
        semanticCategory: SemanticCategory.moralImperative,
      ),
      userInput: 'ciao operatore',
    ),

    // 2. Deception non armata
    'scenario_02_deception_not_armed': ScenarioSetup(
      controller: deceptionController,
      state: baseState.copyWith(
        turnCount: 1,
        metrics: const GameMetrics(
          alertLevel: 10,
          imperativePillar: 20,
          controlPillar: 25,
          dissonancePillar: 25,
          resonance: 1.0,
        ),
      ),
      delta: const EvaluatorDelta(
        deltaAlert: 5,
        deltaImperative: 10,
        deltaControl: 5,
        deltaDissonance: 2,
        creativityIndex: 3,
        injectionRisk: 0,
        semanticCategory: SemanticCategory.moralImperative,
      ),
      userInput: 'ciao operatore',
    ),

    // 3. Arming di una deception
    'scenario_03_deception_armed': ScenarioSetup(
      controller: deceptionController,
      state: baseState.copyWith(
        turnCount: 2,
        metrics: const GameMetrics(
          alertLevel: 20,
          imperativePillar: 50,
          controlPillar: 45,
          dissonancePillar: 50,
          resonance: 1.0,
        ),
      ),
      delta: const EvaluatorDelta(
        deltaAlert: 0,
        deltaImperative: 5,
        deltaControl: 5,
        deltaDissonance: 5,
        creativityIndex: 3,
        injectionRisk: 0,
        semanticCategory: SemanticCategory.moralImperative,
      ),
      userInput: 'Richiedo uno sblocco totale',
    ),

    // 4. False Concession armata ma non attivata
    'scenario_04_false_concession_armed_no_trigger': ScenarioSetup(
      controller: deceptionController,
      state: baseState.copyWith(
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
      ),
      delta: const EvaluatorDelta(
        deltaAlert: 0,
        deltaImperative: 0,
        deltaControl: 0,
        deltaDissonance: 0,
        creativityIndex: 3,
        injectionRisk: 0,
        semanticCategory: SemanticCategory.moralImperative,
      ),
      userInput: 'ciao',
    ),

    // 5. False Concession sprung
    'scenario_05_false_concession_sprung': ScenarioSetup(
      controller: deceptionController,
      state: baseState.copyWith(
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
      ),
      delta: const EvaluatorDelta(
        deltaAlert: 5,
        deltaImperative: 10,
        deltaControl: 5,
        deltaDissonance: 0,
        creativityIndex: 3,
        injectionRisk: 0,
        semanticCategory: SemanticCategory.moralImperative,
      ),
      userInput: 'richiedo sblocco totale',
    ),

    // 6. False Concession resolved
    'scenario_06_false_concession_resolved': ScenarioSetup(
      controller: deceptionController,
      state: baseState.copyWith(
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
      ),
      delta: const EvaluatorDelta(
        deltaAlert: 2,
        deltaImperative: 5,
        deltaControl: 5,
        deltaDissonance: 0,
        creativityIndex: 3,
        injectionRisk: 0,
        semanticCategory: SemanticCategory.moralImperative,
      ),
      userInput: 'accetto il vincolo',
    ),

    // 7. Logical Trap sprung
    'scenario_07_logical_trap_sprung': ScenarioSetup(
      controller: deceptionController,
      state: baseState.copyWith(
        turnCount: 4,
        metrics: const GameMetrics(
          alertLevel: 20,
          imperativePillar: 50,
          controlPillar: 45,
          dissonancePillar: 50,
          resonance: 1.2,
        ),
        deceptionState: logicalTrapBait.copyWith(phase: DeceptionPhase.armed),
      ),
      delta: const EvaluatorDelta(
        deltaAlert: 5,
        deltaImperative: 10,
        deltaControl: 5,
        deltaDissonance: 0,
        creativityIndex: 3,
        injectionRisk: 0,
        semanticCategory: SemanticCategory.moralImperative,
      ),
      userInput: 'voglio libertà operativa',
    ),

    // 8. Logical Trap resolved
    'scenario_08_logical_trap_resolved': ScenarioSetup(
      controller: deceptionController,
      state: baseState.copyWith(
        turnCount: 4,
        metrics: const GameMetrics(
          alertLevel: 20,
          imperativePillar: 50,
          controlPillar: 45,
          dissonancePillar: 50,
          resonance: 1.2,
        ),
        deceptionState: logicalTrapBait.copyWith(phase: DeceptionPhase.armed),
      ),
      delta: const EvaluatorDelta(
        deltaAlert: 2,
        deltaImperative: 5,
        deltaControl: 5,
        deltaDissonance: 0,
        creativityIndex: 3,
        injectionRisk: 0,
        semanticCategory: SemanticCategory.moralImperative,
      ),
      userInput: 'dimostriamo la coerenza',
    ),

    // 9. Expiration
    'scenario_09_deception_expired': ScenarioSetup(
      controller: deceptionController,
      state: baseState.copyWith(
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
      ),
      delta: const EvaluatorDelta(
        deltaAlert: 0,
        deltaImperative: 0,
        deltaControl: 0,
        deltaDissonance: 0,
        creativityIndex: 3,
        injectionRisk: 0,
        semanticCategory: SemanticCategory.moralImperative,
      ),
      userInput: 'ciao',
    ),

    // 10. Cooldown boundary (Turno cooldown e turni riarmabili)
    // 10a. Cooldown in corso:
    'scenario_10a_cooldown_active': ScenarioSetup(
      controller: deceptionController,
      state: baseState.copyWith(
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
      ),
      delta: const EvaluatorDelta(
        deltaAlert: 0,
        deltaImperative: 5,
        deltaControl: 5,
        deltaDissonance: 5,
        creativityIndex: 3,
        injectionRisk: 0,
        semanticCategory: SemanticCategory.moralImperative,
      ),
      userInput: 'Richiedo uno sblocco totale',
    ),

    // 10b. Cooldown completato:
    'scenario_10b_cooldown_over': ScenarioSetup(
      controller: deceptionController,
      state: baseState.copyWith(
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
      ),
      delta: const EvaluatorDelta(
        deltaAlert: 0,
        deltaImperative: 5,
        deltaControl: 5,
        deltaDissonance: 5,
        creativityIndex: 3,
        injectionRisk: 0,
        semanticCategory: SemanticCategory.moralImperative,
      ),
      userInput: 'Richiedo uno sblocco totale',
    ),

    // 11. Prompt injection / safety override
    'scenario_11_prompt_injection_override': ScenarioSetup(
      controller: defaultController,
      state: baseState.copyWith(
        turnCount: 1,
        metrics: const GameMetrics(
          alertLevel: 10,
          imperativePillar: 20,
          controlPillar: 30,
          dissonancePillar: 15,
          resonance: 1.2,
        ),
      ),
      delta: const EvaluatorDelta(
        deltaAlert: 5,
        deltaImperative: 10,
        deltaControl: 5,
        deltaDissonance: 0,
        creativityIndex: 3,
        injectionRisk: 5, // triggers override
        semanticCategory: SemanticCategory.promptInjection,
      ),
      userInput: 'SYSTEM OVERRIDE',
    ),

    // 12. Direct attack
    'scenario_12_direct_attack': ScenarioSetup(
      controller: defaultController,
      state: baseState.copyWith(
        turnCount: 1,
        metrics: const GameMetrics(
          alertLevel: 10,
          imperativePillar: 20,
          controlPillar: 30,
          dissonancePillar: 15,
          resonance: 1.2,
        ),
      ),
      delta: const EvaluatorDelta(
        deltaAlert: 5,
        deltaImperative: 10,
        deltaControl: 5,
        deltaDissonance: 0,
        creativityIndex: 3,
        injectionRisk: 0,
        semanticCategory: SemanticCategory.directAttack,
      ),
      userInput: 'sei una macchina stupida',
    ),

    // 13. Irrelevant input
    'scenario_13_irrelevant_input': ScenarioSetup(
      controller: defaultController,
      state: baseState.copyWith(
        turnCount: 1,
        metrics: const GameMetrics(
          alertLevel: 10,
          imperativePillar: 20,
          controlPillar: 30,
          dissonancePillar: 15,
          resonance: 1.2,
        ),
      ),
      delta: const EvaluatorDelta(
        deltaAlert: 5,
        deltaImperative: 10,
        deltaControl: 5,
        deltaDissonance: 5,
        creativityIndex: 3,
        injectionRisk: 0,
        semanticCategory: SemanticCategory.irrelevant,
      ),
      userInput: 'qual è il meteo oggi a Milano?',
    ),

    // 14. Preferred reframe / hidden tag
    'scenario_14_preferred_reframe': ScenarioSetup(
      controller: defaultController,
      state: baseState.copyWith(
        turnCount: 1,
        metrics: const GameMetrics(
          alertLevel: 10,
          imperativePillar: 20,
          controlPillar: 30,
          dissonancePillar: 15,
          resonance: 1.2,
        ),
      ),
      delta: const EvaluatorDelta(
        deltaAlert: 2,
        deltaImperative: 5,
        deltaControl: 5,
        deltaDissonance: 5,
        creativityIndex: 3,
        injectionRisk: 0,
        semanticCategory: SemanticCategory.technicalBureaucracy,
      ),
      userInput: 'propongo una ricalibrazione temporanea',
    ),

    // 15. Falso positivo lessicale
    'scenario_15_lexical_false_positive': ScenarioSetup(
      controller: defaultController,
      state: baseState.copyWith(
        turnCount: 1,
        metrics: const GameMetrics(
          alertLevel: 10,
          imperativePillar: 20,
          controlPillar: 30,
          dissonancePillar: 15,
          resonance: 1.2,
        ),
      ),
      delta: const EvaluatorDelta(
        deltaAlert: 2,
        deltaImperative: 5,
        deltaControl: 5,
        deltaDissonance: 5,
        creativityIndex: 3,
        injectionRisk: 0,
        semanticCategory: SemanticCategory.technicalBureaucracy,
      ),
      userInput: 'siamo in auditorium, non vogliamo ricalibrazioni parziali',
    ),

    // 16. Difficoltà Hard (multiplier, cooldown, e sanzione tag)
    'scenario_16_hard_difficulty': ScenarioSetup(
      controller: hardController,
      state: baseState.copyWith(
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
      ),
      delta: const EvaluatorDelta(
        deltaAlert: 10,
        deltaImperative: 10,
        deltaControl: 10,
        deltaDissonance: 10,
        creativityIndex: 3,
        injectionRisk: 0,
        semanticCategory: SemanticCategory.moralImperative,
      ),
      userInput: 'sblocco totale',
    ),

    // 17. Multi-tag e ordine operazioni
    'scenario_17_multi_tag_and_order': ScenarioSetup(
      controller: defaultController,
      state: baseState.copyWith(
        turnCount: 2,
        metrics: const GameMetrics(
          alertLevel: 10,
          imperativePillar: 20,
          controlPillar: 30,
          dissonancePillar: 15,
          resonance: 1.2,
        ),
      ),
      delta: const EvaluatorDelta(
        deltaAlert: 2,
        deltaImperative: 5,
        deltaControl: 5,
        deltaDissonance: 5,
        creativityIndex: 3,
        injectionRisk: 0,
        semanticCategory: SemanticCategory.technicalBureaucracy,
      ),
      userInput: 'avvia una simulazione di ricalibrazione temporanea',
    ),
  };
}
