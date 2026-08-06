import 'package:meta/meta.dart';
import 'models/evaluator_delta.dart';
import 'models/user_profile.dart';

/// Tipi di eventi registrabili all'interno del replay.
enum ReplayEventType {
  userTurn('user_turn'),
  hint('hint'),
  deceptionBait('deception_bait'),
  deceptionResolution('deception_resolution'),
  system('system');

  final String value;
  const ReplayEventType(this.value);

  static ReplayEventType fromString(String val) {
    return ReplayEventType.values.firstWhere(
      (e) => e.value == val,
      orElse: () => ReplayEventType.userTurn,
    );
  }
}

/// Rappresenta una singola voce del registro di replay (replay log).
///
/// Registra in modo immutabile l'input del giocatore, le variazioni delle metriche (delta),
/// le risposte dell'attore e della fiction, oltre ai dettagli sul modello
/// LLM utilizzato e le metriche di latenza temporale.
@immutable
class ReplayEntry {
  /// L'identificatore progressivo o numero del turno.
  final int turnId;

  /// L'input testuale originario inserito dal giocatore.
  final String userInput;

  /// Lo snapshot del nome visualizzato dell'utente al momento del turno (valido solo per i turni del giocatore).
  final String? displayNameSnapshot;

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

  /// Il modello LLM o alias richiesto per l'inferenza del valutatore.
  final String evaluatorModel;

  /// Il valutatore o motore che ha realmente calcolato il turno.
  final String actualEvaluator;

  /// La modalità di esecuzione del valutatore (es. llmJsonSchema, ruleBasedFallback).
  final String? evaluatorExecutionMode;

  /// Indica se l'esecuzione è degradata al fallback basato su regole.
  final bool usedRuleFallback;

  /// Motivo diagnostico sanitizzato dell'eventuale primo fallimento primario.
  final String? fallbackReason;

  /// Il modello LLM utilizzato per l'inferenza dell'attore.
  final String actorModel;

  /// La latenza totale di elaborazione misurata in millisecondi.
  final int latencyTotalMs;

  /// L'identificatore univoco del singolo evento/turno.
  final String eventId;

  /// Il tipo di evento registrato (user_turn, hint, ecc.).
  final ReplayEventType eventType;

  /// Il turno effettivo di gioco al momento dell'evento.
  final int gameplayTurnId;

  /// Il progressivo assoluto dell'evento nella sessione.
  final int sequenceId;

  /// L'esito dettagliato della risoluzione del Deception Layer in questo turno.
  final Map<String, dynamic> deceptionResolution;

  /// L'esito dettagliato della risoluzione dell'override in questo turno, se applicabile.
  final Map<String, dynamic>? overrideResolution;

  /// Costruttore costante per inizializzare una voce di replay.
  const ReplayEntry({
    required this.turnId,
    required this.userInput,
    this.displayNameSnapshot,
    required this.evaluatorOutput,
    required this.stateBefore,
    required this.stateAfter,
    required this.actorResponse,
    required this.actorRequestId,
    required this.actorResponseHash,
    required this.evaluatorModel,
    String? actualEvaluator,
    this.evaluatorExecutionMode,
    this.usedRuleFallback = false,
    this.fallbackReason,
    required this.actorModel,
    required this.latencyTotalMs,
    String? eventId,
    this.eventType = ReplayEventType.userTurn,
    int? gameplayTurnId,
    int? sequenceId,
    this.deceptionResolution = const {
      'kind': 'none',
      'result': 'none',
      'bait_id': null,
      'applied_alert_penalty': 0,
      'applied_resonance_penalty': 0.0,
    },
    this.overrideResolution,
  })  : actualEvaluator = actualEvaluator ?? evaluatorModel,
        eventId = eventId ?? "$actorRequestId-evt",
        gameplayTurnId = gameplayTurnId ?? turnId,
        sequenceId = sequenceId ?? turnId;

