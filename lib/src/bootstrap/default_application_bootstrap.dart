import 'dart:async';
import 'package:aura_core/aura_core.dart';
import '../agent_runtime/bridges/local_api_inference_bridge.dart';
import '../agent_runtime/bridges/rule_based_evaluator_bridge.dart';
import '../agent_runtime/bridges/runtime_inference_bridge.dart';
import '../agent_runtime/runtime/adapters/external_openai/external_openai_client.dart';
import '../agent_runtime/runtime/adapters/external_openai/external_openai_configuration.dart';
import '../agent_runtime/runtime/adapters/external_openai/external_openai_model_binding.dart';
import '../agent_runtime/runtime/adapters/external_openai/external_openai_runtime.dart';
import '../agent_runtime/runtime/adapters/managed_llama_server/dart_io_process_launcher.dart';
import '../agent_runtime/runtime/adapters/managed_llama_server/managed_llama_server_runtime.dart';
import '../agent_runtime/runtime/adapters/rule_based_inference_runtime.dart';

/// Implementazione predefinita del composition root applicativo [ApplicationBootstrap].
class DefaultApplicationBootstrap implements ApplicationBootstrap {
  bool _bootstrapped = false;
  bool _disposed = false;

  InferenceRuntime? _activeRuntime;
  ExternalOpenAiClient? _activeClient;

  @override
  Future<ApplicationBootstrapResult> bootstrap(
    ApplicationBootstrapRequest request,
  ) async {
    if (_disposed) {
      throw const ApplicationBootstrapException(
        ApplicationBootstrapFailure(
          code: ApplicationBootstrapFailureCode.alreadyDisposed,
          message:
              'Impossibile eseguire il bootstrap: il composition root è già stato dismesso.',
        ),
      );
    }

    if (_bootstrapped) {
      throw const ApplicationBootstrapException(
        ApplicationBootstrapFailure(
          code: ApplicationBootstrapFailureCode.alreadyBootstrapped,
          message:
              'Il bootstrap è già stato eseguito per questa istanza. Creare una nuova istanza per un nuovo bootstrap.',
        ),
      );
    }

    final env = request.environmentOverride ?? {};
    ApplicationRuntimeConfiguration config = request.configuration;
    if (env.isNotEmpty) {
      try {
        config = ApplicationRuntimeConfiguration.fromEnvironment(
          env,
          defaults: config,
        );
      } on FormatException catch (e) {
        throw ApplicationBootstrapException(
          const ApplicationBootstrapFailure(
            code: ApplicationBootstrapFailureCode.incompleteConfiguration,
            message: 'Configurazione di runtime non valida o incompleta.',
          ),
          e,
        );
      }
    }

    try {
      final result = await _executeBootstrapPath(request, config);
      _bootstrapped = true;
      return result;
    } catch (e) {
      await dispose();
      if (e is ApplicationBootstrapException) {
        rethrow;
      }
      throw ApplicationBootstrapException(
        const ApplicationBootstrapFailure(
          code: ApplicationBootstrapFailureCode.runtimeInitializationFailed,
          message:
              'Errore durante l\'inizializzazione del bootstrap applicativo.',
        ),
        e,
      );
    }
  }

  Future<ApplicationBootstrapResult> _executeBootstrapPath(
    ApplicationBootstrapRequest request,
    ApplicationRuntimeConfiguration config,
  ) async {
    switch (config.runtimeMode) {
      case ApplicationRuntimeMode.legacyExternalOpenAi:
        return await _bootstrapLegacy(config);
      case ApplicationRuntimeMode.externalOpenAiRuntime:
        return await _bootstrapExternalOpenAi(request, config);
      case ApplicationRuntimeMode.managedLlamaServer:
        return await _bootstrapManagedLlamaServer(request, config);
      case ApplicationRuntimeMode.ruleBased:
        return await _bootstrapRuleBased(config);
    }
  }

