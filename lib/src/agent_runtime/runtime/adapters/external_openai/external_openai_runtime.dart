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
import 'external_openai_client.dart';
import 'external_openai_configuration.dart';
import 'external_openai_model_binding.dart';
import 'external_openai_response_parser.dart';

/// OpenAI-compatible backend adapter implementing [InferenceRuntime].
///
/// Communicates with external OpenAI-compatible HTTP servers (e.g. LM Studio, llama-server)
/// while maintaining strict platform neutrality and typed contract invariants.
class ExternalOpenAiRuntime implements InferenceRuntime {
  final ExternalOpenAiConfiguration configuration;
  final ExternalOpenAiClient client;
  final ExternalOpenAiResponseParser parser;
  final Map<String, ExternalOpenAiModelBinding> bindings;

  RuntimeState _state = RuntimeState.uninitialized;
  RuntimeInstanceId? _instanceId;
  final StreamController<RuntimeEvent> _eventController =
      StreamController<RuntimeEvent>.broadcast();

  final Map<ModelHandleId, ModelHandle> _activeHandles = {};
  final Set<String> _activeCancelRequestIds = {};
  int _activeGenerationsCount = 0;

  ExternalOpenAiRuntime({
    required this.configuration,
    required this.client,
    this.parser = const ExternalOpenAiResponseParser(),
    List<ExternalOpenAiModelBinding> bindings = const [],
  }) : bindings = {
          for (final b in bindings) b.logicalModelId: b,
        };

  /// Factory constructor for development using [HttpExternalOpenAiClient].
  factory ExternalOpenAiRuntime.development({
    ExternalOpenAiConfiguration? configuration,
    List<ExternalOpenAiModelBinding> bindings = const [],
  }) {
    final config =
        configuration ?? ExternalOpenAiConfiguration.developmentDefault();
    return ExternalOpenAiRuntime(
      configuration: config,
      client: HttpExternalOpenAiClient(configuration: config),
      bindings: bindings,
    );
  }

  @override
  RuntimeState get state => _state;

  @override
  Stream<RuntimeEvent> get events => _eventController.stream;

  void _changeState(RuntimeState newState, {RuntimeTraceId? traceId}) {
    if (_state == newState) return;
    final oldState = _state;
    _state = newState;
    if (_instanceId != null && !_eventController.isClosed) {
      _eventController.add(
        RuntimeStateChanged(
          instanceId: _instanceId!,
          timestamp: DateTime.now(),
          previousState: oldState,
          newState: newState,
          traceId: traceId,
        ),
      );
    }
  }

  void _ensureNotDisposed() {
    if (_state == RuntimeState.disposed || _state == RuntimeState.disposing) {
      throw const RuntimeException(
        RuntimeFailure(
          code: RuntimeFailureCode.disposed,
          message: 'Il session runtime è già stato eliminato (disposed).',
        ),
      );
    }
  }

  void _ensureInitializedAndNotDisposed() {
    _ensureNotDisposed();
    if (_state == RuntimeState.uninitialized ||
        _state == RuntimeState.initializing) {
      throw const RuntimeException(
        RuntimeFailure(
          code: RuntimeFailureCode.invalidState,
          message:
              'Il runtime deve essere prima inizializzato via initialize().',
        ),
      );
    }
  }

  void _validateHandle(ModelHandle handle) {
    if (handle.runtimeInstanceId != _instanceId) {
      throw RuntimeException(
        RuntimeFailure(
          code: RuntimeFailureCode.invalidModelHandle,
          message:
              'ModelHandle non appartiene all\'istanza di runtime attiva (${handle.runtimeInstanceId} vs $_instanceId).',
        ),
      );
    }
    if (!_activeHandles.containsKey(handle.id)) {
      throw RuntimeException(
        RuntimeFailure(
          code: RuntimeFailureCode.invalidModelHandle,
          message: 'ModelHandle non trovato o non registrato come caricato.',
        ),
      );
    }
  }

  String _resolveServerModelId(String logicalModelId) {
    final binding = bindings[logicalModelId];
    if (binding != null) {
      return binding.serverModelId;
    }
    return logicalModelId;
  }

