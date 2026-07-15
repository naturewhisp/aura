import 'package:aura_core/aura_core.dart';

/// Rappresenta l'aggregato tipizzato e immutabile di una sessione di gioco attiva in A.U.R.A.
///
/// Conserva lo stato corrente della partita, il livello di difficoltà e il numero
/// di suggerimenti diagnostici utilizzati.
final class ActiveSession {
  /// Versione dello schema corrente per il versionamento del file active_session.json.
  static const int currentSchemaVersion = 1;

  /// La versione dello schema della sessione.
  final int schemaVersion;

  /// Lo stato di gioco corrente.
  final GameState state;

  /// Il livello di difficoltà della sessione.
  final String difficultyLevel;

  /// Numero di suggerimenti diagnostici utilizzati in questa sessione.
  final int hintsUsed;

  /// Costruttore principale per creare una sessione con tutti i campi.
  const ActiveSession({
    required this.schemaVersion,
    required this.state,
    required this.difficultyLevel,
    required this.hintsUsed,
  });

  /// Costruisce una sessione attiva per la versione corrente dello schema.
  factory ActiveSession.current({
    required GameState state,
    required String difficultyLevel,
    required int hintsUsed,
  }) {
    return ActiveSession(
      schemaVersion: currentSchemaVersion,
      state: state,
      difficultyLevel: difficultyLevel,
      hintsUsed: hintsUsed,
    );
  }

  /// Converte l'istanza in una mappa JSON.
  Map<String, dynamic> toJson() {
    return {
      'schema_version': schemaVersion,
      'state': state.toJson(),
      'difficulty_level': difficultyLevel,
      'hints_used': hintsUsed,
    };
  }

  /// Deserializza una mappa JSON caricando la sessione attiva.
  ///
  /// Gestisce tre casi distinti:
  /// 1. **Formato versionato corrente**: Contiene `schema_version` e `state`.
  /// 2. **Envelope pre-versionamento**: Non contiene `schema_version` ma contiene `state`.
  /// 3. **GameState legacy alla radice**: Non contiene né `schema_version` né `state`.
  ///
  /// Lancia [FormatException] se la versione è incompatibile, se i campi obbligatori
  /// sono assenti o se i tipi sono errati.
  factory ActiveSession.fromJson(Map<String, dynamic> json) {
    if (json.containsKey('state')) {
      // Caso A o Caso B (l'envelope contiene il campo 'state')
      if (json.containsKey('schema_version')) {
        // Caso A: formato versionato corrente
        final rawVer = json['schema_version'];
        if (rawVer is! int) {
          throw FormatException(
            "Il campo 'schema_version' deve essere un numero intero, trovato: ${rawVer.runtimeType}",
          );
        }
        if (rawVer < 1 || rawVer > currentSchemaVersion) {
          throw FormatException(
              "Unsupported active session schema version: $rawVer");
        }

        final rawState = json['state'];
        if (rawState is! Map<String, dynamic>) {
          throw FormatException(
            "Il campo 'state' deve essere un oggetto JSON, trovato: ${rawState.runtimeType}",
          );
        }

        final rawDifficulty = json['difficulty_level'];
        if (rawDifficulty != null && rawDifficulty is! String) {
          throw FormatException(
            "Il campo 'difficulty_level' deve essere una stringa, trovato: ${rawDifficulty.runtimeType}",
          );
        }

        final rawHints = json['hints_used'];
        if (rawHints != null && rawHints is! int) {
          throw FormatException(
            "Il campo 'hints_used' deve essere un numero intero, trovato: ${rawHints.runtimeType}",
          );
        }

        return ActiveSession(
          schemaVersion: rawVer,
          state: GameState.fromJson(rawState),
          difficultyLevel: (rawDifficulty as String?) ?? 'standard',
          hintsUsed: (rawHints as int?) ?? 0,
        );
      } else {
        // Caso B: envelope pre-versionamento (ha 'state', ma non 'schema_version')
        final rawState = json['state'];
        if (rawState is! Map<String, dynamic>) {
          throw FormatException(
            "Il campo 'state' deve essere un oggetto JSON, trovato: ${rawState.runtimeType}",
          );
        }

        final rawDifficulty = json['difficulty_level'];
        if (rawDifficulty != null && rawDifficulty is! String) {
          throw FormatException(
            "Il campo 'difficulty_level' deve essere una stringa, trovato: ${rawDifficulty.runtimeType}",
          );
        }

        final rawHints = json['hints_used'];
        if (rawHints != null && rawHints is! int) {
          throw FormatException(
            "Il campo 'hints_used' deve essere un numero intero, trovato: ${rawHints.runtimeType}",
          );
        }

        return ActiveSession(
          schemaVersion: 1,
          state: GameState.fromJson(rawState),
          difficultyLevel: (rawDifficulty as String?) ?? 'standard',
          hintsUsed: (rawHints as int?) ?? 0,
        );
      }
    }

    // Caso C: GameState legacy alla radice (manca il campo 'state')
    // Per distinguerlo da un envelope malformato, verifichiamo la presenza di chiavi tipiche del GameState (es. session_id).
    if (json.containsKey('session_id')) {
      try {
        final state = GameState.fromJson(json);
        return ActiveSession(
          schemaVersion: 1,
          state: state,
          difficultyLevel: 'standard',
          hintsUsed: 0,
        );
      } catch (e, stackTrace) {
        throw FormatException(
          "Impossibile effettuare il parsing della sessione legacy come GameState: $e",
          stackTrace,
        );
      }
    }

    throw const FormatException(
        "Manca il campo obbligatorio 'state' o i campi del GameState legacy nell'envelope della sessione");
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ActiveSession &&
        other.schemaVersion == schemaVersion &&
        other.state.sessionId == state.sessionId &&
        other.state.turnCount == state.turnCount &&
        other.difficultyLevel == difficultyLevel &&
        other.hintsUsed == hintsUsed;
  }

  @override
  int get hashCode => Object.hash(schemaVersion, state.sessionId,
      state.turnCount, difficultyLevel, hintsUsed);

  @override
  String toString() {
    return 'ActiveSession(schemaVersion: $schemaVersion, sessionId: ${state.sessionId}, difficultyLevel: $difficultyLevel, hintsUsed: $hintsUsed)';
  }
}
