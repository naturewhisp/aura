import 'package:meta/meta.dart';
import '../agent_runtime/runtime/adapters/managed_llama_server/managed_llama_server_configuration.dart';
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

  /// Configurazione specifica per il runtime gestito `llama-server` (opzionale).
  final ManagedLlamaServerConfiguration? managedLlamaConfig;

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
    this.managedLlamaConfig,
  });

  /// Crea un'istanza di [ApplicationRuntimeConfiguration] a partire da una mappa di variabili d'ambiente.
  ///
  /// Supporta l'override delle configurazioni principali tramite:
  /// - `AURA_RUNTIME_MODE`
  /// - `AURA_INFERENCE_BASE_URL`
  /// - `AURA_ACTOR_MODEL_ID`
  /// - `AURA_EVALUATOR_MODEL_ID`
  /// - `AURA_INFERENCE_API_KEY`
  /// - `AURA_LLAMA_SERVER_EXECUTABLE`
  /// - `AURA_LLAMA_MODEL_PATH`
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
        'managed' ||
        'managedllamaserver' ||
        'managed_llama_server' ||
        'managed-llama-server' =>
          ApplicationRuntimeMode.managedLlamaServer,
        'rulebased' ||
        'rule_based' ||
        'rule-based' ||
        'offline' =>
          ApplicationRuntimeMode.ruleBased,
        _ => throw FormatException(
            'Modalità runtime non valida da ambiente: "$envModeStr". Modalità valide: legacy, external, managed-llama-server, ruleBased.',
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

    ManagedLlamaServerConfiguration? managedConfig =
        defaults.managedLlamaConfig;
    final llamaExec = env['AURA_LLAMA_SERVER_EXECUTABLE']?.trim();
    final llamaModel = env['AURA_LLAMA_MODEL_PATH']?.trim();

    if (llamaExec != null ||
        llamaModel != null ||
        mode == ApplicationRuntimeMode.managedLlamaServer) {
      final host = env['AURA_LLAMA_HOST']?.trim() ?? '127.0.0.1';
      final portStr = env['AURA_LLAMA_PORT']?.trim();
      final port = portStr != null ? int.tryParse(portStr) : null;
      final ctxStr = env['AURA_LLAMA_CONTEXT_SIZE']?.trim();
      final ctx = ctxStr != null ? int.tryParse(ctxStr) : null;
      final gpuStr = env['AURA_LLAMA_GPU_LAYERS']?.trim();
      final gpu = gpuStr != null ? int.tryParse(gpuStr) : null;
      final threadsStr = env['AURA_LLAMA_THREADS']?.trim();
      final threads = threadsStr != null ? int.tryParse(threadsStr) : null;
      final batchStr = env['AURA_LLAMA_BATCH_SIZE']?.trim();
      final batch = batchStr != null ? int.tryParse(batchStr) : null;
      final parallelStr = env['AURA_LLAMA_PARALLEL']?.trim();
      final parallel = parallelStr != null ? int.tryParse(parallelStr) : null;
      final startupMsStr = env['AURA_LLAMA_STARTUP_TIMEOUT_MS']?.trim();
      final startupTimeout =
          startupMsStr != null && int.tryParse(startupMsStr) != null
              ? Duration(milliseconds: int.parse(startupMsStr))
              : const Duration(seconds: 30);
      final shutdownMsStr = env['AURA_LLAMA_SHUTDOWN_TIMEOUT_MS']?.trim();
      final shutdownTimeout =
          shutdownMsStr != null && int.tryParse(shutdownMsStr) != null
              ? Duration(milliseconds: int.parse(shutdownMsStr))
              : const Duration(seconds: 10);

      managedConfig = ManagedLlamaServerConfiguration(
        executablePath:
            llamaExec ?? defaults.managedLlamaConfig?.executablePath ?? '',
        modelPath: llamaModel ?? defaults.managedLlamaConfig?.modelPath ?? '',
        host: host,
        preferredPort: port ?? defaults.managedLlamaConfig?.preferredPort,
        contextSize: ctx ?? defaults.managedLlamaConfig?.contextSize,
        gpuLayers: gpu ?? defaults.managedLlamaConfig?.gpuLayers,
        threads: threads ?? defaults.managedLlamaConfig?.threads,
        batchSize: batch ?? defaults.managedLlamaConfig?.batchSize,
        parallelSlots: parallel ?? defaults.managedLlamaConfig?.parallelSlots,
        startupTimeout: startupTimeout,
        shutdownTimeout: shutdownTimeout,
        apiKey: apiKey ?? 'managed-llama-secret',
        diagnosticMode: defaults.diagnosticMode,
      );
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
      managedLlamaConfig: managedConfig,
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
    ManagedLlamaServerConfiguration? managedLlamaConfig,
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
      managedLlamaConfig: managedLlamaConfig ?? this.managedLlamaConfig,
    );
  }
}