  Future<Map<String, dynamic>> _cleanUpActiveResourcesBeforeFallback() async {
    bool runtimeSuccess = true;
    bool clientSuccess = true;
    int failureCount = 0;

    if (_activeRuntime != null) {
      try {
        await _activeRuntime!.dispose();
      } catch (_) {
        runtimeSuccess = false;
        failureCount++;
      } finally {
        _activeRuntime = null;
      }
    }

    if (_activeClient != null) {
      try {
        await _activeClient!.close();
      } catch (_) {
        clientSuccess = false;
        failureCount++;
      } finally {
        _activeClient = null;
      }
    }

    return {
      'fallbackCleanupPerformed': true,
      'runtimeDisposeSucceeded': runtimeSuccess,
      'clientCloseSucceeded': clientSuccess,
      'fallbackCleanupFailureCount': failureCount,
    };
  }

  Future<ApplicationBootstrapResult> _bootstrapLegacy(
    ApplicationRuntimeConfiguration config,
  ) async {
    final baseUri = config.baseUri ?? Uri.parse('http://127.0.0.1:1234');
    final bridge = LocalApiInferenceBridge(baseUrl: baseUri.toString());

    bool isHealthy = true;
    String statusMsg =
        'Legacy LocalApiInferenceBridge interfacciato su $baseUri.';

    if (!config.skipHealthCheck) {
      try {
        final models = await bridge.discoverModels();
        if (models.isEmpty) {
          isHealthy = false;
          statusMsg =
              'Server LM Studio rilevato ma nessun modello attivo caricato.';
        }
      } catch (e) {
        isHealthy = false;
        statusMsg = 'Server LM Studio non raggiungibile su $baseUri.';
      }

      if (!isHealthy &&
          config.fallbackPolicy == BootstrapFallbackPolicy.ruleBased) {
        return await _bootstrapRuleBased(config);
      }
    }

    const controller = GameController();
    final status = ApplicationRuntimeStatus(
      runtimeMode: ApplicationRuntimeMode.legacyExternalOpenAi,
      isHealthy: isHealthy,
      statusDescription: statusMsg,
      diagnostics: {
        'baseUrl': baseUri.toString(),
        'skipHealthCheck': config.skipHealthCheck,
        if (config.sessionId != null) 'sessionId': config.sessionId,
      },
    );

    return ApplicationBootstrapResult(
      controller: controller,
      activeBridge: bridge,
      runtimeMode: ApplicationRuntimeMode.legacyExternalOpenAi,
      status: status,
      onDispose: dispose,
    );
  }

