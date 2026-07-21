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
          ApplicationBootstrapFailure(
            code: ApplicationBootstrapFailureCode.incompleteConfiguration,
            message: e.message,
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
        ApplicationBootstrapFailure(
          code: ApplicationBootstrapFailureCode.runtimeInitializationFailed,
          message:
              'Errore imprevisto durante l\'inizializzazione del bootstrap: $e',
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
        return await _bootstrapRuleBased();
    }
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
        return await _bootstrapRuleBased();
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
    final baseUri = config.baseUri ?? Uri.parse('http://127.0.0.1:1234');
    if (!baseUri.hasScheme ||
        (baseUri.scheme != 'http' && baseUri.scheme != 'https')) {
      throw ApplicationBootstrapException(
        ApplicationBootstrapFailure(
          code: ApplicationBootstrapFailureCode.invalidUri,
          message:
              'URI base non valida per ExternalOpenAiRuntime: "$baseUri". Occorre uno schema http o https.',
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
    );

    final client = request.customHttpClient ??
        HttpExternalOpenAiClient(configuration: externalConfig);
    _activeClient = client;

    final actorBinding = ExternalOpenAiModelBinding(
      logicalModelId: 'aura.actor.primary',
      serverModelId: config.actorModelId,
      roles: const {ModelRole.actor},
    );
    final evalBinding = ExternalOpenAiModelBinding(
      logicalModelId: 'aura.evaluator.primary',
      serverModelId: config.evaluatorModelId,
      roles: const {ModelRole.evaluator},
    );

    final runtime = request.customRuntime ??
        ExternalOpenAiRuntime(
          configuration: externalConfig,
          client: client,
          bindings: [actorBinding, evalBinding],
        );
    _activeRuntime = runtime;

    try {
      await runtime.initialize(
        const RuntimeInitializationRequest(
          instanceId: RuntimeInstanceId('bootstrap-external-instance'),
        ),
      );
    } on RuntimeException catch (e) {
      throw ApplicationBootstrapException(
        ApplicationBootstrapFailure(
          code: ApplicationBootstrapFailureCode.runtimeInitializationFailed,
          message:
              'Inizializzazione di ExternalOpenAiRuntime fallita: ${e.failure.message}',
        ),
        e,
      );
    } catch (e) {
      throw ApplicationBootstrapException(
        ApplicationBootstrapFailure(
          code: ApplicationBootstrapFailureCode.runtimeInitializationFailed,
          message: 'Inizializzazione di ExternalOpenAiRuntime fallita: $e',
        ),
        e,
      );
    }

    RuntimeModelExecutionPlan actorPlan;
    RuntimeModelExecutionPlan evalPlan;

    if (config.useSharedModel) {
      final sharedBinding = ExternalOpenAiModelBinding(
        logicalModelId: 'aura.shared.primary',
        serverModelId: config.actorModelId,
        roles: const {ModelRole.actor, ModelRole.evaluator},
      );
      try {
        final sharedLoadReq = ModelLoadRequest(
          requestId: const ModelLoadRequestId('bootstrap-shared-load'),
          artifact: const ResolvedModelArtifact(
            modelVariantId: 'variant-shared',
            sha256: 'placeholder-sha',
            format: 'gguf',
            quantization: 'q4_0',
            architecture: 'shared',
            compatibility: ModelRuntimeCompatibility(compatible: true),
          ),
          logicalModelId: sharedBinding.logicalModelId,
          roles: sharedBinding.roles,
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
      } catch (e) {
        throw ApplicationBootstrapException(
          ApplicationBootstrapFailure(
            code: ApplicationBootstrapFailureCode.modelLoadFailed,
            message: 'Caricamento del modello condiviso fallito: $e',
          ),
          e,
        );
      }
    } else {
      try {
        final actorLoadReq = ModelLoadRequest(
          requestId: const ModelLoadRequestId('bootstrap-actor-load'),
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
          requestId: const ModelLoadRequestId('bootstrap-eval-load'),
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
      } catch (e) {
        throw ApplicationBootstrapException(
          ApplicationBootstrapFailure(
            code: ApplicationBootstrapFailureCode.modelLoadFailed,
            message: 'Caricamento dei binding Attore/Valutatore fallito: $e',
          ),
          e,
        );
      }
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
              'ExternalOpenAiRuntime non risponde al controlli di integrità.';
        }
      } catch (e) {
        isHealthy = false;
        statusMsg = 'Health check di ExternalOpenAiRuntime fallito: $e';
      }

      if (!isHealthy &&
          config.fallbackPolicy == BootstrapFallbackPolicy.ruleBased) {
        return await _bootstrapRuleBased();
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
      },
    );

    return ApplicationBootstrapResult(
      controller: controller,
      activeBridge: bridge,
      runtime: runtime,
      runtimeMode: ApplicationRuntimeMode.externalOpenAiRuntime,
      status: status,
      onDispose: dispose,
    );
  }

  Future<ApplicationBootstrapResult> _bootstrapRuleBased() async {
    final runtime = RuleBasedInferenceRuntime();
    _activeRuntime = runtime;
    await runtime.initialize(
      const RuntimeInitializationRequest(
        instanceId: RuntimeInstanceId('bootstrap-rule-instance'),
      ),
    );

    final actorLoadReq = const ModelLoadRequest(
      requestId: ModelLoadRequestId('bootstrap-rule-actor-load'),
      artifact: ResolvedModelArtifact(
        modelVariantId: 'variant-rule-actor',
        sha256: 'placeholder-sha',
        format: 'rule',
        quantization: 'none',
        architecture: 'rule',
        compatibility: ModelRuntimeCompatibility(compatible: true),
      ),
      logicalModelId: 'aura.actor.primary',
      roles: {ModelRole.actor},
    );
    final evalLoadReq = const ModelLoadRequest(
      requestId: ModelLoadRequestId('bootstrap-rule-eval-load'),
      artifact: ResolvedModelArtifact(
        modelVariantId: 'variant-rule-eval',
        sha256: 'placeholder-sha',
        format: 'rule',
        quantization: 'none',
        architecture: 'rule',
        compatibility: ModelRuntimeCompatibility(compatible: true),
      ),
      logicalModelId: 'aura.evaluator.primary',
      roles: {ModelRole.evaluator},
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
    final status = const ApplicationRuntimeStatus(
      runtimeMode: ApplicationRuntimeMode.ruleBased,
      isHealthy: true,
      statusDescription: 'Motore offline deterministico (rule-based) attivo.',
    );

    return ApplicationBootstrapResult(
      controller: controller,
      activeBridge: bridge,
      runtime: runtime,
      runtimeMode: ApplicationRuntimeMode.ruleBased,
      status: status,
      onDispose: dispose,
    );
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    try {
      if (_activeRuntime != null) {
        await _activeRuntime!.dispose();
        _activeRuntime = null;
      }
      if (_activeClient != null) {
        _activeClient!.close();
        _activeClient = null;
      }
    } catch (e) {
      throw ApplicationBootstrapException(
        ApplicationBootstrapFailure(
          code: ApplicationBootstrapFailureCode.disposeFailed,
          message: 'Errore durante la dismissione delle risorse: $e',
        ),
        e,
      );
    }
  }
}