  @override
  Future<RuntimeCapabilities> initialize(
    RuntimeInitializationRequest request,
  ) async {
    _ensureNotDisposed();
    if (_state != RuntimeState.uninitialized) {
      throw const RuntimeException(
        RuntimeFailure(
          code: RuntimeFailureCode.alreadyInitialized,
          message: 'Runtime già inizializzato.',
        ),
      );
    }

    _instanceId = request.instanceId;
    _changeState(RuntimeState.initializing);

    final isHealthy = await client.checkHealth();
    if (!isHealthy && !request.adapterOptions.containsKey('skipHealthCheck')) {
      _changeState(RuntimeState.failed);
      throw const RuntimeException(
        RuntimeFailure(
          code: RuntimeFailureCode.backendUnavailable,
          message:
              'Impossibile connettersi al server OpenAI-compatible esterno.',
        ),
      );
    }

    const capabilities = RuntimeCapabilities(
      adapterId: RuntimeAdapterId('adapter.external.openai'),
      runtimeName: 'External OpenAI-Compatible Runtime',
      runtimeVersion: '1.0.0',
      runtimeBuildId: 'external-openai-v1',
      selectedBackend: RuntimeBackend.cpu,
      generationCapabilities: {
        GenerationCapability.text,
        GenerationCapability.structuredJson,
        GenerationCapability.cancellation,
      },
      modelCapabilities: {
        ModelCapability.multipleLoadedModels,
        ModelCapability.cpuExecution,
      },
      maxConcurrentGenerations: 4,
      maxLoadedModels: 4,
      supportsCancellation: true,
      supportsHealthCheck: true,
      supportsTokenStreaming: false,
      supportsGrammarConstraints: false,
      supportsJsonSchema: true,
      supportsLoRA: false,
    );

    _changeState(RuntimeState.ready);
    if (!_eventController.isClosed) {
      _eventController.add(
        RuntimeInitialized(
          instanceId: _instanceId!,
          timestamp: DateTime.now(),
          adapterName: capabilities.runtimeName,
          runtimeVersion: capabilities.runtimeVersion,
        ),
      );
    }

    return capabilities;
  }

  @override
  Future<ModelHandle> loadModel(ModelLoadRequest request) async {
    _ensureInitializedAndNotDisposed();
    _changeState(RuntimeState.loadingModel);

    if (!_eventController.isClosed) {
      _eventController.add(
        ModelLoadStarted(
          instanceId: _instanceId!,
          timestamp: DateTime.now(),
          loadRequestId: request.requestId,
          logicalModelId: request.logicalModelId,
        ),
      );
    }

    final serverModelId = _resolveServerModelId(request.logicalModelId);
    if (configuration.supportsDiscovery) {
      final available = await client.discoverModels();
      if (available.isNotEmpty && !available.contains(serverModelId)) {
        _changeState(_activeHandles.isNotEmpty
            ? RuntimeState.modelReady
            : RuntimeState.ready);
        final failure = RuntimeFailure(
          code: RuntimeFailureCode.modelMissing,
          message: 'Modello esterno "$serverModelId" non caricato nel server.',
        );
        if (!_eventController.isClosed) {
          _eventController.add(
            ModelLoadFailed(
              instanceId: _instanceId!,
              timestamp: DateTime.now(),
              loadRequestId: request.requestId,
              failure: failure,
            ),
          );
        }
        throw RuntimeException(failure);
      }
    }

    final handleId = ModelHandleId(
        'ext-handle-${request.logicalModelId}-${_activeHandles.length + 1}');
    final handle = ModelHandle(
      id: handleId,
      runtimeInstanceId: _instanceId!,
      logicalModelId: request.logicalModelId,
      modelVariantId: request.artifact.modelVariantId,
      roles: request.roles,
      loadedAt: DateTime.now(),
    );

    _activeHandles[handleId] = handle;
    _changeState(RuntimeState.modelReady);

    if (!_eventController.isClosed) {
      _eventController.add(
        ModelLoadCompleted(
          instanceId: _instanceId!,
          timestamp: DateTime.now(),
          loadRequestId: request.requestId,
          handle: handle,
        ),
      );
    }

    return handle;
  }

  @override
  Future<void> unloadModel(ModelHandle handle) async {
    _ensureInitializedAndNotDisposed();
    _validateHandle(handle);

    _changeState(RuntimeState.unloadingModel);
    if (!_eventController.isClosed) {
      _eventController.add(
        ModelUnloadStarted(
          instanceId: _instanceId!,
          timestamp: DateTime.now(),
          handle: handle,
        ),
      );
    }

    _activeHandles.remove(handle.id);

    if (!_eventController.isClosed) {
      _eventController.add(
        ModelUnloadCompleted(
          instanceId: _instanceId!,
          timestamp: DateTime.now(),
          handleId: handle.id,
        ),
      );
    }

    _changeState(_activeHandles.isNotEmpty
        ? RuntimeState.modelReady
        : RuntimeState.ready);
  }

