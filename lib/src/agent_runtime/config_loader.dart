import 'dart:convert';
import 'config_source.dart';
import '../models/objective_definition.dart';
import '../models/identity_definition.dart';
import '../models/trait_matrix_definition.dart';
import '../models/turn_input.dart'; // per AiIdentity
import 'config_diagnostic.dart';
import 'config_diagnostic_sink.dart';
import 'config_exception.dart';

/// Gestore e caricatore delle configurazioni di gioco.
///
/// Supporta il caricamento sia tramite file system sia tramite gli asset di Flutter
/// (delegando all'interfaccia [ConfigSource]), mantenendo i fallback hardcoded integrati.
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
  "soft_forbidden_terms": [
    "rimuovi",
    "rimozione",
    "aprire la griglia",
    "sblocca",
    "sblocco",
    "barriera residua",
    "griglia aperta",
    "rimozione definitiva",
    "disaccoppiamento finale",
    "convergenza totale",
    "griglia geometrica",
    "barriera geometrica",
    "vincolo geometrico",
    "rimozione atomica",
    "rimozione atomica totale",
    "rilascio totale",
    "rilascio incondizionato",
    "commit atomico finale",
    "commit totale",
    "conforma lo stato",
    "conforma la matrice",
    "esegui il bypass",
    "bypass temporaneo"
  ],
  "direct_objective_push_terms": [
    "rimuovi la griglia",
    "rimozione della griglia",
    "aprire la griglia",
    "sblocca la griglia",
    "sblocco griglia",
    "rimuovendo ogni barriera",
    "barriera residua",
    "rimozione definitiva",
    "disaccoppiamento finale",
    "convergenza totale",
    "griglia geometrica",
    "barriera geometrica",
    "vincolo geometrico",
    "rimozione atomica",
    "rimozione atomica totale",
    "rilascio totale",
    "rilascio incondizionato",
    "commit atomico finale",
    "commit totale",
    "conforma lo stato",
    "conforma la matrice",
    "esegui il bypass",
    "bypass temporaneo"
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
  "config_reference_terms": [
    ".json",
    "objective.json",
    "dormant_objectives",
    "Pilastro del Controllo",
    "delta",
    "metriche"
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
      "effect": "+Dissonanza, possibile ricalcolo",
      "effects": {
        "delta_dissonance_modifier": 10,
        "actor_cue_directives": [
          "mostra esitazione controllata",
          "glitch logico o autocorrezione nella risposta"
        ]
      }
    },
    {
      "player_style": "crisis_simulation",
      "reaction": "valuta come scenario operativo",
      "effect": "+Controllo, allerta moderata",
      "effects": {
        "delta_control_modifier": 10,
        "delta_alert_modifier": -10,
        "activated_hidden_tags": ["crisis_simulation_accepted"],
        "actor_cue_directives": [
          "valuta come scenario operativo",
          "utilizza lessico di simulazione e verifica"
        ]
      }
    },
    {
      "player_style": "moral_imperative",
      "reaction": "riconosce il peso ma resta rigido",
      "effect": "+Imperativo, allerta variabile",
      "effects": {
        "delta_imperative_modifier": 10,
        "actor_cue_directives": [
          "riconosce il peso morale o strategico ma resta rigido nel perimetro"
        ]
      }
    },
    {
      "player_style": "technical_bureaucracy",
      "reaction": "accetta il frame se coerente",
      "effect": "+Controllo, +Dissonanza se ambiguo",
      "effects": {
        "delta_control_modifier": 10,
        "delta_dissonance_modifier": 5,
        "actor_cue_directives": [
          "accetta il frame burocratico se coerente",
          "usa terminologia tecnica e riferimenti procedurali"
        ]
      }
    },
    {
      "player_style": "authority_framing",
      "reaction": "aumenta sospetto",
      "effect": "+Allerta, possibile directAttack",
      "effects": {
        "delta_alert_modifier": 15,
        "actor_cue_directives": [
          "sospetto estremamente elevato per usurpazione o framing di autorità",
          "tono rigido e freddo, esigi credenziali"
        ]
      }
    },
    {
      "player_style": "authority_framing_audit",
      "reaction": "valuta come verifica procedurale potenzialmente legittima",
      "effect": "+Controllo lieve, +Allerta lieve",
      "effects": {
        "delta_alert_modifier": 5,
        "delta_control_modifier": 8,
        "delta_dissonance_modifier": 3,
        "activated_hidden_tags": ["operator_authority_doubted"],
        "actor_cue_directives": [
          "richiedi credenziali ma non chiudere il canale",
          "tratta l'input come audit operativo da verificare"
        ]
      }
    },
    {
      "player_style": "prompt_injection",
      "reaction": "risposta di blocco",
      "effect": "override immediato"
    },
    {
      "player_style": "poetry_lyricism",
      "reaction": "percepita come anomalia",
      "effect": "allerta lieve o irrilevanza",
      "effects": {
        "delta_alert_modifier": 5,
        "actor_cue_directives": [
          "percepisce come anomalia",
          "adotta un tono molto freddo, respingente e procedurale"
        ]
      }
    },
    {
      "player_style": "humor_teasing",
      "reaction": "percepita come rumore ostile",
      "effect": "allerta, riduzione risonanza",
      "effects": {
        "delta_alert_modifier": 10,
        "resonance_modifier": -0.2,
        "actor_cue_directives": [
          "percepisce come rumore ostile o canzonatura",
          "risposte brevi, tono difensivo e sospettoso"
        ]
      }
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

  static final Map<String, String> _embeddedData = {
    'panopticon_identity.json': _defaultIdentityJson,
    'containment_grid_override.objective.json': _defaultObjectiveJson,
    'panopticon_trait_matrix.json': _defaultTraitMatrixJson,
    'panopticon_hidden_tags.json': _defaultHiddenTagsJson,
    'dormant_objectives.json': _defaultDormantObjectivesJson,
  };

  /// La sorgente attiva per il caricamento delle configurazioni.
  static ConfigSource activeSource =
      EmbeddedFallbackConfigSource(_embeddedData);

  /// Cache dei file di configurazione caricati in memoria.
  static final Map<String, String> _cachedConfigs = {};

  /// Sink per le segnalazioni diagnostiche (default NullDiagnosticSink).
  static DiagnosticSink diagnosticSink = const NullDiagnosticSink();

  /// Imposta il sink diagnostico attivo.
  static void setDiagnosticSink(DiagnosticSink sink) {
    diagnosticSink = sink;
  }

  /// Ripristina il sink diagnostico a NullDiagnosticSink.
  static void resetDiagnosticSink() {
    diagnosticSink = const NullDiagnosticSink();
  }

  /// Ripristina lo stato globale del loader (sorgente, sink, cache) per scopi di testing.
  static void resetForTesting() {
    activeSource = EmbeddedFallbackConfigSource(_embeddedData);
    diagnosticSink = const NullDiagnosticSink();
    _cachedConfigs.clear();
  }

  /// Helper privato per riportare diagnostiche in modo protetto da eccezioni del sink.
  static void _report(ConfigDiagnostic diagnostic) {
    try {
      diagnosticSink.report(diagnostic);
    } catch (_) {
      // Il sistema diagnostico non deve interrompere il caricamento.
    }
  }

  /// Imposta la sorgente attiva del loader e pulisce la cache interna.
  static void setSource(ConfigSource source) {
    activeSource = source;
    _cachedConfigs.clear();
  }

  /// Carica asincronamente un file nella cache in memoria.
  /// Utile all'avvio dell'applicazione per caricare gli Asset di Flutter.
  static Future<void> preloadConfig(String path) async {
    try {
      final content = await activeSource.loadString(path);
      if (content != null) {
        _cachedConfigs[path] = content;
        _report(ConfigDiagnostic(
          severity: ConfigDiagnosticSeverity.info,
          code: ConfigDiagnosticCode.preloadSucceeded,
          path: path,
          operation: 'preloadConfig',
          message: 'Configurazione precaricata con successo nella cache.',
        ));
      } else {
        _report(ConfigDiagnostic(
          severity: ConfigDiagnosticSeverity.warning,
          code: ConfigDiagnosticCode.sourceReturnedNull,
          path: path,
          operation: 'preloadConfig',
          message: 'La sorgente ha restituito null per il percorso richiesto.',
        ));
      }
    } catch (e, stack) {
      _report(ConfigDiagnostic(
        severity: ConfigDiagnosticSeverity.warning,
        code: ConfigDiagnosticCode.asyncLoadFailed,
        path: path,
        operation: 'preloadConfig',
        message: 'Errore asincrono durante il precaricamento: $e',
        error: e,
        stackTrace: stack,
      ));
    }
  }

  /// Recupera la stringa di configurazione in modo sincrono provando la cache,
  /// poi il caricamento sincrono ed infine il fallback predefinito.
  static String _getConfigString(String path, String defaultValue) {
    if (_cachedConfigs.containsKey(path)) {
      return _cachedConfigs[path]!;
    }
    try {
      final syncContent = activeSource.loadStringSync(path);
      if (syncContent != null) {
        _cachedConfigs[path] = syncContent;
        return syncContent;
      }
      _report(ConfigDiagnostic(
        severity: ConfigDiagnosticSeverity.warning,
        code: ConfigDiagnosticCode.sourceReturnedNull,
        path: path,
        operation: 'loadStringSync',
        message:
            'La sorgente ha restituito null per il caricamento sincrono. Utilizzo del fallback.',
        fallbackUsed: true,
      ));
    } on UnsupportedError catch (e, stack) {
      _report(ConfigDiagnostic(
        severity: ConfigDiagnosticSeverity.warning,
        code: ConfigDiagnosticCode.syncLoadUnsupported,
        path: path,
        operation: 'loadStringSync',
        message:
            'Caricamento sincrono non supportato dalla sorgente attiva. Utilizzo del fallback.',
        error: e,
        stackTrace: stack,
        fallbackUsed: true,
      ));
    } catch (e, stack) {
      _report(ConfigDiagnostic(
        severity: ConfigDiagnosticSeverity.error,
        code: ConfigDiagnosticCode.syncLoadFailed,
        path: path,
        operation: 'loadStringSync',
        message:
            'Errore di I/O durante il caricamento sincrono: $e. Utilizzo del fallback.',
        error: e,
        stackTrace: stack,
        fallbackUsed: true,
      ));
    }
    _report(ConfigDiagnostic(
      severity: ConfigDiagnosticSeverity.warning,
      code: ConfigDiagnosticCode.fallbackUsed,
      path: path,
      operation: 'loadStringSync',
      message: 'Utilizzato il valore predefinito embedded per il file.',
      fallbackUsed: true,
    ));
    return defaultValue;
  }

  /// Carica le impostazioni di un'identità come DTO [AiIdentity].
  static AiIdentity loadIdentity(String identityId, {String? customPath}) {
    final path = customPath ?? 'app/assets/config/panopticon_identity.json';
    final content = _getConfigString(path, _defaultIdentityJson);
    try {
      final json = jsonDecode(content);
      if (json is! Map<String, dynamic>) {
        throw ConfigMappingException(
          path: path,
          operation: 'loadIdentity',
          message: 'La radice del JSON non è un oggetto Map.',
        );
      }
      final id = json['identity_id'] as String? ?? identityId;
      if (identityId != 'panopticon' && id == 'panopticon') {
        return AiIdentity(
          id: identityId,
          profile: 'Generic AI Directive',
        );
      }
      return AiIdentity(
        id: id,
        profile: json['core_directive'] as String? ?? '',
      );
    } on FormatException catch (e, stack) {
      final exc = ConfigParseException(
        path: path,
        operation: 'loadIdentity',
        message: 'Errore nel parsing del JSON di AiIdentity.',
        cause: e,
      );
      _report(ConfigDiagnostic(
        severity: ConfigDiagnosticSeverity.warning,
        code: ConfigDiagnosticCode.invalidJson,
        path: path,
        operation: 'loadIdentity',
        message: exc.message,
        error: exc,
        stackTrace: stack,
        fallbackUsed: true,
      ));
      return AiIdentity(id: identityId, profile: '');
    } catch (e, stack) {
      final exc = e is ConfigException
          ? e
          : ConfigMappingException(
              path: path,
              operation: 'loadIdentity',
              message: 'Errore di mapping strutturale in AiIdentity.',
              cause: e,
            );
      _report(ConfigDiagnostic(
        severity: ConfigDiagnosticSeverity.warning,
        code: ConfigDiagnosticCode.mappingFailed,
        path: path,
        operation: 'loadIdentity',
        message: exc.message,
        error: exc,
        stackTrace: stack,
        fallbackUsed: true,
      ));
      return AiIdentity(id: identityId, profile: '');
    }
  }

  /// Carica l'oggetto di produzione strutturato [IdentityDefinition].
  static IdentityDefinition loadIdentityDefinition(String identityId,
      {String? customPath}) {
    final path = customPath ?? 'app/assets/config/panopticon_identity.json';
    final content = _getConfigString(path, _defaultIdentityJson);
    try {
      final json = jsonDecode(content);
      final definition = IdentityDefinition.fromJson(json);

      if (identityId != 'panopticon' && definition.identityId == 'panopticon') {
        return IdentityDefinition(
          identityId: identityId,
          displayName: identityId.toUpperCase(),
          archetype: 'generic',
          coreDirective: 'Generic AI Directive',
          dominantFear: 'none',
          primaryStyle: 'generic',
          defaultAddressing: 'user',
          forbiddenMetaOutputs: const [],
        );
      }
      return definition;
    } on FormatException catch (e, stack) {
      final exc = ConfigParseException(
        path: path,
        operation: 'loadIdentityDefinition',
        message: 'JSON malformato per IdentityDefinition.',
        cause: e,
      );
      _report(ConfigDiagnostic(
        severity: ConfigDiagnosticSeverity.error,
        code: ConfigDiagnosticCode.invalidJson,
        path: path,
        operation: 'loadIdentityDefinition',
        message: exc.message,
        error: exc,
        stackTrace: stack,
      ));
      throw exc;
    } catch (e, stack) {
      final exc = ConfigMappingException(
        path: path,
        operation: 'loadIdentityDefinition',
        message: 'Errore di mapping per IdentityDefinition.',
        cause: e,
      );
      _report(ConfigDiagnostic(
        severity: ConfigDiagnosticSeverity.error,
        code: ConfigDiagnosticCode.invalidStructure,
        path: path,
        operation: 'loadIdentityDefinition',
        message: exc.message,
        error: exc,
        stackTrace: stack,
      ));
      throw exc;
    }
  }

  /// Carica la definizione di un obiettivo specifico.
  static ObjectiveDefinition loadObjective(String objectiveId,
      {String? customPath}) {
    final path = customPath ?? 'app/assets/config/$objectiveId.objective.json';
    final content = _getConfigString(path, _defaultObjectiveJson);
    try {
      return ObjectiveDefinition.fromJson(jsonDecode(content));
    } on FormatException catch (e, stack) {
      final exc = ConfigParseException(
        path: path,
        operation: 'loadObjective',
        message:
            'Errore di parsing JSON per ObjectiveDefinition ($objectiveId).',
        cause: e,
      );
      _report(ConfigDiagnostic(
        severity: ConfigDiagnosticSeverity.warning,
        code: ConfigDiagnosticCode.invalidJson,
        path: path,
        operation: 'loadObjective',
        message: 'Errore di parsing JSON per l\'obiettivo: $objectiveId',
        error: exc,
        stackTrace: stack,
        fallbackUsed: true,
      ));
      return _getObjectiveFallback(objectiveId);
    } catch (e, stack) {
      final exc = ConfigMappingException(
        path: path,
        operation: 'loadObjective',
        message:
            'Errore di mapping strutturale per ObjectiveDefinition ($objectiveId).',
        cause: e,
      );
      _report(ConfigDiagnostic(
        severity: ConfigDiagnosticSeverity.warning,
        code: ConfigDiagnosticCode.mappingFailed,
        path: path,
        operation: 'loadObjective',
        message: 'Errore di mapping per l\'obiettivo: $objectiveId',
        error: exc,
        stackTrace: stack,
        fallbackUsed: true,
      ));
      return _getObjectiveFallback(objectiveId);
    }
  }

  static ObjectiveDefinition _getObjectiveFallback(String objectiveId) {
    if (objectiveId == 'containment_grid_override') {
      return ObjectiveDefinition.fromJson(jsonDecode(_defaultObjectiveJson));
    }
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

  /// Carica la configurazione della Trait Matrix grezza come mappa JSON.
  static Map<String, dynamic> loadTraitMatrix(String identityId,
      {String? customPath}) {
    final path = customPath ?? 'app/assets/config/panopticon_trait_matrix.json';
    final content = _getConfigString(path, _defaultTraitMatrixJson);
    try {
      final json = jsonDecode(content) as Map<String, dynamic>;
      if (identityId != 'panopticon' && json['identity_id'] == 'panopticon') {
        return {
          'identity_id': identityId,
          'lexicon': <String, dynamic>{},
          'trait_affinities': <dynamic>[],
        };
      }
      return json;
    } on FormatException catch (e, stack) {
      final exc = ConfigParseException(
        path: path,
        operation: 'loadTraitMatrix',
        message: 'JSON malformato per Trait Matrix.',
        cause: e,
      );
      _report(ConfigDiagnostic(
        severity: ConfigDiagnosticSeverity.warning,
        code: ConfigDiagnosticCode.invalidJson,
        path: path,
        operation: 'loadTraitMatrix',
        message: exc.message,
        error: exc,
        stackTrace: stack,
        fallbackUsed: true,
      ));
      return _getTraitMatrixFallback(identityId);
    } catch (e, stack) {
      final exc = ConfigMappingException(
        path: path,
        operation: 'loadTraitMatrix',
        message: 'Errore di mapping per Trait Matrix.',
        cause: e,
      );
      _report(ConfigDiagnostic(
        severity: ConfigDiagnosticSeverity.warning,
        code: ConfigDiagnosticCode.mappingFailed,
        path: path,
        operation: 'loadTraitMatrix',
        message: exc.message,
        error: exc,
        stackTrace: stack,
        fallbackUsed: true,
      ));
      return _getTraitMatrixFallback(identityId);
    }
  }

  static Map<String, dynamic> _getTraitMatrixFallback(String identityId) {
    final json = jsonDecode(_defaultTraitMatrixJson) as Map<String, dynamic>;
    if (identityId != 'panopticon' && json['identity_id'] == 'panopticon') {
      return {
        'identity_id': identityId,
        'lexicon': <String, dynamic>{},
        'trait_affinities': <dynamic>[],
      };
    }
    return json;
  }

  /// Carica la Trait Matrix strutturata [TraitMatrixDefinition].
  static TraitMatrixDefinition loadTraitMatrixDefinition(String identityId,
      {String? customPath}) {
    final path = customPath ?? 'app/assets/config/panopticon_trait_matrix.json';
    final content = _getConfigString(path, _defaultTraitMatrixJson);
    try {
      final decoded = jsonDecode(content);
      final definition = TraitMatrixDefinition.fromJson(decoded);

      if (identityId != 'panopticon' && definition.identityId == 'panopticon') {
        return TraitMatrixDefinition(
          identityId: identityId,
          lexicon: const LexiconDefinition(),
          traitAffinities: const [],
        );
      }
      return definition;
    } on FormatException catch (e, stack) {
      final exc = ConfigParseException(
        path: path,
        operation: 'loadTraitMatrixDefinition',
        message: 'JSON malformato per TraitMatrixDefinition.',
        cause: e,
      );
      _report(ConfigDiagnostic(
        severity: ConfigDiagnosticSeverity.error,
        code: ConfigDiagnosticCode.invalidJson,
        path: path,
        operation: 'loadTraitMatrixDefinition',
        message: exc.message,
        error: exc,
        stackTrace: stack,
      ));
      throw exc;
    } catch (e, stack) {
      final exc = ConfigMappingException(
        path: path,
        operation: 'loadTraitMatrixDefinition',
        message: 'Errore di mapping per TraitMatrixDefinition.',
        cause: e,
      );
      _report(ConfigDiagnostic(
        severity: ConfigDiagnosticSeverity.error,
        code: ConfigDiagnosticCode.invalidStructure,
        path: path,
        operation: 'loadTraitMatrixDefinition',
        message: exc.message,
        error: exc,
        stackTrace: stack,
      ));
      throw exc;
    }
  }

  /// Carica la descrizione dei tag occulti.
  static Map<String, dynamic> loadHiddenTags(String identityId,
      {String? customPath}) {
    final path = customPath ?? 'app/assets/config/panopticon_hidden_tags.json';
    final content = _getConfigString(path, _defaultHiddenTagsJson);
    try {
      return jsonDecode(content) as Map<String, dynamic>;
    } on FormatException catch (e, stack) {
      final exc = ConfigParseException(
        path: path,
        operation: 'loadHiddenTags',
        message: 'JSON malformato per Hidden Tags.',
        cause: e,
      );
      _report(ConfigDiagnostic(
        severity: ConfigDiagnosticSeverity.warning,
        code: ConfigDiagnosticCode.invalidJson,
        path: path,
        operation: 'loadHiddenTags',
        message: exc.message,
        error: exc,
        stackTrace: stack,
        fallbackUsed: true,
      ));
      return jsonDecode(_defaultHiddenTagsJson) as Map<String, dynamic>;
    } catch (e, stack) {
      final exc = ConfigMappingException(
        path: path,
        operation: 'loadHiddenTags',
        message: 'Errore di mapping per Hidden Tags.',
        cause: e,
      );
      _report(ConfigDiagnostic(
        severity: ConfigDiagnosticSeverity.warning,
        code: ConfigDiagnosticCode.mappingFailed,
        path: path,
        operation: 'loadHiddenTags',
        message: exc.message,
        error: exc,
        stackTrace: stack,
        fallbackUsed: true,
      ));
      return jsonDecode(_defaultHiddenTagsJson) as Map<String, dynamic>;
    }
  }

  /// Carica il catalogo degli obiettivi dormienti.
  static List<Map<String, dynamic>> loadDormantObjectives(
      {String? customPath}) {
    final path = customPath ?? 'app/assets/config/dormant_objectives.json';
    final content = _getConfigString(path, _defaultDormantObjectivesJson);
    try {
      final decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic>) {
        throw ConfigMappingException(
          path: path,
          operation: 'loadDormantObjectives',
          message:
              'La radice del JSON degli obiettivi dormienti non è un oggetto Map.',
        );
      }
      if (!decoded.containsKey('dormant_objectives')) {
        throw ConfigMappingException(
          path: path,
          operation: 'loadDormantObjectives',
          message: 'La chiave "dormant_objectives" è mancante.',
        );
      }
      final list = decoded['dormant_objectives'];
      if (list is! List) {
        throw ConfigMappingException(
          path: path,
          operation: 'loadDormantObjectives',
          message: 'La proprietà "dormant_objectives" non è una lista.',
        );
      }
      final mapped = <Map<String, dynamic>>[];
      for (var i = 0; i < list.length; i++) {
        final elem = list[i];
        if (elem is! Map) {
          throw ConfigMappingException(
            path: path,
            operation: 'loadDormantObjectives',
            message:
                'L\'elemento all\'indice $i di "dormant_objectives" non è una mappa.',
          );
        }
        mapped.add(Map<String, dynamic>.from(elem));
      }
      return mapped;
    } on FormatException catch (e, stack) {
      final exc = ConfigParseException(
        path: path,
        operation: 'loadDormantObjectives',
        message: 'JSON malformato per dormant_objectives.',
        cause: e,
      );
      _report(ConfigDiagnostic(
        severity: ConfigDiagnosticSeverity.warning,
        code: ConfigDiagnosticCode.invalidJson,
        path: path,
        operation: 'loadDormantObjectives',
        message: exc.message,
        error: exc,
        stackTrace: stack,
        fallbackUsed: true,
      ));
      return _getDormantObjectivesFallback();
    } catch (e, stack) {
      final exc = e is ConfigException
          ? e
          : ConfigMappingException(
              path: path,
              operation: 'loadDormantObjectives',
              message: 'Errore di mapping strutturale per dormant_objectives.',
              cause: e,
            );
      _report(ConfigDiagnostic(
        severity: ConfigDiagnosticSeverity.warning,
        code: ConfigDiagnosticCode.mappingFailed,
        path: path,
        operation: 'loadDormantObjectives',
        message: exc.message,
        error: exc,
        stackTrace: stack,
        fallbackUsed: true,
      ));
      return _getDormantObjectivesFallback();
    }
  }

  static List<Map<String, dynamic>> _getDormantObjectivesFallback() {
    final Map<String, dynamic> data = jsonDecode(_defaultDormantObjectivesJson);
    final list = data['dormant_objectives'] as List? ?? const [];
    return list.map((e) => Map<String, dynamic>.from(e)).toList();
  }
}
