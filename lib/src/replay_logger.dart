import 'package:meta/meta.dart';
import 'models/evaluator_delta.dart';

/// Rappresenta un singolo turno registrato all'interno del registro di replay (replay log).
///
/// Contiene tutti i dettagli dello scambio: l'input del giocatore, l'output strutturato del valutatore,
/// lo stato precedente e successivo alla transazione, la risposta dell'attore, i dettagli del modello
/// LLM utilizzato e le metriche di latenza temporale.
@immutable
class ReplayEntry {
  /// L'identificatore progressivo o numero del turno.
  final int turnId;

  /// L'input testuale originario inserito dal giocatore.
  final String userInput;

  /// Il delta delle metriche calcolato e applicato dall'agente valutatore.
  final EvaluatorDelta evaluatorOutput;

  /// La mappa rappresentante lo stato di gioco prima dell'elaborazione del turno.
  final Map<String, dynamic> stateBefore;

  /// La mappa rappresentante lo stato di gioco dopo l'elaborazione del turno.
  final Map<String, dynamic> stateAfter;

  /// La risposta diegetica prodotta dall'agente attore.
  final String actorResponse;

  /// L'identificatore univoco della richiesta inviata all'agente attore.
  final String actorRequestId;

  /// L'hash crittografico o firma di validazione associato alla risposta dell'attore.
  final String actorResponseHash;

  /// Il modello LLM utilizzato per l'inferenza del valutatore.
  final String evaluatorModel;

  /// Il modello LLM utilizzato per l'inferenza dell'attore.
  final String actorModel;

  /// La latenza totale di elaborazione misurata in millisecondi.
  final int latencyTotalMs;

  /// Costruttore costante per inizializzare una voce di replay.
  const ReplayEntry({
    required this.turnId,
    required this.userInput,
    required this.evaluatorOutput,
    required this.stateBefore,
    required this.stateAfter,
    required this.actorResponse,
    required this.actorRequestId,
    required this.actorResponseHash,
    required this.evaluatorModel,
    required this.actorModel,
    required this.latencyTotalMs,
  });

  /// Costruttore factory per ripristinare o decodificare una voce di replay a partire da una mappa JSON.
  factory ReplayEntry.fromJson(Map<String, dynamic> json) {
    final runtime = json['runtime'] as Map<String, dynamic>? ?? const {};
    return ReplayEntry(
      turnId: json['turn_id'] as int? ?? 0,
      userInput: json['user_input'] as String? ?? '',
      evaluatorOutput: EvaluatorDelta.fromJson(json['evaluator_output'] ?? const {}),
      stateBefore: Map<String, dynamic>.from(json['state_before'] ?? const {}),
      stateAfter: Map<String, dynamic>.from(json['state_after'] ?? const {}),
      actorResponse: json['actor_response'] as String? ?? '',
      actorRequestId: json['actor_request_id'] as String? ?? '',
      actorResponseHash: json['actor_response_hash'] as String? ?? '',
      evaluatorModel: runtime['evaluator_model'] as String? ?? '',
      actorModel: runtime['actor_model'] as String? ?? '',
      latencyTotalMs: runtime['latency_total_ms'] as int? ?? 0,
    );
  }

  /// Converte la voce di replay in una mappa JSON conforme alla sezione 16.1 del TGDD.
  Map<String, dynamic> toJson() {
    return {
      'turn_id': turnId,
      'user_input': userInput,
      'evaluator_output': evaluatorOutput.toJson(),
      'state_before': stateBefore,
      'state_after': stateAfter,
      'actor_response': actorResponse,
      'actor_request_id': actorRequestId,
      'actor_response_hash': actorResponseHash,
      'runtime': {
        'evaluator_model': evaluatorModel,
        'actor_model': actorModel,
        'latency_total_ms': latencyTotalMs,
      }
    };
  }
}

/// Gestisce e aggrega i registri dei replay per l'intera sessione di gioco.
///
/// Memorizza l'elenco sequenziale di tutte le voci registrate ([ReplayEntry])
/// per consentire l'esportazione dello storico della partita e l'analisi del gameplay.
class ReplayLogger {
  /// L'identificatore univoco della sessione di gioco associata.
  final String sessionId;
  final List<ReplayEntry> _entries = [];

  /// Inizializza il logger per la sessione specificata.
  ReplayLogger({required this.sessionId});

  /// Restituisce una lista non modificabile di tutte le voci registrate finora.
  List<ReplayEntry> get entries => List.unmodifiable(_entries);

  /// Registra e aggiunge una nuova voce di replay associata a un turno completato.
  void logTurn(ReplayEntry entry) {
    _entries.add(entry);
  }

  /// Converte l'intera sessione di log in una mappa compatibile con il formato JSON.
  Map<String, dynamic> toJson() {
    return {
      'session_id': sessionId,
      'total_turns': _entries.length,
      'entries': _entries.map((e) => e.toJson()).toList(),
    };
  }

  /// Costruttore factory per ripristinare una sessione di logging a partire da dati JSON.
  factory ReplayLogger.fromJson(Map<String, dynamic> json) {
    final logger = ReplayLogger(sessionId: json['session_id'] as String? ?? '');
    final list = json['entries'] as List? ?? const [];
    for (var item in list) {
      logger.logTurn(ReplayEntry.fromJson(Map<String, dynamic>.from(item)));
    }
    return logger;
  }
}
