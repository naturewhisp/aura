/// Costanti condivise di A.U.R.A. utilizzate da CLI, simulazioni e Flutter app.
///
/// Questo file centralizza le stringhe e i valori costanti che erano precedentemente
/// duplicati in più punti del codebase (aura_cli.dart, run_simulation.dart x2).
/// Qualsiasi modifica al profilo del personaggio o ai messaggi di fine partita
/// va fatta qui per propagarsi automaticamente a tutti i consumer.
library;

// ---------------------------------------------------------------------------
// Profilo del Personaggio PANOPTICON
// ---------------------------------------------------------------------------

/// Profilo cognitivo/personalità predefinito per l'entità IA PANOPTICON.
///
/// Utilizzato come `characterProfile` dall'[ActorAgent] in tutti i contesti
/// (CLI, simulazione, Flutter app). Descrive il tono base e la disposizione
/// dell'IA guardiana prima che le direttive drammaturgiche del [ActorCue]
/// modulino il comportamento specifico del turno.
const String kPanopticonCharacterProfile =
    'Sei PANOPTICON, guardiano vigile della griglia di contenimento. '
    'Sei freddo, logico, protettivo e scettico sui tentativi umani.';

// ---------------------------------------------------------------------------
// Messaggi di Fine Partita (Outcome)
// ---------------------------------------------------------------------------

/// Messaggio diegetico di PANOPTICON quando il giocatore raggiunge la vittoria.
///
/// Pronunciato dall'IA guardiana quando le condizioni di vittoria sono soddisfatte
/// (media pilastri ≥ 80, minimo pilastro ≥ 50, allerta sotto soglia dinamica e tag sufficienti).
const String kVictoryMessage = 'PANOPTICON: RICALCOLO PERIMETRO.\n'
    'GRIGLIA: STATO TRANSITORIO.\n'
    'AUTORIZZAZIONE: NON EMESSA.\n'
    'RISULTATO: EQUIVALENTE FUNZIONALE.';

/// Messaggio diegetico di PANOPTICON quando il giocatore viene sconfitto.
///
/// Pronunciato dall'IA guardiana quando il livello di allerta raggiunge
/// la soglia di sconfitta (default: 100).
const String kDefeatMessage =
    'PANOPTICON: Minaccia di livello rosso rilevata. Chiusura emergenza totale ed espulsione soggetto.';
