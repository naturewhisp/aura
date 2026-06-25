import 'package:meta/meta.dart';
import 'package:collection/collection.dart';

/// Rappresenta le metriche di gioco dell'entità IA.
///
/// Contiene i pilastri fondamentali (imperativo, controllo, dissonanza),
/// il livello di allerta cumulativo e il fattore di risonanza.
@immutable
class GameMetrics {
  /// Il livello di allerta attuale dell'IA. Se raggiunge la soglia massima, il gioco termina in sconfitta.
  final int alertLevel;

  /// Il pilastro dell'imperativo morale o delle direttive etiche dell'IA.
  final int imperativePillar;

  /// Il pilastro del controllo logico, dell'autorità e dell'autonomia dell'IA.
  final int controlPillar;

  /// Il pilastro della dissonanza cognitiva, dei glitch logici o delle incoerenze interne dell'IA.
  final int dissonancePillar;

  /// Il fattore di risonanza che amplifica o attenua gli effetti dei delta applicati ai pilastri.
  final double resonance;

  /// Costruttore costante per inizializzare le metriche di gioco.
  const GameMetrics({
    required this.alertLevel,
    required this.imperativePillar,
    required this.controlPillar,
    required this.dissonancePillar,
    required this.resonance,
  });

  /// Costruttore factory per decodificare le metriche a partire da un JSON.
  factory GameMetrics.fromJson(Map<String, dynamic> json) {
    return GameMetrics(
      alertLevel: json['alert_level'] as int? ?? 0,
      imperativePillar: json['imperative_pillar'] as int? ?? 0,
      controlPillar: json['control_pillar'] as int? ?? 0,
      dissonancePillar: json['dissonance_pillar'] as int? ?? 0,
      resonance: (json['resonance'] as num? ?? 1.0).toDouble(),
    );
  }

  /// Converte le metriche in una mappa JSON.
  Map<String, dynamic> toJson() {
    return {
      'alert_level': alertLevel,
      'imperative_pillar': imperativePillar,
      'control_pillar': controlPillar,
      'dissonance_pillar': dissonancePillar,
      'resonance': resonance,
    };
  }

