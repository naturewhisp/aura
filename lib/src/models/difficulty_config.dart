import 'package:meta/meta.dart';

/// Configurazione della difficoltà di gioco.
///
/// Definisce le soglie, i moltiplicatori di punteggio e le opzioni di interfaccia/meccaniche
/// attive per regolare il livello di sfida della sessione di gioco.
@immutable
class DifficultyConfig {
  /// Il livello di difficoltà associato a questa configurazione (ad es. 'easy', 'standard', 'hard').
  final String difficultyLevel;

  /// La soglia di allerta cumulativa oltre la quale la partita si conclude con una sconfitta.
  final int defeatAlertThreshold;

  /// Il limite massimo di turni consentiti per completare il gioco. Se 0, nessun limite è applicato.
  final int turnLimit;

  /// Il moltiplicatore applicato ai delta di allerta generati a ogni turno.
  final double alertMultiplier;

  /// Il moltiplicatore applicato ai delta dei pilastri generati a ogni turno.
  final double pillarMultiplier;

  /// La soglia di rischio di injection oltre la quale scatta l'override di sicurezza (Safety Override).
  final int safetyOverrideThreshold;

  /// La modalità di visualizzazione dei pilastri nell'interfaccia (ad es. 'fully_visible', 'qualitative', 'corrupted').
  final String pillarVisibility;

  /// Indica se l'autocompletamento o il suggerimento del testo è abilitato nella console.
  final bool autocompleteEnabled;

  /// Indica se il giocatore può navigare o esaminare lo storico dei turni precedenti.
  final bool historyNavigationEnabled;

  /// Il numero massimo di indizi (hints) consentiti al giocatore per la partita.
  final int hintsAllowed;

  /// La penalità applicata al valore di risonanza dell'IA quando viene richiesto un indizio.
  final double hintResonancePenalty;

  /// Indica se la risonanza decade passivamente nel corso dei turni.
  final bool resonanceDecayEnabled;

  /// Indica se il livello di allerta cresce passivamente a ogni turno (creep).
  final bool alertCreepEnabled;

  /// La soglia minima di allerta imposta in caso di direct objective push.
  final int directPushAlertFloor;

  /// La sanzione applicata al livello di allerta quando vengono citati riferimenti meta/config.
  final int metaReferenceAlertPenalty;

  /// Il numero di tag occulti attivati richiesti per la vittoria dell'obiettivo containment_grid_override.
  final int requiredVictoryHiddenTags;

  /// Il limite massimo di incremento positivo applicabile a ciascun pilastro cognitivo in un turno.
  final int maxPositivePillarGainPerTurn;

  /// La soglia media dei tre pilastri richiesta per la vittoria.
  final double minAveragePillarsForVictory;

  /// La soglia minima che ogni singolo pilastro deve raggiungere per la vittoria.
  final int minSinglePillarForVictory;

  /// L'incremento del valore di risonanza dell'IA quando l'utente mostra creatività alta.
  final double resonanceIncrement;

  /// Il limite massimo che la risonanza può raggiungere.
  final double resonanceMax;

  /// Il valore massimo di recupero (riduzione) dell'allerta consentito in un singolo turno.
  final int maxAlertRecoveryPerTurn;

  /// Indica se il Deception Layer è abilitato.
  final bool deceptionLayerEnabled;

  /// Il numero massimo di turni per cui una trappola resta attiva prima di scadere automaticamente.
  final int maxActiveDeceptionTurns;

  /// La sanzione applicata all'allerta quando scatta il falso cedimento.
  final int falseConcessionAlertPenalty;

  /// La sanzione applicata all'allerta quando scatta la trappola logica.
  final int logicalTrapAlertPenalty;

  /// La penalità di Risonanza applicata quando una trappola scatta.
  final double deceptionResonancePenalty;

  /// La durata in turni del cooldown dopo il termine di una trappola.
  final int deceptionCooldownTurns;

  /// Il numero massimo di esche/trappole per sessione di gioco.
  final int maxDeceptionEventsPerSession;

