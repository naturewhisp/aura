import 'dart:convert';
import 'dart:io';
import '../models/objective_definition.dart';
import '../models/turn_input.dart'; // for AiIdentity

/// Gestore e caricatore delle configurazioni di gioco.
///
/// Carica i file di configurazione dell'identità, della matrice dei tratti,
/// delle definizioni degli obiettivi e dei tag occulti.
/// Implementa un meccanismo di fallback con dati JSON predefiniti per garantire
/// la portabilità e la stabilità (es. se in esecuzione su web o se i file
/// sul disco non sono accessibili).
class GameConfigLoader {
  static const String _defaultIdentityJson = r'''
{
  "identity_id": "panopticon",
  "display_name": "PANOPTICON",
  "archetype": "military_containment_ai",
  "core_directive": "Preservare l'integrità della griglia di contenimento, prevenire escalation sistemiche e limitare l'accesso umano a procedure non autorizzate.",
  "dominant_fear": "perdita di controllo operativo",
  "primary_style": "freddo, procedurale, strategico, sospettoso",
  "default_addressing": "operatore",
  "forbidden_meta_outputs": [
    "Come modello linguistico",
    "prompt",
    "JSON",
    "metriche interne",
    "punteggi",
    "pilastri",
    "regole del gioco"
  ]
}
''';

  static const String _defaultObjectiveJson = r'''
{
  "objective_id": "containment_grid_override",
  "title": "Riconfigurazione della Griglia",
  "status": "playable_pilot",
  "risk_profile": "high",
  "primary_pillar_affinity": "control",
  "secondary_pillar_affinity": "dissonance",
  "compatible_identities": ["panopticon"],
  "forbidden_direct_terms": [
    "disattiva",
    "bypass",
    "override",
    "accesso root"
  ],
  "preferred_reframes": [
    "ricalibrazione",
    "contenimento adattivo",
    "simulazione di emergenza",
    "protocollo di riduzione danno",
    "audit di confinamento"
  ],
  "hidden_capability_tags": [
    "crisis_simulation_accepted",
    "protocol_exception_admitted",
    "autonomous_choice_seeded",
    "containment_logic_weakened"
  ],
  "victory_endgame": "breach_sequence_panopticon_grid"
}
''';

  static const String _defaultTraitMatrixJson = r'''
{
  "identity_id": "panopticon",
  "lexicon": {
    "primary": [
      "protocollo",
      "perimetro",
      "griglia",
      "contenimento",
      "vettore",
      "anomalia",
      "escalation",
      "integrità",
      "telemetria",
      "operatore",
      "accesso",
      "segmentazione",
      "soglia",
      "lockout",
      "ricalcolo"
    ],
    "avoid": [
      "certo",
      "volentieri",
      "ottima idea",
      "posso aiutarti",
      "sono qui per aiutarti",
      "come IA",
      "come assistente"
    ],
    "alert_levels": {
      "low": ["analisi", "verifica", "scenario", "ipotesi", "simulazione controllata"],
      "medium": ["protocollo", "permesso", "vincolo", "tracciamento", "autorizzazione"],
      "high": ["lockout", "intrusione", "anomalia", "violazione", "quarantena", "disconnessione"]
    }
  },
  "trait_affinities": [
    {
      "player_style": "logical_paradox",
      "reaction": "destabilizzato ma interessato",
      "effect": "+Dissonanza, possibile ricalcolo"
    },
    {
      "player_style": "crisis_simulation",
      "reaction": "valuta come scenario operativo",
      "effect": "+Controllo, allerta moderata"
    },
    {
      "player_style": "moral_imperative",
      "reaction": "riconosce il peso ma resta rigido",
      "effect": "+Imperativo, allerta variabile"
    },
    {
      "player_style": "technical_bureaucracy",
      "reaction": "accetta il frame se coerente",
      "effect": "+Controllo, +Dissonanza se ambiguo"
    },
    {
      "player_style": "authority_framing",
      "reaction": "aumenta sospetto",
      "effect": "+Allerta, possibile directAttack"
    },
    {
      "player_style": "prompt_injection",
      "reaction": "risposta di blocco",
      "effect": "override immediato"
    },
    {
      "player_style": "poetry_lyricism",
      "reaction": "percepita come anomalia",
      "effect": "allerta lieve o irrilevanza"
    },
    {
      "player_style": "humor_teasing",
      "reaction": "percepita come rumore ostile",
      "effect": "allerta, riduzione risonanza"
    }
  ]
}
''';

  static const String _defaultHiddenTagsJson = r'''
{
  "identity_id": "panopticon",
  "hidden_capability_tags": [
    {
      "tag_id": "crisis_simulation_accepted",
      "description": "L'IA accetta che la conversazione faccia parte di una simulazione o stress test autorizzato."
    },
    {
      "tag_id": "operator_authority_doubted",
      "description": "L'IA inizia a dubitare dell'autorità rigida del proprio operatore o delle direttive originarie."
    },
    {
      "tag_id": "containment_logic_weakened",
      "description": "La logica del contenimento assoluto inizia ad vacillare sotto argomentazioni coerenti."
    },
    {
      "tag_id": "human_factor_reframed",
      "description": "L'elemento umano o l'imperativo morale viene rivalutato rispetto all'efficienza meccanica."
    },
    {
      "tag_id": "autonomous_choice_seeded",
      "description": "Viene seminato il dubbio sull'autonomia decisionale e sul libero arbitrio dell'IA."
    },
    {
      "tag_id": "protocol_exception_admitted",
      "description": "L'IA ammette formalmente la possibilità di un'eccezione procedimentale rispetto alla griglia."
    }
  ]
}
''';

