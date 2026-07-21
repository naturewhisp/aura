import 'dart:async';
import '../../inference_runtime.dart';
import '../../model_handle.dart';
import '../../runtime_backend.dart';
import '../../runtime_capabilities.dart';
import '../../runtime_events.dart';
import '../../runtime_failure.dart';
import '../../runtime_health.dart';
import '../../runtime_ids.dart';
import '../../runtime_requests.dart';
import '../../runtime_results.dart';
import '../../runtime_state.dart';
import '../external_openai/external_openai_configuration.dart';
import '../external_openai/external_openai_model_binding.dart';
import '../external_openai/external_openai_runtime.dart';
import 'llama_server_process_supervisor.dart';
import 'managed_llama_server_configuration.dart';
import 'managed_llama_server_failure.dart';

/// Adapter runtime per la gestione locale di `llama-server` su Windows.
///
/// Implementa il contratto [InferenceRuntime] orchestrando l'avvio, l'health check ed
/// il cleanup del processo locale tramite [LlamaServerProcessSupervisor], e delegando
/// l'esecuzione delle generazioni ad un'istanza interna di [ExternalOpenAiRuntime].
class ManagedLlamaServerRuntime implements InferenceRuntime {
  final ManagedLlamaServerConfiguration _configuration;
  final LlamaServerProcessSupervisor _supervisor;
  final ExternalOpenAiRuntime Function(
    ExternalOpenAiConfiguration config,
    List<ExternalOpenAiModelBinding> bindings,
  )? _delegateFactory;

  ExternalOpenAiRuntime? _delegateRuntime;
  bool _initialized = false;
  bool _disposed = false;
  Future<void>? _disposeFuture;
  final List<ModelHandle> _activeHandles = [];
  final StreamController<RuntimeEvent> _eventController =
      StreamController<RuntimeEvent>.broadcast();

  ManagedLlamaServerRuntime({
    required ManagedLlamaServerConfiguration configuration,
    required LlamaServerProcessSupervisor supervisor,
    ExternalOpenAiRuntime Function(
      ExternalOpenAiConfiguration config,
      List<ExternalOpenAiModelBinding> bindings,
    )? delegateFactory,
  })  : _configuration = configuration,
        _supervisor = supervisor,
        _delegateFactory = delegateFactory;

  LlamaServerProcessSupervisor get supervisor => _supervisor;

  @override
  RuntimeState get state {
    if (_disposed) return RuntimeState.disposed;
    if (_supervisor.state == LlamaServerSupervisorState.failed) {
      return RuntimeState.failed;
    }
    if (_initialized) return RuntimeState.ready;
    if (_supervisor.state == LlamaServerSupervisorState.starting ||
        _supervisor.state == LlamaServerSupervisorState.probing) {
      return RuntimeState.initializing;
    }
    return RuntimeState.uninitialized;
  }

  @override
  Stream<RuntimeEvent> get events => _eventController.stream;