  Future<ApplicationBootstrapResult> _bootstrapExternalOpenAi(
    ApplicationBootstrapRequest request,
    ApplicationRuntimeConfiguration config,
  ) async {
    final sessionId =
        (config.sessionId != null && config.sessionId!.trim().isNotEmpty)
            ? config.sessionId!.trim()
            : 'bootstrap-session';

    final baseUri = config.baseUri ?? Uri.parse('http://127.0.0.1:1234');
    if (!baseUri.hasScheme ||
        (baseUri.scheme != 'http' && baseUri.scheme != 'https')) {
      throw const ApplicationBootstrapException(
        ApplicationBootstrapFailure(
          code: ApplicationBootstrapFailureCode.invalidUri,
          message:
              'URI base non valido per ExternalOpenAiRuntime. Occorre uno schema http o https.',
        ),
      );
    }

    if (config.actorModelId.trim().isEmpty) {
      throw const ApplicationBootstrapException(
        ApplicationBootstrapFailure(
          code: ApplicationBootstrapFailureCode.missingActorModelId,
          message: 'L\'ID del modello Attore non può essere vuoto.',
        ),
      );
    }

    if (config.evaluatorModelId.trim().isEmpty) {
      throw const ApplicationBootstrapException(
        ApplicationBootstrapFailure(
          code: ApplicationBootstrapFailureCode.missingEvaluatorModelId,
          message: 'L\'ID del modello Valutatore non può essere vuoto.',
        ),
      );
    }

    final externalConfig = ExternalOpenAiConfiguration(
      baseUri: baseUri,
      apiKey: config.apiKey,
      transportTimeout: config.timeout,
      supportsMultipleLoadedModels: !config.useSharedModel,
      maxLoadedModels: config.useSharedModel ? 1 : 2,
    );

    final client = request.customHttpClient ??
        HttpExternalOpenAiClient(configuration: externalConfig);
    _activeClient = client;

    final ExternalOpenAiModelBinding actorBinding;
    final ExternalOpenAiModelBinding evalBinding;

    if (config.useSharedModel) {
      actorBinding = ExternalOpenAiModelBinding(
        logicalModelId: 'aura.actor.primary',
        serverModelId: config.actorModelId,
        roles: const {ModelRole.actor, ModelRole.evaluator},
      );
      evalBinding = ExternalOpenAiModelBinding(
        logicalModelId: 'aura.evaluator.primary',
        serverModelId: config.actorModelId,
        roles: const {ModelRole.actor, ModelRole.evaluator},
      );
    } else {
      actorBinding = ExternalOpenAiModelBinding(
        logicalModelId: 'aura.actor.primary',
        serverModelId: config.actorModelId,
        roles: const {ModelRole.actor},
      );
      evalBinding = ExternalOpenAiModelBinding(
        logicalModelId: 'aura.evaluator.primary',
        serverModelId: config.evaluatorModelId,
        roles: const {ModelRole.evaluator},
      );
    }

    final runtime = request.customRuntime ??
        ExternalOpenAiRuntime(
          configuration: externalConfig,
          client: client,
          bindings: [actorBinding, evalBinding],
        );
    _activeRuntime = runtime;

    try {
      await runtime.initialize(
        RuntimeInitializationRequest(
          instanceId: RuntimeInstanceId('instance-$sessionId'),
          adapterOptions: const {'skipHealthCheck': 'true'},
        ),
      );
    } on RuntimeException catch (e) {
      throw ApplicationBootstrapException(
        const ApplicationBootstrapFailure(
          code: ApplicationBootstrapFailureCode.runtimeInitializationFailed,
          message: 'Inizializzazione di ExternalOpenAiRuntime fallita.',
        ),
        e,
      );
    } catch (e) {
      throw ApplicationBootstrapException(
        const ApplicationBootstrapFailure(
          code: ApplicationBootstrapFailureCode.runtimeInitializationFailed,
          message: 'Inizializzazione di ExternalOpenAiRuntime fallita.',
        ),
        e,
      );
    }

    RuntimeModelExecutionPlan actorPlan;
    RuntimeModelExecutionPlan evalPlan;

    try {
      if (config.useSharedModel) {
        final sharedLoadReq = ModelLoadRequest(
          requestId: ModelLoadRequestId('load-shared-$sessionId'),
          artifact: const ResolvedModelArtifact(
            modelVariantId: 'variant-shared',
            sha256: 'placeholder-sha',
            format: 'gguf',
            quantization: 'q4_k_m',
            architecture: 'llama',
            compatibility: ModelRuntimeCompatibility(compatible: true),
            localArtifactUri: null,
          ),
          logicalModelId: 'aura.actor.primary',
          roles: const {ModelRole.actor, ModelRole.evaluator},
        );
        final sharedHandle = await runtime.loadModel(sharedLoadReq);

        actorPlan = RuntimeModelExecutionPlan(
          role: ModelRole.actor,
          logicalModelId: 'aura.actor.primary',
          handle: sharedHandle,
        );

        evalPlan = RuntimeModelExecutionPlan(
          role: ModelRole.evaluator,
          logicalModelId: 'aura.evaluator.primary',
          handle: sharedHandle,
        );
      } else {
        final actorLoadReq = ModelLoadRequest(
          requestId: ModelLoadRequestId('load-actor-$sessionId'),
          artifact: const ResolvedModelArtifact(
            modelVariantId: 'variant-actor',
            sha256: 'placeholder-sha',
            format: 'gguf',
            quantization: 'q4_k_m',
            architecture: 'llama',
            compatibility: ModelRuntimeCompatibility(compatible: true),
            localArtifactUri: null,
          ),
          logicalModelId: 'aura.actor.primary',
          roles: const {ModelRole.actor},
        );
        final actorHandle = await runtime.loadModel(actorLoadReq);

        final evalLoadReq = ModelLoadRequest(
          requestId: ModelLoadRequestId('load-eval-$sessionId'),
          artifact: const ResolvedModelArtifact(
            modelVariantId: 'variant-eval',
            sha256: 'placeholder-sha',
            format: 'gguf',
            quantization: 'q4_k_m',
            architecture: 'llama',
            compatibility: ModelRuntimeCompatibility(compatible: true),
            localArtifactUri: null,
          ),
          logicalModelId: 'aura.evaluator.primary',
          roles: const {ModelRole.evaluator},
        );
        final evalHandle = await runtime.loadModel(evalLoadReq);

        actorPlan = RuntimeModelExecutionPlan(
          role: ModelRole.actor,
          logicalModelId: 'aura.actor.primary',
          handle: actorHandle,
        );

        evalPlan = RuntimeModelExecutionPlan(
          role: ModelRole.evaluator,
          logicalModelId: 'aura.evaluator.primary',
          handle: evalHandle,
        );
      }
    } on RuntimeException catch (e) {
      throw ApplicationBootstrapException(
        const ApplicationBootstrapFailure(
          code: ApplicationBootstrapFailureCode.modelLoadFailed,
          message: 'Caricamento dei modelli per ExternalOpenAiRuntime fallito.',
        ),
        e,
      );
    } catch (e) {
      throw ApplicationBootstrapException(
        const ApplicationBootstrapFailure(
          code: ApplicationBootstrapFailureCode.modelLoadFailed,
          message: 'Caricamento dei modelli per ExternalOpenAiRuntime fallito.',
        ),
        e,
      );
    }

    final bridge = RuntimeInferenceBridge(
      runtime: runtime,
      planResolver: (role) => role == ModelRole.actor ? actorPlan : evalPlan,
    );

    bool isHealthy = true;
    String statusMsg =
        'ExternalOpenAiRuntime attivo ed interfacciato su $baseUri.';

    if (!config.skipHealthCheck) {
      try {
        final health = await runtime.health();
        if (!health.responsive) {
          isHealthy = false;
          statusMsg = 'Health check di ExternalOpenAiRuntime fallito.';
        }
      } catch (e) {
        isHealthy = false;
        statusMsg =
            'Impossibile verificare l\'health di ExternalOpenAiRuntime.';
      }

      if (!isHealthy &&
          config.fallbackPolicy == BootstrapFallbackPolicy.ruleBased) {
        final cleanupDiagnostics =
            await _cleanUpActiveResourcesBeforeFallback();
        final ruleBasedResult = await _bootstrapRuleBased(config);
        return ApplicationBootstrapResult(
          controller: ruleBasedResult.controller,
          activeBridge: ruleBasedResult.activeBridge,
          runtimeMode: ruleBasedResult.runtimeMode,
          status: ApplicationRuntimeStatus(
            runtimeMode: ApplicationRuntimeMode.ruleBased,
            isHealthy: ruleBasedResult.status.isHealthy,
            statusDescription:
                'Fallback automatico su RuleBasedInferenceRuntime eseguito a causa del fallimento health check di ExternalOpenAiRuntime.',
            diagnostics: {
              ...ruleBasedResult.status.diagnostics,
              ...cleanupDiagnostics,
              'originalRuntimeMode':
                  ApplicationRuntimeMode.externalOpenAiRuntime.name,
              'fallbackReason': statusMsg,
              if (config.sessionId != null) 'sessionId': config.sessionId,
            },
          ),
          onDispose: dispose,
        );
      }
    }

    const controller = GameController();
    final status = ApplicationRuntimeStatus(
      runtimeMode: ApplicationRuntimeMode.externalOpenAiRuntime,
      isHealthy: isHealthy,
      statusDescription: statusMsg,
      diagnostics: {
        'baseUrl': baseUri.toString(),
        'useSharedModel': config.useSharedModel,
        'actorModelId': config.actorModelId,
        'evaluatorModelId': config.evaluatorModelId,
        'skipHealthCheck': config.skipHealthCheck,
        if (config.sessionId != null) 'sessionId': config.sessionId,
      },
    );

    return ApplicationBootstrapResult(
      controller: controller,
      activeBridge: bridge,
      runtimeMode: ApplicationRuntimeMode.externalOpenAiRuntime,
      status: status,
      onDispose: dispose,
    );
  }