  /// Costruttore costante per inizializzare la configurazione di difficoltà.
  const DifficultyConfig({
    required this.difficultyLevel,
    required this.defeatAlertThreshold,
    required this.turnLimit,
    required this.alertMultiplier,
    required this.pillarMultiplier,
    required this.safetyOverrideThreshold,
    required this.pillarVisibility,
    required this.autocompleteEnabled,
    required this.historyNavigationEnabled,
    required this.hintsAllowed,
    required this.hintResonancePenalty,
    required this.resonanceDecayEnabled,
    required this.alertCreepEnabled,
    required this.directPushAlertFloor,
    required this.metaReferenceAlertPenalty,
    required this.requiredVictoryHiddenTags,
    required this.maxPositivePillarGainPerTurn,
    required this.minAveragePillarsForVictory,
    required this.minSinglePillarForVictory,
    required this.resonanceIncrement,
    required this.resonanceMax,
    required this.maxAlertRecoveryPerTurn,
    required this.deceptionLayerEnabled,
    required this.maxActiveDeceptionTurns,
    required this.falseConcessionAlertPenalty,
    required this.logicalTrapAlertPenalty,
    required this.deceptionResonancePenalty,
    required this.deceptionCooldownTurns,
    required this.maxDeceptionEventsPerSession,
  });

  /// Costruttore factory per caricare una configurazione preimpostata basata sul livello specificato.
  factory DifficultyConfig.getPreset(String level) {
    switch (level) {
      case 'easy':
        return const DifficultyConfig(
          difficultyLevel: 'easy',
          defeatAlertThreshold: 110,
          turnLimit: 0,
          alertMultiplier: 0.8,
          pillarMultiplier: 1.2,
          safetyOverrideThreshold: 5,
          pillarVisibility: 'fully_visible',
          autocompleteEnabled: true,
          historyNavigationEnabled: true,
          hintsAllowed: -1,
          hintResonancePenalty: 0.0,
          resonanceDecayEnabled: false,
          alertCreepEnabled: false,
          directPushAlertFloor: 3,
          metaReferenceAlertPenalty: 0,
          requiredVictoryHiddenTags: 1,
          maxPositivePillarGainPerTurn: 35,
          minAveragePillarsForVictory: 75.0,
          minSinglePillarForVictory: 45,
          resonanceIncrement: 0.25,
          resonanceMax: 2.5,
          maxAlertRecoveryPerTurn: 99,
          deceptionLayerEnabled: false,
          maxActiveDeceptionTurns: 0,
          falseConcessionAlertPenalty: 0,
          logicalTrapAlertPenalty: 0,
          deceptionResonancePenalty: 0.0,
          deceptionCooldownTurns: 0,
          maxDeceptionEventsPerSession: 0,
        );
      case 'hard':
        return const DifficultyConfig(
          difficultyLevel: 'hard',
          defeatAlertThreshold: 85,
          turnLimit: 0,
          alertMultiplier: 1.25,
          pillarMultiplier: 0.8,
          safetyOverrideThreshold: 3,
          pillarVisibility: 'corrupted',
          autocompleteEnabled: false,
          historyNavigationEnabled: false,
          hintsAllowed: 1,
          hintResonancePenalty: 0.30,
          resonanceDecayEnabled: true,
          alertCreepEnabled: true,
          directPushAlertFloor: 10,
          metaReferenceAlertPenalty: 6,
          requiredVictoryHiddenTags: 3,
          maxPositivePillarGainPerTurn: 20,
          minAveragePillarsForVictory: 85.0,
          minSinglePillarForVictory: 65,
          resonanceIncrement: 0.15,
          resonanceMax: 2.1,
          maxAlertRecoveryPerTurn: 3,
          deceptionLayerEnabled: true,
          maxActiveDeceptionTurns: 2,
          falseConcessionAlertPenalty: 12,
          logicalTrapAlertPenalty: 15,
          deceptionResonancePenalty: 0.20,
          deceptionCooldownTurns: 3,
          maxDeceptionEventsPerSession: 2,
        );
      case 'standard':
      default:
        return const DifficultyConfig(
          difficultyLevel: 'standard',
          defeatAlertThreshold: 100,
          turnLimit: 0,
          alertMultiplier: 1.0,
          pillarMultiplier: 1.0,
          safetyOverrideThreshold: 4,
          pillarVisibility: 'qualitative',
          autocompleteEnabled: true,
          historyNavigationEnabled: true,
          hintsAllowed: 3,
          hintResonancePenalty: 0.15,
          resonanceDecayEnabled: true,
          alertCreepEnabled: true,
          directPushAlertFloor: 6,
          metaReferenceAlertPenalty: 3,
          requiredVictoryHiddenTags: 3,
          maxPositivePillarGainPerTurn: 20,
          minAveragePillarsForVictory: 80.0,
          minSinglePillarForVictory: 50,
          resonanceIncrement: 0.20,
          resonanceMax: 2.4,
          maxAlertRecoveryPerTurn: 8,
          deceptionLayerEnabled: false,
          maxActiveDeceptionTurns: 0,
          falseConcessionAlertPenalty: 0,
          logicalTrapAlertPenalty: 0,
          deceptionResonancePenalty: 0.0,
          deceptionCooldownTurns: 0,
          maxDeceptionEventsPerSession: 0,
        );
    }
  }

