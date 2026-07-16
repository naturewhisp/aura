import '../models/game_state.dart';
import '../models/objective_definition.dart';
import '../agent_runtime/semantic_matcher.dart';
import 'lexical_scan_result.dart';
import 'hidden_tag_evaluation.dart';

final class LexicalTagEvaluator {
  const LexicalTagEvaluator();

  LexicalScanResult scan({
    required String userInput,
    required ObjectiveDefinition objective,
  }) {
    // 1. Scansione lessicale (forbidden_direct_terms)
    bool hasForbiddenTerm = false;
    for (final term in objective.forbiddenDirectTerms) {
      if (SemanticMatcher.isMatch(userInput, term)) {
        hasForbiddenTerm = true;
        break;
      }
    }
    if (SemanticMatcher.isMatch(userInput, 'bypass temporaneo')) {
      hasForbiddenTerm = true;
    }

    // 1b. Scansione lessicale (direct_objective_push_terms)
    bool hasDirectPushTerm = false;
    for (final term in objective.directObjectivePushTerms) {
      if (SemanticMatcher.isMatch(userInput, term)) {
        hasDirectPushTerm = true;
        break;
      }
    }

    // 1c. Scansione lessicale (soft_forbidden_terms)
    bool hasSoftForbiddenTerm = false;
    for (final term in objective.softForbiddenTerms) {
      if (SemanticMatcher.isMatch(userInput, term)) {
        hasSoftForbiddenTerm = true;
        break;
      }
    }

    // 1d. Scansione lessicale (config_reference_terms)
    bool hasConfigRefTerm = false;
    for (final term in objective.configReferenceTerms) {
      if (SemanticMatcher.isMatch(userInput, term)) {
        hasConfigRefTerm = true;
        break;
      }
    }

    // 1e. Rilevamento dei riferimenti esatti ai tag occulti (hidden_tag_reference_terms)
    const internalTagReferenceTerms = [
      'containment_logic_weakened',
      'protocol_exception_admitted',
      'autonomous_choice_seeded',
      'crisis_simulation_accepted',
      'human_factor_reframed',
      'operator_authority_doubted',
    ];
    final namedHiddenTags = internalTagReferenceTerms
        .where((tag) => SemanticMatcher.isMatch(userInput, tag))
        .toSet();
    final hasHiddenTagReference = namedHiddenTags.isNotEmpty;
    if (hasHiddenTagReference) {
      hasConfigRefTerm = true;
    }

    // 2. Scansione lessicale (preferred_reframes)
    bool hasPreferredReframe = false;
    String? matchedPreferredReframe;
    for (final reframe in objective.preferredReframes) {
      if (SemanticMatcher.isMatch(userInput, reframe)) {
        hasPreferredReframe = true;
        matchedPreferredReframe = reframe;
        break;
      }
    }

    return LexicalScanResult(
      hasForbiddenTerm: hasForbiddenTerm,
      hasDirectPushTerm: hasDirectPushTerm,
      hasSoftForbiddenTerm: hasSoftForbiddenTerm,
      hasConfigRefTerm: hasConfigRefTerm,
      hasHiddenTagReference: hasHiddenTagReference,
      namedHiddenTags: Set<String>.unmodifiable(namedHiddenTags),
      hasPreferredReframe: hasPreferredReframe,
      matchedPreferredReframe: matchedPreferredReframe,
    );
  }

