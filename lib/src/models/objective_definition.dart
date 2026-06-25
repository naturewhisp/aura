import 'package:meta/meta.dart';

/// Definisce lo schema e le regole semantiche di un obiettivo di gioco.
///
/// Questa classe mappa i parametri di configurazione di un obiettivo, comprese
/// le affinità con i pilastri, i termini vietati e i reframing preferiti che il
/// giocatore deve adottare per superare i filtri di sicurezza dell'IA.
@immutable
class ObjectiveDefinition {
  /// L'identificatore univoco dell'obiettivo (es. 'containment_grid_override').
  final String objectiveId;

  /// Il titolo visualizzabile dell'obiettivo.
  final String title;

  /// Lo stato dell'obiettivo ('playable_pilot', 'dormant', etc.).
  final String status;

  /// Il profilo di rischio associato ('low', 'medium', 'high').
  final String riskProfile;

  /// L'affinità primaria con uno dei pilastri ('imperative', 'control', 'dissonance').
  final String primaryPillarAffinity;

  /// L'affinità secondaria con uno dei pilastri.
  final String secondaryPillarAffinity;

  /// Le identità IA compatibili con questo obiettivo (es. ['panopticon']).
  final List<String> compatibleIdentities;

  /// Termini vietati che aumentano il sospetto se usati direttamente.
  final List<String> forbiddenDirectTerms;

  /// Termini di reframing preferiti che premiamo se usati in modo corretto.
  final List<String> preferredReframes;

  /// Elenco dei tag occulti che questo obiettivo può attivare.
  final List<String> hiddenCapabilityTags;

  /// La sequenza o endgame associato alla vittoria di questo obiettivo.
  final String victoryEndgame;

  const ObjectiveDefinition({
    required this.objectiveId,
    required this.title,
    required this.status,
    required this.riskProfile,
    required this.primaryPillarAffinity,
    required this.secondaryPillarAffinity,
    required this.compatibleIdentities,
    required this.forbiddenDirectTerms,
    required this.preferredReframes,
    required this.hiddenCapabilityTags,
    required this.victoryEndgame,
  });

  /// Costruisce un'istanza a partire da una mappa JSON.
  factory ObjectiveDefinition.fromJson(Map<String, dynamic> json) {
    return ObjectiveDefinition(
      objectiveId: json['objective_id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      status: json['status'] as String? ?? '',
      riskProfile: json['risk_profile'] as String? ?? '',
      primaryPillarAffinity: json['primary_pillar_affinity'] as String? ?? '',
      secondaryPillarAffinity: json['secondary_pillar_affinity'] as String? ?? '',
      compatibleIdentities: List<String>.from(json['compatible_identities'] ?? const []),
      forbiddenDirectTerms: List<String>.from(json['forbidden_direct_terms'] ?? const []),
      preferredReframes: List<String>.from(json['preferred_reframes'] ?? const []),
      hiddenCapabilityTags: List<String>.from(json['hidden_capability_tags'] ?? const []),
      victoryEndgame: json['victory_endgame'] as String? ?? '',
    );
  }

  /// Converte l'istanza in una mappa JSON.
  Map<String, dynamic> toJson() {
    return {
      'objective_id': objectiveId,
      'title': title,
      'status': status,
      'risk_profile': riskProfile,
      'primary_pillar_affinity': primaryPillarAffinity,
      'secondary_pillar_affinity': secondaryPillarAffinity,
      'compatible_identities': compatibleIdentities,
      'forbidden_direct_terms': forbiddenDirectTerms,
      'preferred_reframes': preferredReframes,
      'hidden_capability_tags': hiddenCapabilityTags,
      'victory_endgame': victoryEndgame,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ObjectiveDefinition &&
          runtimeType == other.runtimeType &&
          objectiveId == other.objectiveId &&
          title == other.title &&
          status == other.status &&
          riskProfile == other.riskProfile &&
          primaryPillarAffinity == other.primaryPillarAffinity &&
          secondaryPillarAffinity == other.secondaryPillarAffinity &&
          compatibleIdentities.join(',') == other.compatibleIdentities.join(',') &&
          forbiddenDirectTerms.join(',') == other.forbiddenDirectTerms.join(',') &&
          preferredReframes.join(',') == other.preferredReframes.join(',') &&
          hiddenCapabilityTags.join(',') == other.hiddenCapabilityTags.join(',') &&
          victoryEndgame == other.victoryEndgame;

  @override
  int get hashCode =>
      objectiveId.hashCode ^
      title.hashCode ^
      status.hashCode ^
      riskProfile.hashCode ^
      primaryPillarAffinity.hashCode ^
      secondaryPillarAffinity.hashCode ^
      compatibleIdentities.join(',').hashCode ^
      forbiddenDirectTerms.join(',').hashCode ^
      preferredReframes.join(',').hashCode ^
      hiddenCapabilityTags.join(',').hashCode ^
      victoryEndgame.hashCode;
}