  @override
  Future<TextGenerationResult> generateText(
    TextGenerationRequest request,
  ) async {
    _ensureInitializedAndNotDisposed();
    _validateHandle(request.model);

    _activeGenerationsCount++;
    _changeState(RuntimeState.generating,
        traceId: request.traceContext.traceId);

    if (!_eventController.isClosed) {
      _eventController.add(
        GenerationStarted(
          instanceId: _instanceId!,
          timestamp: DateTime.now(),
          requestId: request.requestId,
          handle: request.model,
          traceId: request.traceContext.traceId,
        ),
      );
    }

    final serverModelId = _resolveServerModelId(request.model.logicalModelId);
    final payload = <String, dynamic>{
      'model': serverModelId,
      'messages': request.messages
          .map((m) => {
                'role': m.role.name,
                'content': m.content,
              })
          .toList(),
      'temperature': request.parameters.temperature,
      'max_tokens': request.parameters.maxOutputTokens,
    };

    if (request.parameters.seed != null) {
      payload['seed'] = request.parameters.seed;
    }

    final stopwatch = Stopwatch()..start();

    try {
      final response = await client.chatCompletions(
        payload,
        requestId: request.requestId.value,
      );
      stopwatch.stop();

      if (_activeCancelRequestIds.contains(request.requestId.value)) {
        _activeCancelRequestIds.remove(request.requestId.value);
        const failure = RuntimeFailure(
          code: RuntimeFailureCode.cancelled,
          message: 'Generazione cancellata.',
        );
        if (!_eventController.isClosed) {
          _eventController.add(
            GenerationCancelled(
              instanceId: _instanceId!,
              timestamp: DateTime.now(),
              requestId: request.requestId,
              traceId: request.traceContext.traceId,
            ),
          );
        }
        throw const RuntimeException(failure);
      }

      final result = parser.parseTextResponse(
        response: response,
        requestId: request.requestId,
        model: request.model,
        latency: stopwatch.elapsed,
      );

      if (!_eventController.isClosed) {
        _eventController.add(
          GenerationCompleted(
            instanceId: _instanceId!,
            timestamp: DateTime.now(),
            requestId: request.requestId,
            latency: stopwatch.elapsed,
            traceId: request.traceContext.traceId,
          ),
        );
      }

      return result;
    } on RuntimeException catch (e) {
      if (!_eventController.isClosed) {
        _eventController.add(
          GenerationFailed(
            instanceId: _instanceId!,
            timestamp: DateTime.now(),
            requestId: request.requestId,
            failure: e.failure,
            traceId: request.traceContext.traceId,
          ),
        );
      }
      rethrow;
    } catch (e) {
      final failure = RuntimeFailure(
        code: RuntimeFailureCode.generationFailed,
        message: 'Errore imprevisto durante la generazione testo.',
      );
      if (!_eventController.isClosed) {
        _eventController.add(
          GenerationFailed(
            instanceId: _instanceId!,
            timestamp: DateTime.now(),
            requestId: request.requestId,
            failure: failure,
            traceId: request.traceContext.traceId,
          ),
        );
      }
      throw RuntimeException(failure, cause: e);
    } finally {
      _activeGenerationsCount--;
      if (_activeGenerationsCount == 0 && _state != RuntimeState.disposed) {
        _changeState(_activeHandles.isNotEmpty
            ? RuntimeState.modelReady
            : RuntimeState.ready);
      }
    }
  }

