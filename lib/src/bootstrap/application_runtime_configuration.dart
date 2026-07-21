import 'package:meta/meta.dart';
import 'application_runtime_mode.dart';

/// Policy di fallback in caso di errore di inizializzazione o connettività.
enum BootstrapFallbackPolicy {
  /// Nessun fallback automatico: l'errore solleva un'eccezione tipizzata.
  none,

  /// Fallback su motore offline deterministico (rule-based).
  ruleBased,
}

/// Configurazione immutabile e tipizzata per il bootstrap applicativo di A.U.R.A.
@immutable
class ApplicationRuntimeConfiguration {
  /// Modalità runtime selezionata.
  final ApplicationRuntimeMode runtimeMode;

  /// URI base del server di inferenza (opzionale).
  final Uri? baseUri;

  /// Chiave API per l'autenticazione con il server di inferenza (opzionale).
  final String? apiKey;

  /// Identificatore del modello server per il ruolo Attore (PANOPTICON).
  final String actorModelId;

  /// Identificatore del modello server per il ruolo Valutatore.
  final String evaluatorModelId;

  /// Timeout massimo per le chiamate di inferenza e gestione del ciclo di vita.
  final Duration timeout;

  /// Disabilita i controlli di integrità iniziali (utilizzabile per test/sviluppo).
  final bool skipHealthCheck;

  /// Specifica se condividere lo stesso modello server per entrambi i ruoli (Attore/Valutatore).
  final bool useSharedModel;

  /// Identificatore opzionale della sessione di bootstrap.
  final String? sessionId;

  /// Abilita i log diagnostici dettagliati del bootstrap.
  final bool diagnosticMode;

  /// Policy di fallback per la gestione dei fallimenti di avvio.
  final BootstrapFallbackPolicy fallbackPolicy;

  /// Costruisce un'istanza immutabile di [ApplicationRuntimeConfiguration].
  const ApplicationRuntimeConfiguration({
    this.runtimeMode = ApplicationRuntimeMode.legacyExternalOpenAi,
    this.baseUri,
    this.apiKey,
    this.actorModelId = 'qwen/qwen3.5-9b',
    this.evaluatorModelId = 'mistralai/ministral-3-3b',
    this.timeout = const Duration(seconds: 30),
    this.skipHealthCheck = false,
    this.useSharedModel = false,
    this.sessionId,
    this.diagnosticMode = false,
    this.fallbackPolicy = BootstrapFallbackPolicy.none,
  });

  /// Crea un'istanza di [ApplicationRuntimeConfiguration] a partire da una mappa di variabili d'ambiente.
  ///
  /// Supporta l'override delle configurazioni principali tramite:
  /// - `AURA_RUNTIME_MODE`
  /// - `AURA_INFERENCE_BASE_URL`
  /// - `AURA_ACTOR_MODEL_ID`
  /// - `AURA_EVALUATOR_MODEL_ID`
  /// - `AURA_INFERENCE_API_KEY`
  factory ApplicationRuntimeConfiguration.fromEnvironment(
    Map<String, String> env, {
    ApplicationRuntimeConfiguration defaults =
        const ApplicationRuntimeConfiguration(),
  }) {
    ApplicationRuntimeMode mode = defaults.runtimeMode;
    final envModeStr = env['AURA_RUNTIME_MODE']?.trim();
    if (envModeStr != null && envModeStr.isNotEmpty) {
      mode = switch (envModeStr.toLowerCase()) {
        'legacy' ||
        'legacyexternalopenai' ||
        'legacy_external_openai' =>
          ApplicationRuntimeMode.legacyExternalOpenAi,
        'external' ||
        'externalopenairuntime' ||
        'external_openai_runtime' =>
          ApplicationRuntimeMode.externalOpenAiRuntime,
        'rulebased' ||
        'rule_based' ||
        'rule-based' ||
        'offline' =>
          ApplicationRuntimeMode.ruleBased,
        _ => throw FormatException(
            'Modalità runtime non valida da ambiente: "$envModeStr". Modalità valide: legacy, external, ruleBased.',
          ),
      };
    }

    Uri? baseUri = defaults.baseUri;
    final envUriStr = env['AURA_INFERENCE_BASE_URL']?.trim();
    if (envUriStr != null && envUriStr.isNotEmpty) {
      try {
        baseUri = Uri.parse(envUriStr);
        if (!baseUri.hasScheme ||
            (baseUri.scheme != 'http' && baseUri.scheme != 'https')) {
          throw const FormatException(
              'L\'URI di inferenza deve includere uno schema valido (http/https).');
        }
      } catch (e) {
        if (e is FormatException) rethrow;
        throw FormatException(
            'URI base di inferenza non valida in AURA_INFERENCE_BASE_URL: "$envUriStr".');
      }
    }

    final apiKey = env['AURA_INFERENCE_API_KEY']?.trim() ?? defaults.apiKey;
    final actorModelId =
        env['AURA_ACTOR_MODEL_ID']?.trim() ?? defaults.actorModelId;
    final evaluatorModelId =
        env['AURA_EVALUATOR_MODEL_ID']?.trim() ?? defaults.evaluatorModelId;

    if (actorModelId.isEmpty) {
      throw const FormatException(
          'L\'ID del modello Attore non può essere vuoto.');
    }
    if (evaluatorModelId.isEmpty) {
      throw const FormatException(
          'L\'ID del modello Valutatore non può essere vuoto.');
    }

    return ApplicationRuntimeConfiguration(
      runtimeMode: mode,
      baseUri: baseUri,
      apiKey: apiKey,
      actorModelId: actorModelId,
      evaluatorModelId: evaluatorModelId,
      timeout: defaults.timeout,
      skipHealthCheck: defaults.skipHealthCheck,
      useSharedModel: defaults.useSharedModel,
      sessionId: defaults.sessionId,
      diagnosticMode: defaults.diagnosticMode,
      fallbackPolicy: defaults.fallbackPolicy,
    );
  }

  /// Restituisce una copia aggiornata di [ApplicationRuntimeConfiguration].
  ApplicationRuntimeConfiguration copyWith({
    ApplicationRuntimeMode? runtimeMode,
    Uri? baseUri,
    String? apiKey,
    String? actorModelId,
    String? evaluatorModelId,
    Duration? timeout,
    bool? skipHealthCheck,
    bool? useSharedModel,
    String? sessionId,
    bool? diagnosticMode,
    BootstrapFallbackPolicy? fallbackPolicy,
  }) {
    return ApplicationRuntimeConfiguration(
      runtimeMode: runtimeMode ?? this.runtimeMode,
      baseUri: baseUri ?? this.baseUri,
      apiKey: apiKey ?? this.apiKey,
      actorModelId: actorModelId ?? this.actorModelId,
      evaluatorModelId: evaluatorModelId ?? this.evaluatorModelId,
      timeout: timeout ?? this.timeout,
      skipHealthCheck: skipHealthCheck ?? this.skipHealthCheck,
      useSharedModel: useSharedModel ?? this.useSharedModel,
      sessionId: sessionId ?? this.sessionId,
      diagnosticMode: diagnosticMode ?? this.diagnosticMode,
      fallbackPolicy: fallbackPolicy ?? this.fallbackPolicy,
    );
  }
}
