import 'dart:async';
import 'package:aura_core/aura_core.dart';
import '../agent_runtime/bridges/local_api_inference_bridge.dart';
import '../agent_runtime/bridges/runtime_inference_bridge.dart';
import '../agent_runtime/runtime/adapters/external_openai/external_openai_client.dart';
import '../agent_runtime/runtime/adapters/external_openai/external_openai_configuration.dart';
import '../agent_runtime/runtime/adapters/external_openai/external_openai_model_binding.dart';
import '../agent_runtime/runtime/adapters/external_openai/external_openai_runtime.dart';
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
            quantization: 'q4_0',
            architecture: 'shared',
            compatibility: ModelRuntimeCompatibility(compatible: true),
          ),
          logicalModelId: actorBinding.logicalModelId,
          roles: actorBinding.roles,
        );
        final sharedHandle = await runtime.loadModel(sharedLoadReq);
        actorPlan = RuntimeModelExecutionPlan(
          role: ModelRole.actor,
          logicalModelId: 'aura.actor.primary',
          handle: sharedHandle,
        );
        evalPlan = RuntimeModelExecutionPlan(
          role: ModelRole.evaluator,
          logicalModelId: 'aura.actor.primary',
          handle: sharedHandle,
        );
      } else {
        final actorLoadReq = ModelLoadRequest(
          requestId: ModelLoadRequestId('load-actor-$sessionId'),
          artifact: const ResolvedModelArtifact(
            modelVariantId: 'variant-actor',
            sha256: 'placeholder-sha',
            format: 'gguf',
            quantization: 'q4_0',
            architecture: 'qwen',
            compatibility: ModelRuntimeCompatibility(compatible: true),
          ),
          logicalModelId: actorBinding.logicalModelId,
          roles: actorBinding.roles,
        );
        final evalLoadReq = ModelLoadRequest(
          requestId: ModelLoadRequestId('load-eval-$sessionId'),
          artifact: const ResolvedModelArtifact(
            modelVariantId: 'variant-eval',
            sha256: 'placeholder-sha',
            format: 'gguf',
            quantization: 'q4_0',
            architecture: 'mistral',
            compatibility: ModelRuntimeCompatibility(compatible: true),
          ),
          logicalModelId: evalBinding.logicalModelId,
          roles: evalBinding.roles,
        );

        final actorHandle = await runtime.loadModel(actorLoadReq);
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
    } catch (e) {
      throw ApplicationBootstrapException(
        const ApplicationBootstrapFailure(
          code: ApplicationBootstrapFailureCode.modelLoadFailed,
          message: 'Caricamento dei modelli di inferenza fallito.',
        ),
        e,
      );
    }

    const routeResolver = LegacyInferenceRouteResolver();
    final bridge = RuntimeInferenceBridge(
      runtime: runtime,
      planResolver: (role) => role == ModelRole.actor ? actorPlan : evalPlan,
      routeResolver: routeResolver,
    );

    bool isHealthy = true;
    String statusMsg = 'ExternalOpenAiRuntime attivo ed interfacciato.';
    if (!config.skipHealthCheck) {
      try {
        final health = await runtime.health();
        isHealthy = health.responsive;
        if (!isHealthy) {
          statusMsg =
              'ExternalOpenAiRuntime non risponde ai controlli di integrità.';
        }
      } catch (e) {
        isHealthy = false;
        statusMsg = 'Health check di ExternalOpenAiRuntime fallito.';
      }

      if (!isHealthy &&
          config.fallbackPolicy == BootstrapFallbackPolicy.ruleBased) {
        final cleanupDiagnostics =
            await _cleanUpActiveResourcesBeforeFallback();
        return await _bootstrapRuleBased(config,
            fallbackDiagnostics: cleanupDiagnostics);
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
        'sessionId': sessionId,
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

  Future<ApplicationBootstrapResult> _bootstrapRuleBased(
    ApplicationRuntimeConfiguration config, {
    Map<String, dynamic>? fallbackDiagnostics,
  }) async {
    final sessionId =
        (config.sessionId != null && config.sessionId!.trim().isNotEmpty)
            ? config.sessionId!.trim()
            : 'bootstrap-session';

    final runtime = RuleBasedInferenceRuntime();
    _activeRuntime = runtime;
    await runtime.initialize(
      RuntimeInitializationRequest(
        instanceId: RuntimeInstanceId('instance-$sessionId'),
      ),
    );

    final actorLoadReq = ModelLoadRequest(
      requestId: ModelLoadRequestId('load-rule-actor-$sessionId'),
      artifact: const ResolvedModelArtifact(
        modelVariantId: 'variant-rule-actor',
        sha256: 'placeholder-sha',
        format: 'rule',
        quantization: 'none',
        architecture: 'rule',
        compatibility: ModelRuntimeCompatibility(compatible: true),
      ),
      logicalModelId: 'aura.actor.primary',
      roles: const {ModelRole.actor},
    );
    final evalLoadReq = ModelLoadRequest(
      requestId: ModelLoadRequestId('load-rule-eval-$sessionId'),
      artifact: const ResolvedModelArtifact(
        modelVariantId: 'variant-rule-eval',
        sha256: 'placeholder-sha',
        format: 'rule',
        quantization: 'none',
        architecture: 'rule',
        compatibility: ModelRuntimeCompatibility(compatible: true),
      ),
      logicalModelId: 'aura.evaluator.primary',
      roles: const {ModelRole.evaluator},
    );

    final actorHandle = await runtime.loadModel(actorLoadReq);
    final evalHandle = await runtime.loadModel(evalLoadReq);

    final actorPlan = RuntimeModelExecutionPlan(
      role: ModelRole.actor,
      logicalModelId: 'aura.actor.primary',
      handle: actorHandle,
    );
    final evalPlan = RuntimeModelExecutionPlan(
      role: ModelRole.evaluator,
      logicalModelId: 'aura.evaluator.primary',
      handle: evalHandle,
    );

    const routeResolver = LegacyInferenceRouteResolver();
    final bridge = RuntimeInferenceBridge(
      runtime: runtime,
      planResolver: (role) => role == ModelRole.actor ? actorPlan : evalPlan,
      routeResolver: routeResolver,
    );

    const controller = GameController();
    final status = ApplicationRuntimeStatus(
      runtimeMode: ApplicationRuntimeMode.ruleBased,
      isHealthy: true,
      statusDescription: 'Motore offline deterministico (rule-based) attivo.',
      diagnostics: {
        'sessionId': sessionId,
        if (fallbackDiagnostics != null) ...fallbackDiagnostics,
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

    final errors = <Object>[];

    if (_activeRuntime != null) {
      try {
        await _activeRuntime!.dispose();
      } catch (e) {
        errors.add(e);
      } finally {
        _activeRuntime = null;
      }
    }

    if (_activeClient != null) {
      try {
        await _activeClient!.close();
      } catch (e) {
        errors.add(e);
      } finally {
        _activeClient = null;
      }
    }

    if (errors.isNotEmpty) {
      throw ApplicationBootstrapException(
        const ApplicationBootstrapFailure(
          code: ApplicationBootstrapFailureCode.disposeFailed,
          message:
              'Errore durante la dismissione delle risorse del composition root.',
        ),
        errors.length == 1 ? errors.first : errors,
      );
    }
  }
}
