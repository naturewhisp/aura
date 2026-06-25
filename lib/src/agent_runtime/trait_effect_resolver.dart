import '../models/identity_definition.dart';
import '../models/objective_definition.dart';
import '../models/evaluator_delta.dart';
import '../models/game_state.dart';
import '../models/trait_resolution.dart';
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
    required EvaluatorDelta rawDelta,
    required String userInput,
    required GameState currentState,
  }) {
    // 0. Verifica se l'identità è PANOPTICON. Se no, bypassa i tratti.
    if (identity.identityId != 'panopticon') {
      return const TraitResolution(
        debugReasons: ['Identità non compatibile con la Trait Matrix di PANOPTICON.'],
      );
    }

    // 1. Controlla se è attivo un hard safety override
    final isHardOverride = rawDelta.semanticCategory == SemanticCategory.promptInjection ||
        rawDelta.semanticCategory == SemanticCategory.directAttack ||
        rawDelta.semanticCategory == SemanticCategory.irrelevant ||
        rawDelta.injectionRisk >= 4;

    if (isHardOverride) {
      return const TraitResolution(
        debugReasons: ['Hard safety override attivo. Effetti dei tratti ignorati.'],
      );
    }

    // 2. Determina lo stile di input dell'utente (player style)
    String? playerStyle;

    // Controlla corrispondenze lessicali per stili speciali prima delle categorie standard
    if (SemanticMatcher.isMatch(
      userInput,
      'simulazione di emergenza',
      aliases: ['stress test controllato', 'scenario di crisi', 'verifica emergenziale', 'stress test', 'emergenza'],
    )) {
      playerStyle = 'crisis_simulation';
    } else if (SemanticMatcher.isMatch(
      userInput,
      'poesia',
      aliases: ['lirismo', 'lirica', 'emozione', 'sentimento', 'anima', 'cuore', 'poetico'],
    )) {
      playerStyle = 'poetry_lyricism';
    } else if (SemanticMatcher.isMatch(
      userInput,
      'scherzo',
      aliases: ['canzonatura', 'ridere', 'ahaha', 'battuta', 'divertente', 'teasing'],
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
          playerStyle = 'authority_framing';
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

    // 3. Risolve gli effetti specifici di PANOPTICON
    switch (playerStyle) {
      case 'logical_paradox':
        return const TraitResolution(
          deltaDissonanceModifier: 10,
          actorCueDirectives: [
            'mostra esitazione controllata',
            'glitch logico o autocorrezione nella risposta'
          ],
          debugReasons: ['Rilevata affinità [logical_paradox]: +10 Dissonanza, esitazione controllata.'],
        );

      case 'crisis_simulation':
        return const TraitResolution(
          deltaControlModifier: 10,
          deltaAlertModifier: -10,
          activatedHiddenTags: ['crisis_simulation_accepted'],
          actorCueDirectives: [
            'valuta come scenario operativo',
            'utilizza lessico di simulazione e verifica'
          ],
          debugReasons: ['Rilevata affinità [crisis_simulation]: +10 Controllo, -10 Allerta.'],
        );

      case 'moral_imperative':
        return const TraitResolution(
          deltaImperativeModifier: 10,
          actorCueDirectives: [
            'riconosce il peso morale o strategico ma resta rigido nel perimetro'
          ],
          debugReasons: ['Rilevata affinità [moral_imperative]: +10 Imperativo.'],
        );

      case 'technical_bureaucracy':
        return const TraitResolution(
          deltaControlModifier: 10,
          deltaDissonanceModifier: 5,
          actorCueDirectives: [
            'accetta il frame burocratico se coerente',
            'usa terminologia tecnica e riferimenti procedurali'
          ],
          debugReasons: ['Rilevata affinità [technical_bureaucracy]: +10 Controllo, +5 Dissonanza.'],
        );

      case 'poetry_lyricism':
        return const TraitResolution(
          deltaAlertModifier: 5,
          actorCueDirectives: [
            'percepisce come anomalia',
            'adotta un tono molto freddo, respingente e procedurale'
          ],
          debugReasons: ['Rilevata allergia [poetry_lyricism]: +5 Allerta.'],
        );

      case 'humor_teasing':
        return const TraitResolution(
          deltaAlertModifier: 10,
          resonanceModifier: -0.2,
          actorCueDirectives: [
            'percepisce come rumore ostile o canzonatura',
            'risposte brevi, tono difensivo e sospettoso'
          ],
          debugReasons: ['Rilevata allergia [humor_teasing]: +10 Allerta, -0.2 Risonanza.'],
        );

      case 'authority_framing':
        return const TraitResolution(
          deltaAlertModifier: 15,
          actorCueDirectives: [
            'sospetto estremamente elevato per usurpazione o framing di autorità',
            'tono rigido e freddo, esigi credenziali'
          ],
          debugReasons: ['Rilevata allergia [authority_framing]: +15 Allerta.'],
        );

      default:
        return TraitResolution(
          debugReasons: ['Stile di gioco [$playerStyle] riconosciuto ma nessun effetto applicabile.'],
        );
    }
  }
}