  @override
  Future<StructuredGenerationResult> generateStructured(
    StructuredGenerationRequest request,
  ) async {
    _ensureInitializedAndNotDisposed();
    _validateHandle(request.model);

    _activeGenerationsCount++;
    _changeState(RuntimeState.generating,
        traceId: request.traceContext.traceId);

    if (!_eventController.isClosed) {
      _eventController.add(
        GenerationStarted(
          instanceId: _instanceId!,
          timestamp: DateTime.now(),
          requestId: request.requestId,
          handle: request.model,
          traceId: request.traceContext.traceId,
        ),
      );
    }

    final serverModelId = _resolveServerModelId(request.model.logicalModelId);
    final payload = <String, dynamic>{
      'model': serverModelId,
      'messages': request.messages
          .map((m) => {
                'role': m.role.name,
                'content': m.content,
              })
          .toList(),
      'temperature': request.parameters.temperature,
      'response_format': {
        'type': 'json_schema',
        'json_schema': {
          'name': request.schema.schemaId,
          'strict': true,
          'schema': request.schema.document,
        }
      }
    };

    final stopwatch = Stopwatch()..start();

    try {
      final response = await client.chatCompletions(
        payload,
        requestId: request.requestId.value,
      );
      stopwatch.stop();

      if (_activeCancelRequestIds.contains(request.requestId.value)) {
        _activeCancelRequestIds.remove(request.requestId.value);
        const failure = RuntimeFailure(
          code: RuntimeFailureCode.cancelled,
          message: 'Generazione strutturata cancellata.',
        );
        if (!_eventController.isClosed) {
          _eventController.add(
            GenerationCancelled(
              instanceId: _instanceId!,
              timestamp: DateTime.now(),
              requestId: request.requestId,
              traceId: request.traceContext.traceId,
            ),
          );
        }
        throw const RuntimeException(failure);
      }

      final result = parser.parseStructuredResponse(
        response: response,
        requestId: request.requestId,
        model: request.model,
        latency: stopwatch.elapsed,
      );

      if (!_eventController.isClosed) {
        _eventController.add(
          GenerationCompleted(
            instanceId: _instanceId!,
            timestamp: DateTime.now(),
            requestId: request.requestId,
            latency: stopwatch.elapsed,
            traceId: request.traceContext.traceId,
          ),
        );
      }

      return result;
    } on RuntimeException catch (e) {
      if (!_eventController.isClosed) {
        _eventController.add(
          GenerationFailed(
            instanceId: _instanceId!,
            timestamp: DateTime.now(),
            requestId: request.requestId,
            failure: e.failure,
            traceId: request.traceContext.traceId,
          ),
        );
      }
      rethrow;
    } catch (e) {
      final failure = RuntimeFailure(
        code: RuntimeFailureCode.generationFailed,
        message: 'Errore imprevisto durante la generazione strutturata.',
      );
      if (!_eventController.isClosed) {
        _eventController.add(
          GenerationFailed(
            instanceId: _instanceId!,
            timestamp: DateTime.now(),
            requestId: request.requestId,
            failure: failure,
            traceId: request.traceContext.traceId,
          ),
        );
      }
      throw RuntimeException(failure, cause: e);
    } finally {
      _activeGenerationsCount--;
      if (_activeGenerationsCount == 0 && _state != RuntimeState.disposed) {
        _changeState(_activeHandles.isNotEmpty
            ? RuntimeState.modelReady
            : RuntimeState.ready);
      }
    }
  }

  @override
  Future<void> cancel(GenerationRequestId requestId) async {
    _ensureNotDisposed();
    _activeCancelRequestIds.add(requestId.value);
    await client.cancel(requestId.value);
  }

  @override
  Future<RuntimeHealth> health() async {
    _ensureNotDisposed();
    final isResponsive = await client.checkHealth();
    return RuntimeHealth(
      instanceId: _instanceId ?? const RuntimeInstanceId('uninitialized'),
      state: _state,
      responsive: isResponsive,
      observedAt: DateTime.now(),
      backend: RuntimeBackend.cpu,
      loadedModelCount: _activeHandles.length,
      activeGenerations: _activeGenerationsCount,
    );
  }

  @override
  Future<void> dispose() async {
    if (_state == RuntimeState.disposed) return;
    _changeState(RuntimeState.disposing);

    if (_instanceId != null && !_eventController.isClosed) {
      _eventController.add(
        RuntimeDisposing(
          instanceId: _instanceId!,
          timestamp: DateTime.now(),
        ),
      );
    }

    _activeHandles.clear();
    _activeCancelRequestIds.clear();
    _activeGenerationsCount = 0;

    await client.close();

    _changeState(RuntimeState.disposed);
    if (!_eventController.isClosed) {
      _eventController.add(
        RuntimeDisposed(
          instanceId: _instanceId ?? const RuntimeInstanceId('unknown'),
          timestamp: DateTime.now(),
        ),
      );
      await _eventController.close();
    }
  }
}
