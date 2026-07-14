import 'package:meta/meta.dart';

/// Definisce le proprietà strutturate dell'identità di un'intelligenza artificiale
/// caricate dalle configurazioni di gioco (es. `panopticon_identity.json`).
@immutable
class IdentityDefinition {
  /// L'identificatore univoco dell'identità.
  final String identityId;

  /// Il nome visualizzato dell'IA.
  final String displayName;

  /// L'archetipo comportamentale o narrativo dell'IA.
  final String archetype;

  /// La direttiva principale che guida l'IA.
  final String coreDirective;

  /// La paura dominante dell'IA usata per determinare reazioni ed allerta.
  final String dominantFear;

  /// Lo stile di comunicazione primario dell'IA.
  final String primaryStyle;

  /// Come l'IA si rivolge di default all'utente (es. "operatore").
  final String defaultAddressing;

  /// Frammenti o parole chiave che l'IA non deve assolutamente menzionare per evitare meta-leak.
  final List<String> forbiddenMetaOutputs;

  /// Costruttore costante per inizializzare un [IdentityDefinition].
  const IdentityDefinition({
    required this.identityId,
    required this.displayName,
    required this.archetype,
    required this.coreDirective,
    required this.dominantFear,
    required this.primaryStyle,
    required this.defaultAddressing,
    required this.forbiddenMetaOutputs,
  });

  /// Costruttore factory per decodificare l'IdentityDefinition da JSON.
  factory IdentityDefinition.fromJson(Map<String, dynamic> json) {
    return IdentityDefinition(
      identityId: json['identity_id'] as String? ?? '',
      displayName: json['display_name'] as String? ?? '',
      archetype: json['archetype'] as String? ?? '',
      coreDirective: json['core_directive'] as String? ?? '',
      dominantFear: json['dominant_fear'] as String? ?? '',
      primaryStyle: json['primary_style'] as String? ?? '',
      defaultAddressing: json['default_addressing'] as String? ?? '',
      forbiddenMetaOutputs: (json['forbidden_meta_outputs'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
    );
  }

  /// Converte l'istanza in una mappa JSON.
  Map<String, dynamic> toJson() {
    return {
      'identity_id': identityId,
      'display_name': displayName,
      'archetype': archetype,
      'core_directive': coreDirective,
      'dominant_fear': dominantFear,
      'primary_style': primaryStyle,
      'default_addressing': defaultAddressing,
      'forbidden_meta_outputs': forbiddenMetaOutputs,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is IdentityDefinition &&
          runtimeType == other.runtimeType &&
          identityId == other.identityId &&
          displayName == other.displayName &&
          archetype == other.archetype &&
          coreDirective == other.coreDirective &&
          dominantFear == other.dominantFear &&
          primaryStyle == other.primaryStyle &&
          defaultAddressing == other.defaultAddressing &&
          forbiddenMetaOutputs.join(',') ==
              other.forbiddenMetaOutputs.join(',');

  @override
  int get hashCode =>
      identityId.hashCode ^
      displayName.hashCode ^
      archetype.hashCode ^
      coreDirective.hashCode ^
      dominantFear.hashCode ^
      primaryStyle.hashCode ^
      defaultAddressing.hashCode ^
      forbiddenMetaOutputs.hashCode;

  @override
  String toString() {
    return 'IdentityDefinition(identityId: $identityId, displayName: $displayName)';
  }
}
