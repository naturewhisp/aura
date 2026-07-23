import 'dart:convert';
import 'package:aura_core/aura_core.dart';

const Object _unset = Object();

/// Impostazioni persistenti dell'applicazione A.U.R.A.
///
/// Modello immutabile che rappresenta la configurazione salvata
/// nel file `settings.json`. Tutte le chiavi JSON sono invariate
/// rispetto al formato precedente per garantire la retrocompatibilità.
final class AppSettings {
  /// ID del modello utilizzato per il ruolo di Valutatore.
  final String evaluatorModelId;

  /// ID del modello utilizzato per il ruolo di Attore (PANOPTICON).
  final String actorModelId;

  /// Specifica se abilitare la Chain-of-Thought per l'Attore.
  final bool reasoningEnabled;

  /// Specifica se forzare un ragionamento CoT sintetico e ridotto.
  final bool conciseReasoning;

  /// Specifica se abilitare lo shader per simulare l'effetto schermo CRT.
  final bool shaderEnabled;

  /// Specifica se abilitare l'audio e gli effetti sonori.
  final bool audioEnabled;

  /// Livello di difficoltà predefinito per le nuove sessioni.
  final String defaultDifficulty;

  /// Indica se l'utente ha impostato una configurazione personalizzata dei modelli.
  final bool userCustomizedModels;

  /// Il nome visualizzato personalizzato dell'utente (opzionale, null per default "Tu").
  final String? userDisplayName;

  /// Crea un'istanza di [AppSettings] con tutti i campi obbligatori.
  const AppSettings({
    required this.evaluatorModelId,
    required this.actorModelId,
    required this.reasoningEnabled,
    required this.conciseReasoning,
    required this.shaderEnabled,
    required this.audioEnabled,
    required this.defaultDifficulty,
    required this.userCustomizedModels,
    this.userDisplayName,
  });

  /// Restituisce le impostazioni predefinite di fabbrica.
  factory AppSettings.defaults() {
    return const AppSettings(
      evaluatorModelId: 'mistralai/ministral-3-3b',
      actorModelId: 'qwen/qwen3.5-9b',
      reasoningEnabled: false,
      conciseReasoning: false,
      shaderEnabled: true,
      audioEnabled: true,
      defaultDifficulty: 'standard',
      userCustomizedModels: false,
      userDisplayName: null,
    );
  }