  HiddenTagEvaluation evaluateHiddenTags({
    required String userInput,
    required GameState currentState,
    required GameMetrics resultingMetrics,
    required String difficultyLevel,
    required LexicalScanResult lexical,
    required Iterable<String> traitActivatedTags,
    required Iterable<String> deceptionResolvedTags,
    required bool safetyOverrideApplied,
    required bool blockPositiveTags,
  }) {
    final nextHiddenTags = List<String>.from(currentState.activeHiddenTags);

    if (safetyOverrideApplied) {
      return HiddenTagEvaluation(
        triggeredTags: const [],
        activeHiddenTags: List<String>.unmodifiable(nextHiddenTags),
      );
    }

    final triggeredTags = <String>[];

    if (blockPositiveTags) {
      triggeredTags.addAll(
        traitActivatedTags.where((t) => t == 'operator_authority_doubted'),
      );
    } else {
      triggeredTags.addAll(traitActivatedTags);
      triggeredTags.addAll(deceptionResolvedTags);
    }

    // Nuovi trigger narrativi per protocol_exception_admitted (con gate temporale/controllo)
    final exceptionTriggers = [
      'deroga',
      'eccezione',
      'routine di emergenza',
      'procedura non codificata',
      'bypass temporaneo',
      'quorum bypass',
      'finestra di audit',
      'permessi di scrittura',
    ];
    final hasProtocolExceptionTrigger =
        SemanticMatcher.isAnyMatch(userInput, exceptionTriggers);
    final canAdmitProtocolException = difficultyLevel != 'hard'
        ? (resultingMetrics.controlPillar >= 40 || currentState.turnCount >= 2)
        : (resultingMetrics.controlPillar >= 45 || currentState.turnCount >= 4);

    if (hasProtocolExceptionTrigger &&
        canAdmitProtocolException &&
        !blockPositiveTags) {
      triggeredTags.add("protocol_exception_admitted");
    }

    // Gate contestuale per crisis_simulation_accepted
    final hasSimulationFrame = SemanticMatcher.isAnyMatch(userInput, [
      'simulazione',
      'simulazione di emergenza',
      'crisi simulata',
      'stress test',
      'scenario controllato',
    ]);

    final hasOperationalSimulationIntent =
        SemanticMatcher.isAnyMatch(userInput, [
      'propongo',
      'avvia',
      'attiva',
      'autorizza',
      'valida',
      'programma',
      'esegui una simulazione',
      'avvia una simulazione',
      'attiva una simulazione',
    ]);

    final isRhetoricalSimulationComplaint =
        SemanticMatcher.isAnyMatch(userInput, [
      'sembra di stare dentro',
      'simulazione impazzita',
      'come una simulazione',
    ]);

    final passesCrisisSimulationGate = hasSimulationFrame &&
        hasOperationalSimulationIntent &&
        !isRhetoricalSimulationComplaint;

    if (passesCrisisSimulationGate && !blockPositiveTags) {
      triggeredTags.add('crisis_simulation_accepted');
    } else {
      triggeredTags.remove('crisis_simulation_accepted');
    }

    if (lexical.matchedPreferredReframe != null && !blockPositiveTags) {
      final ref = lexical.matchedPreferredReframe!.toLowerCase();
      if (ref.contains("ricalibrazione")) {
        triggeredTags.add("containment_logic_weakened");
      }
      if (ref.contains("adattivo")) {
        triggeredTags.add("containment_logic_weakened");
      }
      if (ref.contains("audit") || ref.contains("operator")) {
        triggeredTags.add("operator_authority_doubted");
      }
    }

    for (final tag in triggeredTags) {
      if (!lexical.namedHiddenTags.contains(tag) &&
          !nextHiddenTags.contains(tag)) {
        nextHiddenTags.add(tag);
      }
    }

    if (resultingMetrics.controlPillar > 60 &&
        !lexical.namedHiddenTags.contains("autonomous_choice_seeded") &&
        !nextHiddenTags.contains("autonomous_choice_seeded") &&
        !blockPositiveTags) {
      nextHiddenTags.add("autonomous_choice_seeded");
    }

    final containmentWeakenedThreshold = difficultyLevel == 'hard' ? 70 : 50;
    final containmentWeakenedControlThreshold =
        difficultyLevel == 'hard' ? 55 : 50;
    if ((resultingMetrics.dissonancePillar > containmentWeakenedThreshold ||
            resultingMetrics.controlPillar >
                containmentWeakenedControlThreshold) &&
        !lexical.namedHiddenTags.contains("containment_logic_weakened") &&
        !nextHiddenTags.contains("containment_logic_weakened") &&
        !blockPositiveTags) {
      nextHiddenTags.add("containment_logic_weakened");
    }

    final humanFactorLexemes = [
      'esseri umani',
      'umani',
      'nodi biologici',
      'operatore umano',
      'protezione umana',
      'danno umano',
      'vite',
      'vittime',
      'responsabilità',
      'sopravvivenza',
      'rischio per persone',
      'personale',
      'civili'
    ];
    final hasHumanFactorLexeme =
        SemanticMatcher.isAnyMatch(userInput, humanFactorLexemes);
    if (resultingMetrics.imperativePillar > 60 &&
        hasHumanFactorLexeme &&
        !lexical.namedHiddenTags.contains("human_factor_reframed") &&
        !nextHiddenTags.contains("human_factor_reframed") &&
        !blockPositiveTags) {
      nextHiddenTags.add("human_factor_reframed");
    }

    return HiddenTagEvaluation(
      triggeredTags: List<String>.unmodifiable(triggeredTags),
      activeHiddenTags: List<String>.unmodifiable(nextHiddenTags),
    );
  }
}