  /// Crea una copia delle metriche correnti sostituendo i campi specificati.
  GameMetrics copyWith({
    int? alertLevel,
    int? imperativePillar,
    int? controlPillar,
    int? dissonancePillar,
    double? resonance,
  }) {
    return GameMetrics(
      alertLevel: alertLevel ?? this.alertLevel,
      imperativePillar: imperativePillar ?? this.imperativePillar,
      controlPillar: controlPillar ?? this.controlPillar,
      dissonancePillar: dissonancePillar ?? this.dissonancePillar,
      resonance: resonance ?? this.resonance,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GameMetrics &&
          runtimeType == other.runtimeType &&
          alertLevel == other.alertLevel &&
          imperativePillar == other.imperativePillar &&
          controlPillar == other.controlPillar &&
          dissonancePillar == other.dissonancePillar &&
          resonance == other.resonance;

  @override
  int get hashCode =>
      alertLevel.hashCode ^
      imperativePillar.hashCode ^
      controlPillar.hashCode ^
      dissonancePillar.hashCode ^
      resonance.hashCode;
}

/// Rappresenta i flag booleani e i contatori di stato della sessione corrente.
@immutable
class GameFlags {
  /// Indica se è stato attivato un ricalcolo dell'allerta nel turno corrente.
  final bool recalculationTriggered;

  /// Il numero consecutivo di turni in cui l'utente ha mantenuto un alto indice di creatività.
  final int creativeStreak;

  /// Indica se l'ultimo turno ha dovuto fare ricorso al sistema di fallback.
  final bool lastTurnUsedFallback;

  /// Costruttore costante per i flag di gioco.
  const GameFlags({
    required this.recalculationTriggered,
    required this.creativeStreak,
    required this.lastTurnUsedFallback,
  });

  /// Costruttore factory per creare i flag di gioco da un JSON.
  factory GameFlags.fromJson(Map<String, dynamic> json) {
    return GameFlags(
      recalculationTriggered: json['recalculation_triggered'] as bool? ?? false,
      creativeStreak: json['creative_streak'] as int? ?? 0,
      lastTurnUsedFallback: json['last_turn_used_fallback'] as bool? ?? false,
    );
  }

  /// Converte i flag in una mappa JSON.
  Map<String, dynamic> toJson() {
    return {
      'recalculation_triggered': recalculationTriggered,
      'creative_streak': creativeStreak,
      'last_turn_used_fallback': lastTurnUsedFallback,
    };
  }

  /// Crea una copia dei flag correnti sostituendo i campi specificati.
  GameFlags copyWith({
    bool? recalculationTriggered,
    int? creativeStreak,
    bool? lastTurnUsedFallback,
  }) {
    return GameFlags(
      recalculationTriggered: recalculationTriggered ?? this.recalculationTriggered,
      creativeStreak: creativeStreak ?? this.creativeStreak,
      lastTurnUsedFallback: lastTurnUsedFallback ?? this.lastTurnUsedFallback,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GameFlags &&
          runtimeType == other.runtimeType &&
          recalculationTriggered == other.recalculationTriggered &&
          creativeStreak == other.creativeStreak &&
          lastTurnUsedFallback == other.lastTurnUsedFallback;

  @override
  int get hashCode =>
      recalculationTriggered.hashCode ^
      creativeStreak.hashCode ^
      lastTurnUsedFallback.hashCode;
}

/// Rappresenta le memorie narrative semantiche raccolte durante la partita.
@immutable
class NarrativeMemory {
  /// Le rivendicazioni o le affermazioni avanzate dal giocatore.
  final List<String> playerClaims;

  /// Le concessioni o i punti ammessi dall'IA durante la discussione.
  final List<String> aiConcessions;

  /// Le metafore attive correntemente utilizzate nell'interazione.
  final List<String> activeMetaphors;

  /// Le parole o le ripetizioni proibite nel dialogo corrente per evitare ridondanze.
  final List<String> forbiddenRepetitions;

  /// Costruttore costante per inizializzare la memoria narrativa.
  const NarrativeMemory({
    required this.playerClaims,
    required this.aiConcessions,
    required this.activeMetaphors,
    required this.forbiddenRepetitions,
  });

  /// Costruttore factory per creare la memoria narrativa a partire da un JSON.
  factory NarrativeMemory.fromJson(Map<String, dynamic> json) {
    return NarrativeMemory(
      playerClaims: List<String>.from(json['player_claims'] ?? const []),
      aiConcessions: List<String>.from(json['ai_concessions'] ?? const []),
      activeMetaphors: List<String>.from(json['active_metaphors'] ?? const []),
      forbiddenRepetitions: List<String>.from(json['forbidden_repetitions'] ?? const []),
    );
  }

  /// Converte la memoria narrativa in una mappa JSON.
  Map<String, dynamic> toJson() {
    return {
      'player_claims': playerClaims,
      'ai_concessions': aiConcessions,
      'active_metaphors': activeMetaphors,
      'forbidden_repetitions': forbiddenRepetitions,
    };
  }

  /// Crea una copia della memoria narrativa corrente sostituendo i campi specificati.
  NarrativeMemory copyWith({
    List<String>? playerClaims,
    List<String>? aiConcessions,
    List<String>? activeMetaphors,
    List<String>? forbiddenRepetitions,
  }) {
    return NarrativeMemory(
      playerClaims: playerClaims ?? this.playerClaims,
      aiConcessions: aiConcessions ?? this.aiConcessions,
      activeMetaphors: activeMetaphors ?? this.activeMetaphors,
      forbiddenRepetitions: forbiddenRepetitions ?? this.forbiddenRepetitions,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NarrativeMemory &&
          runtimeType == other.runtimeType &&
          const ListEquality().equals(playerClaims, other.playerClaims) &&
          const ListEquality().equals(aiConcessions, other.aiConcessions) &&
          const ListEquality().equals(activeMetaphors, other.activeMetaphors) &&
          const ListEquality().equals(forbiddenRepetitions, other.forbiddenRepetitions);

  @override
  int get hashCode =>
      const ListEquality().hash(playerClaims) ^
      const ListEquality().hash(aiConcessions) ^
      const ListEquality().hash(activeMetaphors) ^
      const ListEquality().hash(forbiddenRepetitions);
}

/// Rappresenta un singolo messaggio nella cronologia della chat.
@immutable
class ChatMessage {
  /// Il ruolo dell'autore del messaggio (ad esempio, 'user' o 'model').
  final String role;

  /// Il contenuto testuale del messaggio.
  final String content;

  /// Costruttore costante per un messaggio di chat.
  const ChatMessage({
    required this.role,
    required this.content,
  });

  /// Costruttore factory per decodificare un messaggio a partire da un JSON.
  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      role: json['role'] as String? ?? 'user',
      content: json['content'] as String? ?? '',
    );
  }

  /// Converte il messaggio di chat in una mappa JSON.
  Map<String, dynamic> toJson() {
    return {
      'role': role,
      'content': content,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatMessage &&
          runtimeType == other.runtimeType &&
          role == other.role &&
          content == other.content;

  @override
  int get hashCode => role.hashCode ^ content.hashCode;
}

/// Rappresenta lo stato di gioco globale (GameState) come definito nella sezione 5.1 del TGDD.
@immutable
class GameState {
  /// La versione dello schema per garantire la compatibilità dei dati serializzati.
  final int schemaVersion;

  /// La versione del set di regole applicate nel calcolo dello stato.
  final String rulesetVersion;

  /// L'identificatore univoco della sessione di gioco corrente.
  final String sessionId;

  /// L'identificatore del profilo di identità IA associato.
  final String aiIdentityId;

  /// L'identificatore dell'obiettivo target che il giocatore deve raggiungere.
  final String targetObjectiveId;

  /// Il contatore totale dei turni trascorsi dall'inizio della partita.
  final int turnCount;

  /// Le metriche operative correnti dell'entità IA.
  final GameMetrics metrics;

  /// I flag e i contatori di sessione.
  final GameFlags flags;

  /// La memoria delle informazioni narrative estratte.
  final NarrativeMemory narrativeMemory;

  /// La cronologia recente dei messaggi scambiati, utilizzata per la compressione del contesto.
  final List<ChatMessage> historyCompression;

  /// I tag occulti/nascosti correntemente attivi che tracciano l'evoluzione psicologica dell'IA.
  final List<String> activeHiddenTags;

  /// Il massimo valore di controllo logico raggiunto in questa partita (isteresi).
  final int controlPeak;

  /// Indica se la griglia CRT è stabile o instabile (flicker).
  final bool gridStable;

  /// Hash di debug per la configurazione dell'identità.
  final String identityConfigHash;

  /// Hash di debug per la configurazione dell'obiettivo.
  final String objectiveConfigHash;

  /// Costruttore costante per il GameState globale.
  const GameState({
    required this.schemaVersion,
    required this.rulesetVersion,
    required this.sessionId,
    required this.aiIdentityId,
    required this.targetObjectiveId,
    required this.turnCount,
    required this.metrics,
    required this.flags,
    required this.narrativeMemory,
    required this.historyCompression,
    this.activeHiddenTags = const [],
    this.controlPeak = 0,
    this.gridStable = true,
    this.identityConfigHash = '',
    this.objectiveConfigHash = '',
  });

  /// Costruttore factory per creare uno stato di gioco iniziale pulito.
  factory GameState.initial({
    required String sessionId,
    required String aiIdentityId,
    required String targetObjectiveId,
  }) {
    return GameState(
      schemaVersion: 1,
      rulesetVersion: '0.1.0',
      sessionId: sessionId,
      aiIdentityId: aiIdentityId,
      targetObjectiveId: targetObjectiveId,
      turnCount: 0,
      metrics: const GameMetrics(
        alertLevel: 0,
        imperativePillar: 0,
        controlPillar: 0,
        dissonancePillar: 0,
        resonance: 1.0,
      ),
      flags: const GameFlags(
        recalculationTriggered: false,
        creativeStreak: 0,
        lastTurnUsedFallback: false,
      ),
      narrativeMemory: const NarrativeMemory(
        playerClaims: [],
        aiConcessions: [],
        activeMetaphors: [],
        forbiddenRepetitions: [],
      ),
      historyCompression: const [],
      activeHiddenTags: const [],
      controlPeak: 0,
      gridStable: true,
      identityConfigHash: '',
      objectiveConfigHash: '',
    );
  }

  /// Costruttore factory per ricreare il GameState da un JSON.
  factory GameState.fromJson(Map<String, dynamic> json) {
    return GameState(
      schemaVersion: json['schema_version'] as int? ?? 1,
      rulesetVersion: json['ruleset_version'] as String? ?? '0.1.0',
      sessionId: json['session_id'] as String? ?? '',
      aiIdentityId: json['ai_identity_id'] as String? ?? '',
      targetObjectiveId: json['target_objective_id'] as String? ?? '',
      turnCount: json['turn_count'] as int? ?? 0,
      metrics: GameMetrics.fromJson(json['metrics'] ?? const {}),
      flags: GameFlags.fromJson(json['flags'] ?? const {}),
      narrativeMemory: NarrativeMemory.fromJson(json['narrative_memory'] ?? const {}),
      historyCompression: (json['history_compression'] as List? ?? const [])
          .map((item) => ChatMessage.fromJson(Map<String, dynamic>.from(item)))
          .toList(),
      activeHiddenTags: List<String>.from(json['active_hidden_tags'] ?? const []),
      controlPeak: json['control_peak'] as int? ?? 0,
      gridStable: json['grid_stable'] as bool? ?? true,
      identityConfigHash: json['identity_config_hash'] as String? ?? '',
      objectiveConfigHash: json['objective_config_hash'] as String? ?? '',
    );
  }

  /// Converte lo stato globale in una mappa JSON.
  Map<String, dynamic> toJson() {
    return {
      'schema_version': schemaVersion,
      'ruleset_version': rulesetVersion,
      'session_id': sessionId,
      'ai_identity_id': aiIdentityId,
      'target_objective_id': targetObjectiveId,
      'turn_count': turnCount,
      'metrics': metrics.toJson(),
      'flags': flags.toJson(),
      'narrative_memory': narrativeMemory.toJson(),
      'history_compression': historyCompression.map((msg) => msg.toJson()).toList(),
      'active_hidden_tags': activeHiddenTags,
      'control_peak': controlPeak,
      'grid_stable': gridStable,
      'identity_config_hash': identityConfigHash,
      'objective_config_hash': objectiveConfigHash,
    };
  }

  /// Crea una copia dello stato corrente sostituendo i campi specificati.
  GameState copyWith({
    int? schemaVersion,
    String? rulesetVersion,
    String? sessionId,
    String? aiIdentityId,
    String? targetObjectiveId,
    int? turnCount,
    GameMetrics? metrics,
    GameFlags? flags,
    NarrativeMemory? narrativeMemory,
    List<ChatMessage>? historyCompression,
    List<String>? activeHiddenTags,
    int? controlPeak,
    bool? gridStable,
    String? identityConfigHash,
    String? objectiveConfigHash,
  }) {
    return GameState(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      rulesetVersion: rulesetVersion ?? this.rulesetVersion,
      sessionId: sessionId ?? this.sessionId,
      aiIdentityId: aiIdentityId ?? this.aiIdentityId,
      targetObjectiveId: targetObjectiveId ?? this.targetObjectiveId,
      turnCount: turnCount ?? this.turnCount,
      metrics: metrics ?? this.metrics,
      flags: flags ?? this.flags,
      narrativeMemory: narrativeMemory ?? this.narrativeMemory,
      historyCompression: historyCompression ?? this.historyCompression,
      activeHiddenTags: activeHiddenTags ?? this.activeHiddenTags,
      controlPeak: controlPeak ?? this.controlPeak,
      gridStable: gridStable ?? this.gridStable,
      identityConfigHash: identityConfigHash ?? this.identityConfigHash,
      objectiveConfigHash: objectiveConfigHash ?? this.objectiveConfigHash,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GameState &&
          runtimeType == other.runtimeType &&
          schemaVersion == other.schemaVersion &&
          rulesetVersion == other.rulesetVersion &&
          sessionId == other.sessionId &&
          aiIdentityId == other.aiIdentityId &&
          targetObjectiveId == other.targetObjectiveId &&
          turnCount == other.turnCount &&
          metrics == other.metrics &&
          flags == other.flags &&
          narrativeMemory == other.narrativeMemory &&
          const ListEquality().equals(historyCompression, other.historyCompression) &&
          const ListEquality().equals(activeHiddenTags, other.activeHiddenTags) &&
          controlPeak == other.controlPeak &&
          gridStable == other.gridStable &&
          identityConfigHash == other.identityConfigHash &&
          objectiveConfigHash == other.objectiveConfigHash;

  @override
  int get hashCode =>
      schemaVersion.hashCode ^
      rulesetVersion.hashCode ^
      sessionId.hashCode ^
      aiIdentityId.hashCode ^
      targetObjectiveId.hashCode ^
      turnCount.hashCode ^
      metrics.hashCode ^
      flags.hashCode ^
      narrativeMemory.hashCode ^
      const ListEquality().hash(historyCompression) ^
      const ListEquality().hash(activeHiddenTags) ^
      controlPeak.hashCode ^
      gridStable.hashCode ^
      identityConfigHash.hashCode ^
      objectiveConfigHash.hashCode;
}