  /// Deserializza le impostazioni da una mappa JSON.
  ///
  /// Applica fallback ai valori predefiniti per i campi mancanti.
  /// Supporta la chiave legacy `difficulty_level` come fallback
  /// quando `default_difficulty` è assente.
  ///
  /// Lancia [FormatException] se un campo è presente ma con tipo errato.
  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      evaluatorModelId: _readString(
        json,
        'evaluator_model_id',
        AppSettings.defaults().evaluatorModelId,
      ),
      actorModelId: _readString(
        json,
        'actor_model_id',
        AppSettings.defaults().actorModelId,
      ),
      reasoningEnabled: _readBool(
        json,
        'reasoning_enabled',
        AppSettings.defaults().reasoningEnabled,
      ),
      conciseReasoning: _readBool(
        json,
        'concise_reasoning',
        AppSettings.defaults().conciseReasoning,
      ),
      shaderEnabled: _readBool(
        json,
        'shader_enabled',
        AppSettings.defaults().shaderEnabled,
      ),
      audioEnabled: _readBool(
        json,
        'audio_enabled',
        AppSettings.defaults().audioEnabled,
      ),
      defaultDifficulty: _readDefaultDifficulty(json),
      userCustomizedModels: _readBool(
        json,
        'user_customized_models',
        AppSettings.defaults().userCustomizedModels,
      ),
      userDisplayName: _readOptionalString(json, 'user_display_name'),
    );
  }

  /// Serializza le impostazioni in una mappa JSON.
  ///
  /// Scrive sia `default_difficulty` che `difficulty_level` per
  /// retrocompatibilità con versioni precedenti del formato.
  Map<String, dynamic> toJson() {
    final normName = UserProfile.normalize(userDisplayName);
    return {
      'evaluator_model_id': evaluatorModelId,
      'actor_model_id': actorModelId,
      'reasoning_enabled': reasoningEnabled,
      'concise_reasoning': conciseReasoning,
      'shader_enabled': shaderEnabled,
      'audio_enabled': audioEnabled,
      'difficulty_level': defaultDifficulty, // per retrocompatibilità
      'default_difficulty': defaultDifficulty,
      'user_customized_models': userCustomizedModels,
      if (normName != null) 'user_display_name': normName,
    };
  }

  /// Restituisce una copia delle impostazioni con i campi specificati aggiornati.
  ///
  /// Utilizza un sentinel interno per consentire il ripristino esplicito
  /// a `null` del campo [userDisplayName] quando passato come `userDisplayName: null`.
  AppSettings copyWith({
    String? evaluatorModelId,
    String? actorModelId,
    bool? reasoningEnabled,
    bool? conciseReasoning,
    bool? shaderEnabled,
    bool? audioEnabled,
    String? defaultDifficulty,
    bool? userCustomizedModels,
    Object? userDisplayName = _unset,
  }) {
    final String? nextUserDisplayName;
    if (identical(userDisplayName, _unset)) {
      nextUserDisplayName = this.userDisplayName;
    } else if (userDisplayName == null) {
      nextUserDisplayName = null;
    } else if (userDisplayName is String) {
      nextUserDisplayName = UserProfile.normalize(userDisplayName);
    } else {
      throw ArgumentError('userDisplayName deve essere String? o null.');
    }

    return AppSettings(
      evaluatorModelId: evaluatorModelId ?? this.evaluatorModelId,
      actorModelId: actorModelId ?? this.actorModelId,
      reasoningEnabled: reasoningEnabled ?? this.reasoningEnabled,
      conciseReasoning: conciseReasoning ?? this.conciseReasoning,
      shaderEnabled: shaderEnabled ?? this.shaderEnabled,
      audioEnabled: audioEnabled ?? this.audioEnabled,
      defaultDifficulty: defaultDifficulty ?? this.defaultDifficulty,
      userCustomizedModels: userCustomizedModels ?? this.userCustomizedModels,
      userDisplayName: nextUserDisplayName,
    );
  }

  /// Restituisce una copia delle impostazioni ripristinando il nome utente di default ("Tu").
  AppSettings clearUserDisplayName() {
    return copyWith(userDisplayName: null);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AppSettings &&
        other.evaluatorModelId == evaluatorModelId &&
        other.actorModelId == actorModelId &&
        other.reasoningEnabled == reasoningEnabled &&
        other.conciseReasoning == conciseReasoning &&
        other.shaderEnabled == shaderEnabled &&
        other.audioEnabled == audioEnabled &&
        other.defaultDifficulty == defaultDifficulty &&
        other.userCustomizedModels == userCustomizedModels &&
        other.userDisplayName == userDisplayName;
  }

  @override
  int get hashCode => Object.hash(
        evaluatorModelId,
        actorModelId,
        reasoningEnabled,
        conciseReasoning,
        shaderEnabled,
        audioEnabled,
        defaultDifficulty,
        userCustomizedModels,
        userDisplayName,
      );

  @override
  String toString() => 'AppSettings(${jsonEncode(toJson())})';

  // ---------------------------------------------------------------------------
  // Helper privati di lettura e validazione
  // ---------------------------------------------------------------------------

  static String? _readOptionalString(Map<String, dynamic> json, String key) {
    final raw = json[key];
    if (raw == null) return null;
    if (raw is String) return UserProfile.normalize(raw);
    throw FormatException(
      "Il campo '$key' deve essere una stringa, trovato: ${raw.runtimeType}",
    );
  }

  static String _readString(
    Map<String, dynamic> json,
    String key,
    String defaultValue,
  ) {
    final raw = json[key];
    if (raw == null) return defaultValue;
    if (raw is String) return raw;
    throw FormatException(
      "Il campo '$key' deve essere una stringa, trovato: ${raw.runtimeType}",
    );
  }

  static bool _readBool(
    Map<String, dynamic> json,
    String key,
    bool defaultValue,
  ) {
    final raw = json[key];
    if (raw == null) return defaultValue;
    if (raw is bool) return raw;
    throw FormatException(
      "Il campo '$key' deve essere un booleano, trovato: ${raw.runtimeType}",
    );
  }

  /// Legge `default_difficulty`, con fallback legacy a `difficulty_level`.
  static String _readDefaultDifficulty(Map<String, dynamic> json) {
    final rawNew = json['default_difficulty'];
    if (rawNew != null) {
      if (rawNew is String) return rawNew;
      throw FormatException(
        "Il campo 'default_difficulty' deve essere una stringa, trovato: ${rawNew.runtimeType}",
      );
    }

    // Fallback alla chiave legacy
    final rawLegacy = json['difficulty_level'];
    if (rawLegacy != null) {
      if (rawLegacy is String) return rawLegacy;
      throw FormatException(
        "Il campo 'difficulty_level' deve essere una stringa, trovato: ${rawLegacy.runtimeType}",
      );
    }

    return AppSettings.defaults().defaultDifficulty;
  }
}
