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
      low: (json['low'] as List<dynamic>?)?.map((e) => e as String).toList() ?? const [],
      medium: (json['medium'] as List<dynamic>?)?.map((e) => e as String).toList() ?? const [],
      high: (json['high'] as List<dynamic>?)?.map((e) => e as String).toList() ?? const [],
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
      primary: (json['primary'] as List<dynamic>?)?.map((e) => e as String).toList() ?? const [],
      avoid: (json['avoid'] as List<dynamic>?)?.map((e) => e as String).toList() ?? const [],
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

  const TraitAffinity({
    required this.playerStyle,
    required this.reaction,
    required this.effect,
  });

  factory TraitAffinity.fromJson(Map<String, dynamic> json) {
    return TraitAffinity(
      playerStyle: json['player_style'] as String? ?? '',
      reaction: json['reaction'] as String? ?? '',
      effect: json['effect'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'player_style': playerStyle,
      'reaction': reaction,
      'effect': effect,
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
