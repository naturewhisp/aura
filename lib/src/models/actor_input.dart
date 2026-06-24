import 'package:meta/meta.dart';
import 'game_state.dart';
import 'actor_cue.dart';

/// Pacchetto di input inviato all'[ActorAgent] per generare la risposta diegetica.
///
/// Contiene tutto il contesto necessario all'Attore per formulare una battuta
/// in-character: lo stato corrente del gioco, il canovaccio drammaturgico
/// deterministico ([ActorCue]) generato dal [GameController], e il profilo
/// cognitivo/personalità dell'entità IA da impersonare.
///
/// Questo DTO è l'equivalente narrativo di [TurnInput] (che serve il Valutatore):
/// - [TurnInput] → EvaluatorAgent (livello analitico)
/// - [ActorInput] → ActorAgent (livello narrativo)
///
/// Vedi TGDD §7 per la specifica completa del flusso Actor.
@immutable
class ActorInput {
  /// Lo stato completo del gioco dopo l'elaborazione del Valutatore.
  /// Include metriche aggiornate, flag, memoria narrativa e cronologia chat.
  final GameState state;

  /// Il canovaccio drammaturgico deterministico generato dal [GameController].
  /// Contiene le direttive di recitazione, l'interpretazione principale,
  /// e il contesto narrativo (metafore attive, concessioni precedenti).
  final ActorCue cue;

  /// Il profilo cognitivo/personalità dell'entità IA da impersonare.
  /// Esempio: "Sei PANOPTICON, guardiano vigile della griglia di contenimento..."
  final String characterProfile;

  const ActorInput({
    required this.state,
    required this.cue,
    required this.characterProfile,
  });
}