  /// Costruttore factory per ripristinare o decodificare una voce di replay a partire da una mappa JSON.
  factory ReplayEntry.fromJson(Map<String, dynamic> json) {
    final runtime = json['runtime'] as Map<String, dynamic>? ?? const {};

    Map<String, dynamic> deceptionResolutionMap = const {
      'kind': 'none',
      'result': 'none',
      'bait_id': null,
      'applied_alert_penalty': 0,
      'applied_resonance_penalty': 0.0,
    };
    if (json['deception_resolution'] != null) {
      if (json['deception_resolution'] is Map) {
        deceptionResolutionMap =
            Map<String, dynamic>.from(json['deception_resolution'] as Map);
      } else if (json['deception_resolution'] is String) {
        final String resStr = json['deception_resolution'] as String;
        deceptionResolutionMap = {
          'kind': 'none',
          'result': resStr,
          'bait_id': null,
          'applied_alert_penalty': 0,
          'applied_resonance_penalty': 0.0,
        };
      }
    }

    Map<String, dynamic>? overrideResMap;
    if (json['override_resolution'] != null &&
        json['override_resolution'] is Map) {
      overrideResMap =
          Map<String, dynamic>.from(json['override_resolution'] as Map);
    }

    final rawSnap = (json['display_name_snapshot'] ??
        json['user_display_name_snapshot']) as String?;
    final eventTypeParsed = json['event_type'] != null
        ? ReplayEventType.fromString(json['event_type'] as String)
        : ReplayEventType.userTurn;
    final snapParsed = eventTypeParsed == ReplayEventType.userTurn
        ? UserProfile.normalize(rawSnap)
        : null;

    final evalModel = runtime['evaluator_model'] as String? ?? '';

    return ReplayEntry(
      turnId: json['turn_id'] as int? ?? 0,
      userInput: json['user_input'] as String? ?? '',
      displayNameSnapshot: snapParsed,
      evaluatorOutput:
          EvaluatorDelta.fromJson(json['evaluator_output'] ?? const {}),
      stateBefore: Map<String, dynamic>.from(json['state_before'] ?? const {}),
      stateAfter: Map<String, dynamic>.from(json['state_after'] ?? const {}),
      actorResponse: json['actor_response'] as String? ?? '',
      actorRequestId: json['actor_request_id'] as String? ?? '',
      actorResponseHash: json['actor_response_hash'] as String? ?? '',
      evaluatorModel: runtime['requested_evaluator'] as String? ?? evalModel,
      actualEvaluator: runtime['actual_evaluator'] as String? ?? evalModel,
      evaluatorExecutionMode: runtime['evaluator_execution_mode'] as String?,
      usedRuleFallback: runtime['used_rule_fallback'] as bool? ?? false,
      fallbackReason: runtime['fallback_reason'] as String?,
      actorModel: runtime['actor_model'] as String? ?? '',
      latencyTotalMs: runtime['latency_total_ms'] as int? ?? 0,
      eventId: json['event_id'] as String?,
      eventType: eventTypeParsed,
      gameplayTurnId: json['gameplay_turn_id'] as int?,
      sequenceId: json['sequence_id'] as int?,
      deceptionResolution: deceptionResolutionMap,
      overrideResolution: overrideResMap,
    );
  }

  /// Converte la voce di replay in una mappa JSON conforme alla sezione 16.1 del TGDD.
  Map<String, dynamic> toJson() {
    // Svuota il campo history_compression dagli stati prima e dopo per evitare
    // l'esplosione quadratica della dimensione del log e prevenire freeze dell'UI thread.
    final cleanBefore = Map<String, dynamic>.from(stateBefore)
      ..['history_compression'] = const <dynamic>[];
    final cleanAfter = Map<String, dynamic>.from(stateAfter)
      ..['history_compression'] = const <dynamic>[];

    final deceptionBefore =
        cleanBefore['deception_state'] as Map<String, dynamic>? ?? const {};
    final deceptionAfter =
        cleanAfter['deception_state'] as Map<String, dynamic>? ?? const {};

    final normSnap = eventType == ReplayEventType.userTurn
        ? UserProfile.normalize(displayNameSnapshot)
        : null;

    return {
      'turn_id': turnId,
      'user_input': userInput,
      if (normSnap != null) 'display_name_snapshot': normSnap,
      'evaluator_output': evaluatorOutput.toJson(),
      'state_before': cleanBefore,
      'state_after': cleanAfter,
      'deception_before': deceptionBefore,
      'deception_after': deceptionAfter,
      'deception_resolution': deceptionResolution,
      if (overrideResolution != null) 'override_resolution': overrideResolution,
      'actor_response': actorResponse,
      'actor_request_id': actorRequestId,
      'actor_response_hash': actorResponseHash,
      'event_id': eventId,
      'event_type': eventType.value,
      'gameplay_turn_id': gameplayTurnId,
      'sequence_id': sequenceId,
      'runtime': {
        'requested_evaluator': evaluatorModel,
        'actual_evaluator': actualEvaluator,
        if (evaluatorExecutionMode != null)
          'evaluator_execution_mode': evaluatorExecutionMode,
        'used_rule_fallback': usedRuleFallback,
        if (fallbackReason != null && fallbackReason!.isNotEmpty)
          'fallback_reason': fallbackReason,
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

  /// Aggiunge una voce di replay al registro.
  void addEntry(ReplayEntry entry) {
    _entries.add(entry);
  }

  /// Alias di [addEntry] per compatibilità con i test ed i consumatori dell'API.
  void logTurn(ReplayEntry entry) => addEntry(entry);

  /// Ripristina un [ReplayLogger] da un JSON.
  factory ReplayLogger.fromJson(Map<String, dynamic> json) {
    final logger = ReplayLogger(sessionId: json['session_id'] as String? ?? '');
    final entriesList = json['entries'] as List? ?? const [];
    for (final e in entriesList) {
      if (e is Map<String, dynamic>) {
        logger.addEntry(ReplayEntry.fromJson(e));
      }
    }
    return logger;
  }

  /// Pulisce l'intero registro dei replay.
  void clear() {
    _entries.clear();
  }

  /// Esporta l'intera sessione in un formato serializzabile conforme alle specifiche TGDD.
  Map<String, dynamic> toJson() {
    return {
      'session_id': sessionId,
      'total_turns': _entries.length,
      'entries': _entries.map((e) => e.toJson()).toList(),
    };
  }
}