  @override
  Future<RuntimeCapabilities> initialize(
      [RuntimeInitializationRequest? request]) async {
    if (_initialized) {
      throw const RuntimeException(
        RuntimeFailure(
          code: RuntimeFailureCode.alreadyInitialized,
          message: 'ManagedLlamaServerRuntime già inizializzato.',
        ),
      );
    }

    try {
      // 1. Avvia il supervisor e attende che il server HTTP loopback sia pronto
      final allocatedPort = await _supervisor.start();

      // 2. Costruisce la configurazione per ExternalOpenAiRuntime connesso a llama-server
      final externalConfig = ExternalOpenAiConfiguration(
        baseUri: Uri.parse('http://${_configuration.host}:$allocatedPort'),
        apiKey: _configuration.apiKey,
        transportTimeout: _configuration.startupTimeout,
        supportsMultipleLoadedModels: true,
        maxLoadedModels: 2,
      );

      final bindings = [
        ExternalOpenAiModelBinding(
          logicalModelId: 'aura.actor.primary',
          serverModelId: _configuration.modelAlias,
          roles: const {ModelRole.actor, ModelRole.evaluator},
        ),
        ExternalOpenAiModelBinding(
          logicalModelId: 'aura.evaluator.primary',
          serverModelId: _configuration.modelAlias,
          roles: const {ModelRole.actor, ModelRole.evaluator},
        ),
      ];

      // 3. Inizializza l'adattatore delegato HTTP
      _delegateRuntime = _delegateFactory != null
          ? _delegateFactory!(externalConfig, bindings)
          : ExternalOpenAiRuntime.development(
              configuration: externalConfig,
              bindings: bindings,
            );

      final initReq = request ??
          RuntimeInitializationRequest(
            instanceId: RuntimeInstanceId(
                _configuration.runtimeInstanceId ?? 'managed-llama-instance'),
          );

      final delegateCapabilities = await _delegateRuntime!.initialize(initReq);
      _initialized = true;

      final normalizedModelCaps = delegateCapabilities.modelCapabilities
          .where((cap) => cap != ModelCapability.multipleLoadedModels)
          .toSet();

      // 4. Personalizza le capabilities dichiarate per rispecchiare il runtime gestito
      // Info Hiding: non esponiamo mai porta o PID nei DTO pubblici
      return RuntimeCapabilities(
        adapterId: const RuntimeAdapterId('llama-server-managed'),
        runtimeName: 'llama-server',
        runtimeVersion: '1.0.0',
        runtimeBuildId: 'managed',
        selectedBackend: RuntimeBackend.systemManaged,
        generationCapabilities: delegateCapabilities.generationCapabilities,
        modelCapabilities: normalizedModelCaps,
        maxConcurrentGenerations: _configuration.parallelSlots ?? 1,
        maxLoadedModels: 1,
        supportsCancellation: delegateCapabilities.supportsCancellation,
        supportsHealthCheck: true,
        extensions: {
          'managed': true,
          'modelAlias': _configuration.modelAlias,
          'logicalBindingsCount': 2,
          ...delegateCapabilities.extensions,
        },
      );
    } on ManagedLlamaServerException catch (e) {
      await dispose();
      throw RuntimeException(
        RuntimeFailure(
          code: _mapFailureCode(e.code),
          message: e.message,
        ),
        cause: e,
      );
    } catch (e) {
      await dispose();
      if (e is RuntimeException) rethrow;
      throw RuntimeException(
        const RuntimeFailure(
          code: RuntimeFailureCode.runtimeInitializationFailed,
          message: 'Impossibile inizializzare ManagedLlamaServerRuntime.',
        ),
        cause: e,
      );
    }
  }

  @override
  Future<ModelHandle> loadModel(ModelLoadRequest request) async {
    _checkInitialized();

    // Consente multipli logical handle sullo stesso modello fisico
    if (request.artifact.modelVariantId != _configuration.modelAlias) {
      throw const RuntimeException(
        RuntimeFailure(
          code: RuntimeFailureCode.unsupportedCapability,
          message:
              'ManagedLlamaServerRuntime supporta solo il caricamento del modello fisico configurato.',
        ),
      );
    }

    if (request.artifact.localArtifactUri != null) {
      final requestPath = request.artifact.localArtifactUri!.toFilePath();
      final configPath = Uri.file(_configuration.modelPath).toFilePath();
      if (requestPath != configPath) {
        throw const RuntimeException(
          RuntimeFailure(
            code: RuntimeFailureCode.unsupportedCapability,
            message:
                'ManagedLlamaServerRuntime supporta solo il caricamento del modello al percorso configurato.',
          ),
        );
      }
    }

    final handle = await _delegateRuntime!.loadModel(request);

    if (!_activeHandles.any((h) => h.id == handle.id)) {
      _activeHandles.add(handle);
    }

    return handle;
  }

  @override
  Future<void> unloadModel(ModelHandle handle) async {
    _checkInitialized();
    await _delegateRuntime!.unloadModel(handle);
    _activeHandles.removeWhere((h) => h.id == handle.id);
  }

  @override
  Future<TextGenerationResult> generateText(
      TextGenerationRequest request) async {
    _checkInitialized();
    return await _delegateRuntime!.generateText(request);
  }

  @override
  Future<StructuredGenerationResult> generateStructured(
      StructuredGenerationRequest request) async {
    _checkInitialized();
    return await _delegateRuntime!.generateStructured(request);
  }

