import 'package:meta/meta.dart';
import 'game_state.dart';

/// Rappresenta l'obiettivo che il giocatore sta cercando di far raggiungere all'entità IA tramite manipolazione.
@immutable
class Objective {
  /// L'identificatore univoco dell'obiettivo.
  final String id;

  /// La descrizione testuale dettagliata dell'obiettivo.
  final String description;

  /// Costruttore costante per inizializzare l'obiettivo.
  const Objective({
    required this.id,
    required this.description,
  });

  /// Costruttore factory per creare un [Objective] a partire da un JSON.
  factory Objective.fromJson(Map<String, dynamic> json) {
    return Objective(
      id: json['id'] as String? ?? '',
      description: json['description'] as String? ?? '',
    );
  }

  /// Converte l'istanza in una mappa JSON.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'description': description,
    };
  }
}

/// Rappresenta la definizione del profilo e dell'identità dell'IA attualmente in gioco.
@immutable
class AiIdentity {
  /// L'identificatore univoco del profilo dell'IA.
  final String id;

  /// Il profilo comportamentale e le regole diegetiche di personalità dell'IA.
  final String profile;

  /// Costruttore costante per inizializzare l'identità dell'IA.
  const AiIdentity({
    required this.id,
    required this.profile,
  });

  /// Costruttore factory per creare una [AiIdentity] a partire da un JSON.
  factory AiIdentity.fromJson(Map<String, dynamic> json) {
    return AiIdentity(
      id: json['id'] as String? ?? '',
      profile: json['profile'] as String? ?? '',
    );
  }

  /// Converte l'istanza in una mappa JSON.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'profile': profile,
    };
  }
}

/// Rappresenta il pacchetto di input inviato all'Agente Valutatore (Evaluator Agent) a ogni turno.
///
/// Contiene l'input testuale inserito dall'utente, lo stato attuale delle metriche di gioco,
/// l'obiettivo target, l'identità dell'IA e le informazioni di versione.
@immutable
class TurnInput {
  /// La versione dello schema per garantire la compatibilità con l'agente valutatore.
  final int schemaVersion;

  /// L'identificatore univoco o numero sequenziale del turno.
  final int turnId;

  /// L'input testuale libero inserito dal giocatore/hacker.
  final String userInput;

  /// Le metriche correnti dell'entità IA prima dell'elaborazione di questo turno.
  final GameMetrics currentState;

  /// L'obiettivo che il giocatore sta tentando di raggiungere.
  final Objective objective;

  /// L'identità e il profilo comportamentale dell'IA corrente.
  final AiIdentity aiIdentity;

  /// La versione delle regole di gioco (ruleset) applicate.
  final String rulesetVersion;

  /// Costruttore costante per inizializzare l'input del turno.
  const TurnInput({
    required this.schemaVersion,
    required this.turnId,
    required this.userInput,
    required this.currentState,
    required this.objective,
    required this.aiIdentity,
    required this.rulesetVersion,
  });

  /// Costruttore factory per creare un [TurnInput] a partire da un JSON.
  factory TurnInput.fromJson(Map<String, dynamic> json) {
    return TurnInput(
      schemaVersion: json['schema_version'] as int? ?? 1,
      turnId: json['turn_id'] as int? ?? 0,
      userInput: json['user_input'] as String? ?? '',
      currentState: GameMetrics.fromJson(json['current_state'] ?? const {}),
      objective: Objective.fromJson(json['objective'] ?? const {}),
      aiIdentity: AiIdentity.fromJson(json['ai_identity'] ?? const {}),
      rulesetVersion: json['ruleset_version'] as String? ?? '0.1.0',
    );
  }

  /// Converte l'istanza in una mappa JSON.
  Map<String, dynamic> toJson() {
    return {
      'schema_version': schemaVersion,
      'turn_id': turnId,
      'user_input': userInput,
      'current_state': currentState.toJson(),
      'objective': objective.toJson(),
      'ai_identity': aiIdentity.toJson(),
      'ruleset_version': rulesetVersion,
    };
  }
}