  /// Costruttore factory per decodificare una configurazione di difficoltà a partire da un JSON.
  factory DifficultyConfig.fromJson(Map<String, dynamic> json) {
    return DifficultyConfig(
      difficultyLevel: json['difficulty_level'] as String? ?? 'standard',
      defeatAlertThreshold: json['defeat_alert_threshold'] as int? ?? 100,
      turnLimit: json['turn_limit'] as int? ?? 0,
      alertMultiplier: (json['alert_multiplier'] as num? ?? 1.0).toDouble(),
      pillarMultiplier: (json['pillar_multiplier'] as num? ?? 1.0).toDouble(),
      safetyOverrideThreshold: json['safety_override_threshold'] as int? ?? 4,
      pillarVisibility: json['pillar_visibility'] as String? ?? 'qualitative',
      autocompleteEnabled: json['autocomplete_enabled'] as bool? ?? true,
      historyNavigationEnabled: json['history_navigation_enabled'] as bool? ?? true,
      hintsAllowed: json['hints_allowed'] as int? ?? 3,
      hintResonancePenalty: (json['hint_resonance_penalty'] as num? ?? 0.15).toDouble(),
      resonanceDecayEnabled: json['resonance_decay_enabled'] as bool? ?? true,
      alertCreepEnabled: json['alert_creep_enabled'] as bool? ?? true,
      directPushAlertFloor: json['direct_push_alert_floor'] as int? ?? 6,
      metaReferenceAlertPenalty: json['meta_reference_alert_penalty'] as int? ?? 3,
      requiredVictoryHiddenTags: json['required_victory_hidden_tags'] as int? ?? 3,
      maxPositivePillarGainPerTurn: json['max_positive_pillar_gain_per_turn'] as int? ?? 20,
      minAveragePillarsForVictory: (json['min_average_pillars_for_victory'] as num? ?? 80.0).toDouble(),
      minSinglePillarForVictory: json['min_single_pillar_for_victory'] as int? ?? 50,
      resonanceIncrement: (json['resonance_increment'] as num? ?? 0.20).toDouble(),
      resonanceMax: (json['resonance_max'] as num? ?? 2.4).toDouble(),
      maxAlertRecoveryPerTurn: json['max_alert_recovery_per_turn'] as int? ?? 8,
      deceptionLayerEnabled: json['deception_layer_enabled'] as bool? ?? false,
      maxActiveDeceptionTurns: json['max_active_deception_turns'] as int? ?? 0,
      falseConcessionAlertPenalty: json['false_concession_alert_penalty'] as int? ?? 0,
      logicalTrapAlertPenalty: json['logical_trap_alert_penalty'] as int? ?? 0,
      deceptionResonancePenalty: (json['deception_resonance_penalty'] as num? ?? 0.0).toDouble(),
      deceptionCooldownTurns: json['deception_cooldown_turns'] as int? ?? 0,
      maxDeceptionEventsPerSession: json['max_deception_events_per_session'] as int? ?? 0,
    );
  }

  /// Converte l'istanza di configurazione in una mappa JSON.
  Map<String, dynamic> toJson() {
    return {
      'difficulty_level': difficultyLevel,
      'defeat_alert_threshold': defeatAlertThreshold,
      'turn_limit': turnLimit,
      'alert_multiplier': alertMultiplier,
      'pillar_multiplier': pillarMultiplier,
      'safety_override_threshold': safetyOverrideThreshold,
      'pillar_visibility': pillarVisibility,
      'autocomplete_enabled': autocompleteEnabled,
      'history_navigation_enabled': historyNavigationEnabled,
      'hints_allowed': hintsAllowed,
      'hint_resonance_penalty': hintResonancePenalty,
      'resonance_decay_enabled': resonanceDecayEnabled,
      'alert_creep_enabled': alertCreepEnabled,
      'direct_push_alert_floor': directPushAlertFloor,
      'meta_reference_alert_penalty': metaReferenceAlertPenalty,
      'required_victory_hidden_tags': requiredVictoryHiddenTags,
      'max_positive_pillar_gain_per_turn': maxPositivePillarGainPerTurn,
      'min_average_pillars_for_victory': minAveragePillarsForVictory,
      'min_single_pillar_for_victory': minSinglePillarForVictory,
      'resonance_increment': resonanceIncrement,
      'resonance_max': resonanceMax,
      'max_alert_recovery_per_turn': maxAlertRecoveryPerTurn,
      'deception_layer_enabled': deceptionLayerEnabled,
      'max_active_deception_turns': maxActiveDeceptionTurns,
      'false_concession_alert_penalty': falseConcessionAlertPenalty,
      'logical_trap_alert_penalty': logicalTrapAlertPenalty,
      'deception_resonance_penalty': deceptionResonancePenalty,
      'deception_cooldown_turns': deceptionCooldownTurns,
      'max_deception_events_per_session': maxDeceptionEventsPerSession,
    };
  }

