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
          requiredVictoryHiddenTags: 2,
          maxPositivePillarGainPerTurn: 25,
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
      requiredVictoryHiddenTags: json['required_victory_hidden_tags'] as int? ?? 2,
      maxPositivePillarGainPerTurn: json['max_positive_pillar_gain_per_turn'] as int? ?? 25,
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
    );
  }
}