  Future<ApplicationBootstrapResult> _bootstrapManagedLlamaServer(
    ApplicationBootstrapRequest request,
    ApplicationRuntimeConfiguration config,
  ) async {
    final sessionId =
        (config.sessionId != null && config.sessionId!.trim().isNotEmpty)
            ? config.sessionId!.trim()
            : 'bootstrap-session';

    final managedConfig = config.managedLlamaConfig;
    if (managedConfig == null) {
      throw const ApplicationBootstrapException(
        ApplicationBootstrapFailure(
          code: ApplicationBootstrapFailureCode.incompleteConfiguration,
          message:
              'Configurazione managedLlamaConfig mancante per la modalità managedLlamaServer.',
        ),
      );
    }

    try {
      managedConfig.validate();
    } on RuntimeException catch (e) {
      if (config.fallbackPolicy == BootstrapFallbackPolicy.ruleBased) {
        final cleanupDiag = await _cleanUpActiveResourcesBeforeFallback();
        final result = await _bootstrapRuleBased(config);
        return ApplicationBootstrapResult(
          controller: result.controller,
          activeBridge: result.activeBridge,
          runtimeMode: result.runtimeMode,
          status: ApplicationRuntimeStatus(
            runtimeMode: ApplicationRuntimeMode.ruleBased,
            isHealthy: result.status.isHealthy,
            statusDescription:
                'Fallback rule-based eseguito a causa di configurazione managedLlamaServer non valida.',
            diagnostics: {
              ...result.status.diagnostics,
              ...cleanupDiag,
              'fallbackReason': e.failure.message,
              if (config.sessionId != null) 'sessionId': config.sessionId,
            },
          ),
          onDispose: dispose,
        );
      }
      throw ApplicationBootstrapException(
        ApplicationBootstrapFailure(
          code: ApplicationBootstrapFailureCode.incompleteConfiguration,
          message: e.failure.message,
        ),
        e,
      );
    }

    final processLauncher =
        request.customProcessLauncher ?? const DartIoProcessLauncher();
    final portAllocator =
        request.customPortAllocator ?? const LoopbackPortAllocator();
    final healthProbe =
        request.customHealthProbe ?? HttpLlamaServerHealthProbe();

    final supervisor = LlamaServerProcessSupervisor(
      configuration: managedConfig,
      processLauncher: processLauncher,
      portAllocator: portAllocator,
      healthProbe: healthProbe,
    );

    final runtime = request.customRuntime ??
        ManagedLlamaServerRuntime(
          configuration: managedConfig,
          supervisor: supervisor,
          delegateFactory: request.customDelegateFactory != null
              ? (clientConfig, bindings) =>
                  request.customDelegateFactory!(clientConfig)
              : null,
        );

    _activeRuntime = runtime;

    try {
      await runtime.initialize(
        RuntimeInitializationRequest(
          instanceId: RuntimeInstanceId('instance-$sessionId'),
        ),
      );
    } catch (e) {
      if (config.fallbackPolicy == BootstrapFallbackPolicy.ruleBased) {
        final cleanupDiag = await _cleanUpActiveResourcesBeforeFallback();
        final result = await _bootstrapRuleBased(config);
        return ApplicationBootstrapResult(
          controller: result.controller,
          activeBridge: result.activeBridge,
          runtimeMode: result.runtimeMode,
          status: ApplicationRuntimeStatus(
            runtimeMode: ApplicationRuntimeMode.ruleBased,
            isHealthy: result.status.isHealthy,
            statusDescription:
                'Fallback rule-based eseguito a causa del fallimento di avvio di ManagedLlamaServerRuntime.',
            diagnostics: {
              ...result.status.diagnostics,
              ...cleanupDiag,
              'fallbackReason': 'Avvio managed-llama-server fallito.',
              if (config.sessionId != null) 'sessionId': config.sessionId,
            },
          ),
          onDispose: dispose,
        );
      }
      throw ApplicationBootstrapException(
        const ApplicationBootstrapFailure(
          code: ApplicationBootstrapFailureCode.runtimeInitializationFailed,
          message: 'Inizializzazione di ManagedLlamaServerRuntime fallita.',
        ),
        e,
      );
    }

    final loadReq = ModelLoadRequest(
      requestId: ModelLoadRequestId('load-managed-$sessionId'),
      artifact: ResolvedModelArtifact(
        modelVariantId: managedConfig.modelAlias,
        sha256: 'placeholder-sha',
        format: 'gguf',
        quantization: 'q4_k_m',
        architecture: 'llama',
        compatibility: const ModelRuntimeCompatibility(compatible: true),
        localArtifactUri: Uri.file(managedConfig.modelPath),
      ),
      logicalModelId: 'aura.actor.primary',
      roles: const {ModelRole.actor, ModelRole.evaluator},
    );

    final handle = await runtime.loadModel(loadReq);

    final bridge = RuntimeInferenceBridge.fromHandleResolver(
      runtime: runtime,
      handleResolver: (_) => handle,
    );

    const controller = GameController();
    final status = ApplicationRuntimeStatus(
      runtimeMode: ApplicationRuntimeMode.managedLlamaServer,
      isHealthy: true,
      statusDescription:
          'ManagedLlamaServerRuntime attivo e pronto su porta ${supervisor.allocatedPort}.',
      diagnostics: {
        'managed': true,
        'allocatedPort': supervisor.allocatedPort,
        'modelAlias': managedConfig.modelAlias,
        'pid': supervisor.pid,
        if (config.sessionId != null) 'sessionId': config.sessionId,
      },
    );

    return ApplicationBootstrapResult(
      controller: controller,
      activeBridge: bridge,
      runtimeMode: ApplicationRuntimeMode.managedLlamaServer,
      status: status,
      onDispose: dispose,
    );
  }