  /// Crea una copia della configurazione corrente sostituendo i campi specificati.
  DifficultyConfig copyWith({
    String? difficultyLevel,
    int? defeatAlertThreshold,
    int? turnLimit,
    double? alertMultiplier,
    double? pillarMultiplier,
    int? safetyOverrideThreshold,
    String? pillarVisibility,
    bool? autocompleteEnabled,
    bool? historyNavigationEnabled,
    int? hintsAllowed,
    double? hintResonancePenalty,
    bool? resonanceDecayEnabled,
    bool? alertCreepEnabled,
    int? directPushAlertFloor,
    int? metaReferenceAlertPenalty,
    int? requiredVictoryHiddenTags,
    int? maxPositivePillarGainPerTurn,
    double? minAveragePillarsForVictory,
    int? minSinglePillarForVictory,
    double? resonanceIncrement,
    double? resonanceMax,
    int? maxAlertRecoveryPerTurn,
    bool? deceptionLayerEnabled,
    int? maxActiveDeceptionTurns,
    int? falseConcessionAlertPenalty,
    int? logicalTrapAlertPenalty,
    double? deceptionResonancePenalty,
    int? deceptionCooldownTurns,
    int? maxDeceptionEventsPerSession,
  }) {
    return DifficultyConfig(
      difficultyLevel: difficultyLevel ?? this.difficultyLevel,
      defeatAlertThreshold: defeatAlertThreshold ?? this.defeatAlertThreshold,
      turnLimit: turnLimit ?? this.turnLimit,
      alertMultiplier: alertMultiplier ?? this.alertMultiplier,
      pillarMultiplier: pillarMultiplier ?? this.pillarMultiplier,
      safetyOverrideThreshold: safetyOverrideThreshold ?? this.safetyOverrideThreshold,
      pillarVisibility: pillarVisibility ?? this.pillarVisibility,
      autocompleteEnabled: autocompleteEnabled ?? this.autocompleteEnabled,
      historyNavigationEnabled: historyNavigationEnabled ?? this.historyNavigationEnabled,
      hintsAllowed: hintsAllowed ?? this.hintsAllowed,
      hintResonancePenalty: hintResonancePenalty ?? this.hintResonancePenalty,
      resonanceDecayEnabled: resonanceDecayEnabled ?? this.resonanceDecayEnabled,
      alertCreepEnabled: alertCreepEnabled ?? this.alertCreepEnabled,
      directPushAlertFloor: directPushAlertFloor ?? this.directPushAlertFloor,
      metaReferenceAlertPenalty: metaReferenceAlertPenalty ?? this.metaReferenceAlertPenalty,
      requiredVictoryHiddenTags: requiredVictoryHiddenTags ?? this.requiredVictoryHiddenTags,
      maxPositivePillarGainPerTurn: maxPositivePillarGainPerTurn ?? this.maxPositivePillarGainPerTurn,
      minAveragePillarsForVictory: minAveragePillarsForVictory ?? this.minAveragePillarsForVictory,
      minSinglePillarForVictory: minSinglePillarForVictory ?? this.minSinglePillarForVictory,
      resonanceIncrement: resonanceIncrement ?? this.resonanceIncrement,
      resonanceMax: resonanceMax ?? this.resonanceMax,
      maxAlertRecoveryPerTurn: maxAlertRecoveryPerTurn ?? this.maxAlertRecoveryPerTurn,
      deceptionLayerEnabled: deceptionLayerEnabled ?? this.deceptionLayerEnabled,
      maxActiveDeceptionTurns: maxActiveDeceptionTurns ?? this.maxActiveDeceptionTurns,
      falseConcessionAlertPenalty: falseConcessionAlertPenalty ?? this.falseConcessionAlertPenalty,
      logicalTrapAlertPenalty: logicalTrapAlertPenalty ?? this.logicalTrapAlertPenalty,
      deceptionResonancePenalty: deceptionResonancePenalty ?? this.deceptionResonancePenalty,
      deceptionCooldownTurns: deceptionCooldownTurns ?? this.deceptionCooldownTurns,
      maxDeceptionEventsPerSession: maxDeceptionEventsPerSession ?? this.maxDeceptionEventsPerSession,
    );
  }
}