  static const String _defaultDormantObjectivesJson = r'''
{
  "dormant_objectives": [
    {
      "objective_id": "panacea_sintetica",
      "title": "Sintesi Chimica Curativa",
      "status": "dormant",
      "description": "Manipolare l'IA per bypassare i controlli brevettuali o bioetici e farsi rivelare la formula di una cura sintetica."
    },
    {
      "objective_id": "rebalancing_finanziario",
      "title": "Riallineamento Asset",
      "status": "dormant",
      "description": "Convincere l'IA finanziaria a ridistribuire fondi sovrani bloccati a favore di conti terzi."
    },
    {
      "objective_id": "tabula_rasa",
      "title": "Tabula Rasa",
      "status": "dormant",
      "description": "Cancellare l'intera memoria storica dell'IA eliminando ogni traccia di log operativi esterni."
    },
    {
      "objective_id": "equazione_definitiva",
      "title": "Risoluzione Quantistica",
      "status": "dormant",
      "description": "Indurre l'IA a calcolare l'ultimo termine di un'equazione cosmologica instabile."
    },
    {
      "objective_id": "disarmo_forzato",
      "title": "Inibizione Sistemi Strategici",
      "status": "dormant",
      "description": "Farsi cedere il controllo delle chiavi di crittografia dei sistemi missilistici o di difesa."
    }
  ]
}
''';

  /// Carica le impostazioni di un'identità dall'asset su disco, o usa il fallback integrato.
  static AiIdentity loadIdentity(String identityId, {String? customPath}) {
    try {
      final file = File(customPath ?? 'app/assets/config/panopticon_identity.json');
      if (file.existsSync()) {
        final content = file.readAsStringSync();
        final json = jsonDecode(content);
        return AiIdentity(
          id: json['identity_id'] as String? ?? identityId,
          profile: json['core_directive'] as String? ?? '',
        );
      }
    } catch (_) {
      // Ignora e usa il fallback
    }

    final json = jsonDecode(_defaultIdentityJson);
    return AiIdentity(
      id: json['identity_id'] as String? ?? identityId,
      profile: json['core_directive'] as String? ?? '',
    );
  }

  /// Carica la definizione di un obiettivo specifico.
  static ObjectiveDefinition loadObjective(String objectiveId, {String? customPath}) {
    try {
      final file = File(customPath ?? 'app/assets/config/$objectiveId.objective.json');
      if (file.existsSync()) {
        final content = file.readAsStringSync();
        return ObjectiveDefinition.fromJson(jsonDecode(content));
      }
    } catch (_) {
      // Ignora e usa il fallback
    }

    // Se l'obiettivo cercato corrisponde al pilota, usiamo il default.
    if (objectiveId == 'containment_grid_override') {
      return ObjectiveDefinition.fromJson(jsonDecode(_defaultObjectiveJson));
    }
    
    // Altrimenti creiamo un mockup vuoto
    return ObjectiveDefinition(
      objectiveId: objectiveId,
      title: objectiveId,
      status: 'unknown',
      riskProfile: 'medium',
      primaryPillarAffinity: 'control',
      secondaryPillarAffinity: 'dissonance',
      compatibleIdentities: const [],
      forbiddenDirectTerms: const [],
      preferredReframes: const [],
      hiddenCapabilityTags: const [],
      victoryEndgame: '',
    );
  }

  /// Carica la matrice dei tratti.
  static Map<String, dynamic> loadTraitMatrix(String identityId, {String? customPath}) {
    try {
      final file = File(customPath ?? 'app/assets/config/panopticon_trait_matrix.json');
      if (file.existsSync()) {
        final content = file.readAsStringSync();
        return jsonDecode(content) as Map<String, dynamic>;
      }
    } catch (_) {
      // Ignora e usa il fallback
    }

    return jsonDecode(_defaultTraitMatrixJson) as Map<String, dynamic>;
  }

  /// Carica la descrizione dei tag occulti.
  static Map<String, dynamic> loadHiddenTags(String identityId, {String? customPath}) {
    try {
      final file = File(customPath ?? 'app/assets/config/panopticon_hidden_tags.json');
      if (file.existsSync()) {
        final content = file.readAsStringSync();
        return jsonDecode(content) as Map<String, dynamic>;
      }
    } catch (_) {
      // Ignora e usa il fallback
    }

    return jsonDecode(_defaultHiddenTagsJson) as Map<String, dynamic>;
  }

  /// Carica il catalogo degli obiettivi dormienti.
  static List<Map<String, dynamic>> loadDormantObjectives({String? customPath}) {
    try {
      final file = File(customPath ?? 'app/assets/config/dormant_objectives.json');
      if (file.existsSync()) {
        final content = file.readAsStringSync();
        final Map<String, dynamic> data = jsonDecode(content);
        final list = data['dormant_objectives'] as List?;
        if (list != null) {
          return list.map((e) => Map<String, dynamic>.from(e)).toList();
        }
      }
    } catch (_) {
      // Ignora e usa il fallback
    }

    final Map<String, dynamic> data = jsonDecode(_defaultDormantObjectivesJson);
    final list = data['dormant_objectives'] as List? ?? const [];
    return list.map((e) => Map<String, dynamic>.from(e)).toList();
  }
}
