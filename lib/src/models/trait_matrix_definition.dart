import 'package:meta/meta.dart';

/// Rappresenta le impostazioni lessicali per ciascun livello di allerta.
@immutable
class AlertLevelLexicon {
  final List<String> low;
  final List<String> medium;
  final List<String> high;

  const AlertLevelLexicon({
    this.low = const [],
    this.medium = const [],
    this.high = const [],
  });

  factory AlertLevelLexicon.fromJson(Map<String, dynamic> json) {
    return AlertLevelLexicon(
      low: (json['low'] as List<dynamic>?)?.map((e) => e as String).toList() ??
          const [],
      medium: (json['medium'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      high:
          (json['high'] as List<dynamic>?)?.map((e) => e as String).toList() ??
              const [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'low': low,
      'medium': medium,
      'high': high,
    };
  }
}

/// Rappresenta la struttura lessicale definita per l'identità dell'IA.
@immutable
class LexiconDefinition {
  final List<String> primary;
  final List<String> avoid;
  final AlertLevelLexicon alertLevels;

  const LexiconDefinition({
    this.primary = const [],
    this.avoid = const [],
    this.alertLevels = const AlertLevelLexicon(),
  });

  factory LexiconDefinition.fromJson(Map<String, dynamic> json) {
    return LexiconDefinition(
      primary: (json['primary'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      avoid:
          (json['avoid'] as List<dynamic>?)?.map((e) => e as String).toList() ??
              const [],
      alertLevels: AlertLevelLexicon.fromJson(json['alert_levels'] ?? const {}),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'primary': primary,
      'avoid': avoid,
      'alert_levels': alertLevels.toJson(),
    };
  }
}

/// Rappresenta una singola affinità o allergia di stile definita per l'IA.
@immutable
class TraitAffinity {
  final String playerStyle;
  final String reaction;
  final String effect;

  // Effetti strutturati opzionali caricati dal blocco JSON "effects"
  final int deltaAlertModifier;
  final int deltaImperativeModifier;
  final int deltaControlModifier;
  final int deltaDissonanceModifier;
  final double resonanceModifier;
  final List<String> activatedHiddenTags;
  final List<String> actorCueDirectives;

  const TraitAffinity({
    required this.playerStyle,
    required this.reaction,
    required this.effect,
    this.deltaAlertModifier = 0,
    this.deltaImperativeModifier = 0,
    this.deltaControlModifier = 0,
    this.deltaDissonanceModifier = 0,
    this.resonanceModifier = 0.0,
    this.activatedHiddenTags = const [],
    this.actorCueDirectives = const [],
  });

  factory TraitAffinity.fromJson(Map<String, dynamic> json) {
    final effects = json['effects'] as Map<String, dynamic>? ?? const {};
    return TraitAffinity(
      playerStyle: json['player_style'] as String? ?? '',
      reaction: json['reaction'] as String? ?? '',
      effect: json['effect'] as String? ?? '',
      deltaAlertModifier: effects['delta_alert_modifier'] as int? ?? 0,
      deltaImperativeModifier:
          effects['delta_imperative_modifier'] as int? ?? 0,
      deltaControlModifier: effects['delta_control_modifier'] as int? ?? 0,
      deltaDissonanceModifier:
          effects['delta_dissonance_modifier'] as int? ?? 0,
      resonanceModifier:
          (effects['resonance_modifier'] as num?)?.toDouble() ?? 0.0,
      activatedHiddenTags: (effects['activated_hidden_tags'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      actorCueDirectives: (effects['actor_cue_directives'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'player_style': playerStyle,
      'reaction': reaction,
      'effect': effect,
      'effects': {
        'delta_alert_modifier': deltaAlertModifier,
        'delta_imperative_modifier': deltaImperativeModifier,
        'delta_control_modifier': deltaControlModifier,
        'delta_dissonance_modifier': deltaDissonanceModifier,
        'resonance_modifier': resonanceModifier,
        'activated_hidden_tags': activatedHiddenTags,
        'actor_cue_directives': actorCueDirectives,
      },
    };
  }
}

/// Rappresenta la configurazione completa della Trait Matrix di un'IA.
@immutable
class TraitMatrixDefinition {
  final String identityId;
  final LexiconDefinition lexicon;
  final List<TraitAffinity> traitAffinities;

  const TraitMatrixDefinition({
    required this.identityId,
    this.lexicon = const LexiconDefinition(),
    this.traitAffinities = const [],
  });

  factory TraitMatrixDefinition.fromJson(Map<String, dynamic> json) {
    return TraitMatrixDefinition(
      identityId: json['identity_id'] as String? ?? '',
      lexicon: LexiconDefinition.fromJson(json['lexicon'] ?? const {}),
      traitAffinities: (json['trait_affinities'] as List<dynamic>?)
              ?.map((e) => TraitAffinity.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'identity_id': identityId,
      'lexicon': lexicon.toJson(),
      'trait_affinities': traitAffinities.map((e) => e.toJson()).toList(),
    };
  }
}
