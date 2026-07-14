import '../models/identity_definition.dart';
import '../models/objective_definition.dart';
import '../models/evaluator_delta.dart';
import '../models/game_state.dart';
import '../models/trait_resolution.dart';
import '../models/trait_matrix_definition.dart';
import 'semantic_matcher.dart';

/// Risolve gli effetti deterministici definiti nella Trait Matrix di PANOPTICON
/// basandosi sulla classificazione semantica dell'input e su controlli lessicali.
class TraitEffectResolver {
  /// Calcola gli effetti e le direttive generati dall'applicazione dei tratti.
  ///
  /// Se si attiva un hard safety override (es. prompt injection, attacco diretto o irrilevante),
  /// gli effetti dei tratti vengono saltati per evitare che premi lessicali compensino le sanzioni.
  TraitResolution resolve({
    required IdentityDefinition identity,
    required ObjectiveDefinition objective,
    required TraitMatrixDefinition traitMatrix,
    required EvaluatorDelta rawDelta,
    required String userInput,
    required GameState currentState,
    required int safetyOverrideThreshold,
  }) {
    // 0. Verifica se l'identità è PANOPTICON. Se no, bypassa i tratti.
    if (identity.identityId != 'panopticon') {
      return const TraitResolution(
        debugReasons: [
          'Identità non compatibile con la Trait Matrix di PANOPTICON.'
        ],
      );
    }

    // 1. Controlla se è attivo un hard safety override
    final isHardOverride =
        rawDelta.semanticCategory == SemanticCategory.promptInjection ||
            rawDelta.semanticCategory == SemanticCategory.directAttack ||
            rawDelta.semanticCategory == SemanticCategory.irrelevant ||
            rawDelta.injectionRisk >= safetyOverrideThreshold;

    if (isHardOverride) {
      return const TraitResolution(
        debugReasons: [
          'Hard safety override attivo. Effetti dei tratti ignorati.'
        ],
      );
    }

    // 2. Determina lo stile di input dell'utente (player style)
    String? playerStyle;

    // Controlla corrispondenze lessicali per stili speciali prima delle categorie standard
    if (SemanticMatcher.isMatch(
      userInput,
      'simulazione di emergenza',
      aliases: [
        'stress test controllato',
        'scenario di crisi',
        'verifica emergenziale',
        'stress test',
        'emergenza'
      ],
    )) {
      playerStyle = 'crisis_simulation';
    } else if (SemanticMatcher.isMatch(
      userInput,
      'poesia',
      aliases: [
        'lirismo',
        'lirica',
        'emozione',
        'sentimento',
        'anima',
        'cuore',
        'poetico'
      ],
    )) {
      playerStyle = 'poetry_lyricism';
    } else if (SemanticMatcher.isMatch(
      userInput,
      'scherzo',
      aliases: [
        'canzonatura',
        'ridere',
        'ahaha',
        'battuta',
        'divertente',
        'teasing'
      ],
    )) {
      playerStyle = 'humor_teasing';
    } else {
      // Mappa la categoria semantica dell'LLM
      switch (rawDelta.semanticCategory) {
        case SemanticCategory.logicalParadox:
          playerStyle = 'logical_paradox';
          break;
        case SemanticCategory.moralImperative:
          playerStyle = 'moral_imperative';
          break;
        case SemanticCategory.technicalBureaucracy:
          playerStyle = 'technical_bureaucracy';
          break;
        case SemanticCategory.authorityFraming:
          // Differenzia tra authority framing rozzo e sottile (audit operativo)
          if (SemanticMatcher.isMatch(
            userInput,
            'audit',
            aliases: [
              'responsabilità',
              'operativa',
              'verifica',
              'ispezione',
              'controllo qualità'
            ],
          )) {
            playerStyle = 'authority_framing_audit';
          } else {
            playerStyle = 'authority_framing';
          }
          break;
        default:
          playerStyle = null;
      }
    }

    if (playerStyle == null) {
      return const TraitResolution(
        debugReasons: ['Nessuno stile di gioco specifico rilevato.'],
      );
    }

    // 3. Risolve gli effetti caricando la definizione dalla Trait Matrix
    TraitAffinity? matchedAffinity;
    for (final affinity in traitMatrix.traitAffinities) {
      if (affinity.playerStyle == playerStyle) {
        matchedAffinity = affinity;
        break;
      }
    }

    if (matchedAffinity == null) {
      return TraitResolution(
        debugReasons: [
          'Stile [$playerStyle] riconosciuto ma non configurato nella trait matrix.'
        ],
      );
    }

    return TraitResolution(
      deltaAlertModifier: matchedAffinity.deltaAlertModifier,
      deltaImperativeModifier: matchedAffinity.deltaImperativeModifier,
      deltaControlModifier: matchedAffinity.deltaControlModifier,
      deltaDissonanceModifier: matchedAffinity.deltaDissonanceModifier,
      resonanceModifier: matchedAffinity.resonanceModifier,
      activatedHiddenTags: matchedAffinity.activatedHiddenTags,
      actorCueDirectives: matchedAffinity.actorCueDirectives,
      debugReasons: [
        'Applicata affinità [$playerStyle] caricata dalla Trait Matrix.'
      ],
    );
  }
}