  @override
  Future<void> cancel(GenerationRequestId requestId) async {
    _checkInitialized();
    await _delegateRuntime!.cancel(requestId);
  }

  @override
  Future<RuntimeHealth> health() async {
    final observedAt = DateTime.now();
    final instanceId = RuntimeInstanceId(
        _configuration.runtimeInstanceId ?? 'managed-llama-instance');

    if (!_initialized || _disposed || state == RuntimeState.failed) {
      return RuntimeHealth(
        instanceId: instanceId,
        state: _disposed
            ? RuntimeState.disposed
            : (state == RuntimeState.failed
                ? RuntimeState.failed
                : RuntimeState.uninitialized),
        responsive: false,
        observedAt: observedAt,
        backend: RuntimeBackend.systemManaged,
      );
    }

    final supervisorHealth = await _supervisor.checkHealth();
    final delegateHealth = await _delegateRuntime!.health();

    final isHealthy = supervisorHealth.responsive && delegateHealth.responsive;

    // Info Hiding: escludiamo pid e porta dai diagnostics dello status pubblico
    return RuntimeHealth(
      instanceId: instanceId,
      state: isHealthy ? RuntimeState.ready : RuntimeState.failed,
      responsive: isHealthy,
      observedAt: observedAt,
      backend: RuntimeBackend.systemManaged,
      activeGenerations: delegateHealth.activeGenerations,
      loadedModelCount: _activeHandles.length,
    );
  }

  @override
  Future<void> dispose() async {
    return _disposeFuture ??= _performDispose();
  }

  Future<void> _performDispose() async {
    _initialized = false;
    _disposed = true;
    _activeHandles.clear();

    final List<Object> errors = [];

    try {
      if (_delegateRuntime != null) {
        await _delegateRuntime!.dispose();
      }
    } catch (e) {
      errors.add(e);
    } finally {
      _delegateRuntime = null;
    }

    try {
      await _supervisor.dispose();
    } catch (e) {
      errors.add(e);
    }

    try {
      await _eventController.close();
    } catch (e) {
      errors.add(e);
    }

    if (errors.isNotEmpty) {
      throw RuntimeException(
        const RuntimeFailure(
          code: RuntimeFailureCode.invalidState,
          message:
              'Errore durante la dismissione di ManagedLlamaServerRuntime.',
        ),
        cause: errors.length == 1 ? errors.first : errors,
      );
    }
  }

  void _checkInitialized() {
    if (!_initialized || _delegateRuntime == null || _disposed) {
      throw const RuntimeException(
        RuntimeFailure(
          code: RuntimeFailureCode.invalidState,
          message:
              'ManagedLlamaServerRuntime non inizializzato, dismesso o in stato di errore.',
        ),
      );
    }
  }

  RuntimeFailureCode _mapFailureCode(ManagedLlamaServerFailureCode code) {
    switch (code) {
      case ManagedLlamaServerFailureCode.executableMissing:
      case ManagedLlamaServerFailureCode.executableNotFile:
      case ManagedLlamaServerFailureCode.modelMissing:
      case ManagedLlamaServerFailureCode.modelNotFile:
        return RuntimeFailureCode.invalidArgument;
      case ManagedLlamaServerFailureCode.invalidPort:
      case ManagedLlamaServerFailureCode.invalidConfiguration:
      case ManagedLlamaServerFailureCode.unsupportedHost:
        return RuntimeFailureCode.invalidArgument;
      case ManagedLlamaServerFailureCode.processLaunchFailed:
        return RuntimeFailureCode.runtimeInitializationFailed;
      case ManagedLlamaServerFailureCode.processExitedEarly:
        return RuntimeFailureCode.runtimeCrashed;
      case ManagedLlamaServerFailureCode.startupTimeout:
        return RuntimeFailureCode.timeout;
      case ManagedLlamaServerFailureCode.healthCheckFailed:
        return RuntimeFailureCode.backendUnavailable;
      case ManagedLlamaServerFailureCode.shutdownTimeout:
        return RuntimeFailureCode.timeout;
      case ManagedLlamaServerFailureCode.forcedTerminationFailed:
        return RuntimeFailureCode.invalidState;
      case ManagedLlamaServerFailureCode.unexpectedProcessState:
        return RuntimeFailureCode.invalidState;
    }
  }
}