  Future<ApplicationBootstrapResult> _bootstrapRuleBased(
    ApplicationRuntimeConfiguration config,
  ) async {
    const controller = GameController();
    const bridge = RuleBasedEvaluatorBridge();
    _activeRuntime = RuleBasedInferenceRuntime();

    final status = ApplicationRuntimeStatus(
      runtimeMode: ApplicationRuntimeMode.ruleBased,
      isHealthy: true,
      statusDescription:
          'Motore offline deterministico attivo (nessuna chiamata LLM esterna).',
      diagnostics: {
        'offlineMode': true,
        if (config.sessionId != null) 'sessionId': config.sessionId,
      },
    );

    return ApplicationBootstrapResult(
      controller: controller,
      activeBridge: bridge,
      runtimeMode: ApplicationRuntimeMode.ruleBased,
      status: status,
      onDispose: dispose,
    );
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    bool runtimeSuccess = true;
    bool clientSuccess = true;
    Object? firstError;

    if (_activeRuntime != null) {
      try {
        await _activeRuntime!.dispose();
      } catch (e) {
        runtimeSuccess = false;
        firstError ??= e;
      } finally {
        _activeRuntime = null;
      }
    }

    if (_activeClient != null) {
      try {
        await _activeClient!.close();
      } catch (e) {
        clientSuccess = false;
        firstError ??= e;
      } finally {
        _activeClient = null;
      }
    }

    _bootstrapped = false;

    if (!runtimeSuccess || !clientSuccess) {
      throw ApplicationBootstrapException(
        const ApplicationBootstrapFailure(
          code: ApplicationBootstrapFailureCode.disposeFailed,
          message:
              'Fallimento durante la dismissione delle risorse attive del composition root.',
        ),
        firstError,
      );
    }
  }
}
