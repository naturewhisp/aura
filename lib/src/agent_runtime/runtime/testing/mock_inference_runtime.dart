import 'dart:async';
import '../inference_runtime.dart';
import '../model_handle.dart';
import '../runtime_backend.dart';
import '../runtime_capabilities.dart';
import '../runtime_events.dart';
import '../runtime_failure.dart';
import '../runtime_health.dart';
import '../runtime_ids.dart';
import '../runtime_requests.dart';
import '../runtime_results.dart';
import '../runtime_state.dart';

/// Configurable mock implementation of [InferenceRuntime] for unit and contract testing.
class MockInferenceRuntime implements InferenceRuntime {
  final StreamController<RuntimeEvent> _eventController =
      StreamController<RuntimeEvent>.broadcast();

  RuntimeState _state = RuntimeState.uninitialized;
  RuntimeInstanceId? _instanceId;
  final Set<ModelHandleId> _activeHandles = {};
  final Set<GenerationRequestId> _activeGenerationRequests = {};
  final Set<GenerationRequestId> _cancelledRequestIds = {};

  // Configurable responses
  String textResponse;
  Map<String, Object?> structuredResponse;
  Duration simulatedDelay;
  RuntimeFailure? failureToThrowOnInitialize;
  RuntimeFailure? failureToThrowOnLoadModel;
  RuntimeFailure? failureToThrowOnGenerate;
  bool throwOnCancellation;

  // Call counters & recording
  int initializeCalls = 0;
  int loadModelCalls = 0;
  int unloadModelCalls = 0;
  int generateTextCalls = 0;
  int generateStructuredCalls = 0;
  int cancelCalls = 0;
  int healthCalls = 0;
  int disposeCalls = 0;

  final List<TextGenerationRequest> textRequests = [];
  final List<StructuredGenerationRequest> structuredRequests = [];

  MockInferenceRuntime({
    this.textResponse = "Mock response from MockInferenceRuntime.",
    this.structuredResponse = const {
      "delta_alert": 0,
      "delta_imperative": 5,
      "delta_control": 5,
      "delta_dissonance": 0,
      "creativity_index": 3,
      "injection_risk": 0,
      "semantic_category": "authority_framing",
    },
    this.simulatedDelay = Duration.zero,
    this.failureToThrowOnInitialize,
    this.failureToThrowOnLoadModel,
    this.failureToThrowOnGenerate,
    this.throwOnCancellation = false,
  });

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

  @override
  Future<RuntimeCapabilities> initialize(
    RuntimeInitializationRequest request,
  ) async {
    initializeCalls++;
    if (_state == RuntimeState.disposed) {
      throw const RuntimeException(
        RuntimeFailure(
          code: RuntimeFailureCode.disposed,
          message: 'Cannot initialize a disposed runtime.',
        ),
      );
    }
    if (_state != RuntimeState.uninitialized && _state != RuntimeState.failed) {
      throw const RuntimeException(
        RuntimeFailure(
          code: RuntimeFailureCode.alreadyInitialized,
          message: 'Runtime is already initialized.',
        ),
      );
    }

    _instanceId = request.instanceId;
    _changeState(RuntimeState.initializing);

    if (simulatedDelay > Duration.zero) {
      await Future<void>.delayed(simulatedDelay);
    }

    if (failureToThrowOnInitialize != null) {
      _changeState(RuntimeState.failed);
      _eventController.add(
        RuntimeInitializationFailed(
          instanceId: _instanceId!,
          timestamp: DateTime.now(),
          failure: failureToThrowOnInitialize!,
        ),
      );
      throw RuntimeException(failureToThrowOnInitialize!);
    }

    const capabilities = RuntimeCapabilities(
      adapterId: RuntimeAdapterId('mock_runtime_adapter'),
      runtimeName: 'Mock Inference Runtime',
      runtimeVersion: '1.0.0',
      runtimeBuildId: 'mock-build-001',
      selectedBackend: RuntimeBackend.mock,
      generationCapabilities: {
        GenerationCapability.text,
        GenerationCapability.structuredJson,
        GenerationCapability.cancellation,
        GenerationCapability.deterministicSeed,
      },
      modelCapabilities: {
        ModelCapability.multipleLoadedModels,
        ModelCapability.sharedModelAcrossRoles,
        ModelCapability.cpuExecution,
      },
      maxConcurrentGenerations: 4,
      maxLoadedModels: 4,
      supportsCancellation: true,
      supportsHealthCheck: true,
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
    loadModelCalls++;
    _ensureInitialized();
    if (_state.isDisposed) {
      throw const RuntimeException(
        RuntimeFailure(
          code: RuntimeFailureCode.disposed,
          message: 'Runtime is disposed.',
        ),
      );
    }

    _changeState(RuntimeState.loadingModel);
    _eventController.add(
      ModelLoadStarted(
        instanceId: _instanceId!,
        timestamp: DateTime.now(),
        loadRequestId: request.requestId,
        logicalModelId: request.logicalModelId,
      ),
    );

    if (simulatedDelay > Duration.zero) {
      await Future<void>.delayed(simulatedDelay);
    }

    if (failureToThrowOnLoadModel != null) {
      _changeState(_activeHandles.isNotEmpty
          ? RuntimeState.modelReady
          : RuntimeState.ready);
      _eventController.add(
        ModelLoadFailed(
          instanceId: _instanceId!,
          timestamp: DateTime.now(),
          loadRequestId: request.requestId,
          failure: failureToThrowOnLoadModel!,
        ),
      );
      throw RuntimeException(failureToThrowOnLoadModel!);
    }

    final handleId = ModelHandleId(
        'mock-handle-${request.logicalModelId}-${_activeHandles.length + 1}');
    final handle = ModelHandle(
      id: handleId,
      runtimeInstanceId: _instanceId!,
      logicalModelId: request.logicalModelId,
      modelVariantId: request.artifact.modelVariantId,
      roles: request.roles,
      loadedAt: DateTime.now(),
    );

    _activeHandles.add(handleId);
    _changeState(RuntimeState.modelReady);

    _eventController.add(
      ModelLoadCompleted(
        instanceId: _instanceId!,
        timestamp: DateTime.now(),
        loadRequestId: request.requestId,
        handle: handle,
      ),
    );

    return handle;
  }

  @override
  Future<void> unloadModel(ModelHandle handle) async {
    unloadModelCalls++;
    _ensureInitialized();
    _validateHandle(handle);

    _changeState(RuntimeState.unloadingModel);
    _eventController.add(
      ModelUnloadStarted(
        instanceId: _instanceId!,
        timestamp: DateTime.now(),
        handle: handle,
      ),
    );

    _activeHandles.remove(handle.id);

    _eventController.add(
      ModelUnloadCompleted(
        instanceId: _instanceId!,
        timestamp: DateTime.now(),
        handleId: handle.id,
      ),
    );

    _changeState(_activeHandles.isNotEmpty
        ? RuntimeState.modelReady
        : RuntimeState.ready);
  }

  @override
  Future<TextGenerationResult> generateText(
      TextGenerationRequest request) async {
    generateTextCalls++;
    textRequests.add(request);
    _ensureInitialized();
    _validateHandle(request.model);

    _activeGenerationRequests.add(request.requestId);
    _changeState(RuntimeState.generating,
        traceId: request.traceContext.traceId);
    _eventController.add(
      GenerationStarted(
        instanceId: _instanceId!,
        timestamp: DateTime.now(),
        requestId: request.requestId,
        handle: request.model,
        traceId: request.traceContext.traceId,
      ),
    );

    final stopwatch = Stopwatch()..start();
    if (simulatedDelay > Duration.zero) {
      await Future<void>.delayed(simulatedDelay);
    }
    stopwatch.stop();

    _activeGenerationRequests.remove(request.requestId);

    if (_cancelledRequestIds.contains(request.requestId)) {
      _cancelledRequestIds.remove(request.requestId);
      _changeState(_activeHandles.isNotEmpty
          ? RuntimeState.modelReady
          : RuntimeState.ready);
      throw const RuntimeException(
        RuntimeFailure(
          code: RuntimeFailureCode.cancelled,
          message: 'Generation was cancelled.',
        ),
      );
    }

    if (failureToThrowOnGenerate != null) {
      _changeState(_activeHandles.isNotEmpty
          ? RuntimeState.modelReady
          : RuntimeState.ready);
      _eventController.add(
        GenerationFailed(
          instanceId: _instanceId!,
          timestamp: DateTime.now(),
          requestId: request.requestId,
          failure: failureToThrowOnGenerate!,
          traceId: request.traceContext.traceId,
        ),
      );
      throw RuntimeException(failureToThrowOnGenerate!);
    }

    final result = TextGenerationResult(
      requestId: request.requestId,
      model: request.model,
      content: textResponse,
      finishReason: GenerationFinishReason.completed,
      latency: stopwatch.elapsed,
    );

    _eventController.add(
      GenerationCompleted(
        instanceId: _instanceId!,
        timestamp: DateTime.now(),
        requestId: request.requestId,
        latency: stopwatch.elapsed,
        traceId: request.traceContext.traceId,
      ),
    );

    _changeState(_activeHandles.isNotEmpty
        ? RuntimeState.modelReady
        : RuntimeState.ready);
    return result;
  }

  @override
  Future<StructuredGenerationResult> generateStructured(
    StructuredGenerationRequest request,
  ) async {
    generateStructuredCalls++;
    structuredRequests.add(request);
    _ensureInitialized();
    _validateHandle(request.model);

    _activeGenerationRequests.add(request.requestId);
    _changeState(RuntimeState.generating,
        traceId: request.traceContext.traceId);
    _eventController.add(
      GenerationStarted(
        instanceId: _instanceId!,
        timestamp: DateTime.now(),
        requestId: request.requestId,
        handle: request.model,
        traceId: request.traceContext.traceId,
      ),
    );

    final stopwatch = Stopwatch()..start();
    if (simulatedDelay > Duration.zero) {
      await Future<void>.delayed(simulatedDelay);
    }
    stopwatch.stop();

    _activeGenerationRequests.remove(request.requestId);

    if (_cancelledRequestIds.contains(request.requestId)) {
      _cancelledRequestIds.remove(request.requestId);
      _changeState(_activeHandles.isNotEmpty
          ? RuntimeState.modelReady
          : RuntimeState.ready);
      throw const RuntimeException(
        RuntimeFailure(
          code: RuntimeFailureCode.cancelled,
          message: 'Structured generation was cancelled.',
        ),
      );
    }

    if (failureToThrowOnGenerate != null) {
      _changeState(_activeHandles.isNotEmpty
          ? RuntimeState.modelReady
          : RuntimeState.ready);
      _eventController.add(
        GenerationFailed(
          instanceId: _instanceId!,
          timestamp: DateTime.now(),
          requestId: request.requestId,
          failure: failureToThrowOnGenerate!,
          traceId: request.traceContext.traceId,
        ),
      );
      throw RuntimeException(failureToThrowOnGenerate!);
    }

    final result = StructuredGenerationResult(
      requestId: request.requestId,
      model: request.model,
      rawContent: structuredResponse.toString(),
      parsedObject: structuredResponse,
      appliedMode: StructuredOutputMode.automatic,
      finishReason: GenerationFinishReason.completed,
      latency: stopwatch.elapsed,
    );

    _eventController.add(
      GenerationCompleted(
        instanceId: _instanceId!,
        timestamp: DateTime.now(),
        requestId: request.requestId,
        latency: stopwatch.elapsed,
        traceId: request.traceContext.traceId,
      ),
    );

    _changeState(_activeHandles.isNotEmpty
        ? RuntimeState.modelReady
        : RuntimeState.ready);
    return result;
  }

  @override
  Future<void> cancel(GenerationRequestId requestId) async {
    cancelCalls++;
    _ensureInitialized();

    if (throwOnCancellation) {
      throw const RuntimeException(
        RuntimeFailure(
          code: RuntimeFailureCode.cancellationUnsupported,
          message: 'Cancellation is unsupported by policy.',
        ),
      );
    }

    _cancelledRequestIds.add(requestId);
    if (_instanceId != null) {
      _eventController.add(
        GenerationCancelled(
          instanceId: _instanceId!,
          timestamp: DateTime.now(),
          requestId: requestId,
        ),
      );
    }
  }

  @override
  Future<RuntimeHealth> health() async {
    healthCalls++;
    _ensureInitialized();
    return RuntimeHealth(
      instanceId: _instanceId!,
      state: _state,
      responsive: true,
      observedAt: DateTime.now(),
      backend: RuntimeBackend.mock,
      activeGenerations: _activeGenerationRequests.length,
      loadedModelCount: _activeHandles.length,
    );
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
    if (_state == RuntimeState.disposed) return;

    if (_instanceId != null) {
      _eventController.add(
        RuntimeDisposing(
          instanceId: _instanceId!,
          timestamp: DateTime.now(),
        ),
      );
    }

    _activeHandles.clear();
    _activeGenerationRequests.clear();
    _cancelledRequestIds.clear();

    _changeState(RuntimeState.disposed);

    if (_instanceId != null && !_eventController.isClosed) {
      _eventController.add(
        RuntimeDisposed(
          instanceId: _instanceId!,
          timestamp: DateTime.now(),
        ),
      );
    }
    await _eventController.close();
  }

  void _ensureInitialized() {
    if (_state == RuntimeState.uninitialized) {
      throw const RuntimeException(
        RuntimeFailure(
          code: RuntimeFailureCode.invalidState,
          message: 'Runtime is uninitialized.',
        ),
      );
    }
  }

  void _validateHandle(ModelHandle handle) {
    if (handle.runtimeInstanceId != _instanceId ||
        !_activeHandles.contains(handle.id)) {
      throw const RuntimeException(
        RuntimeFailure(
          code: RuntimeFailureCode.invalidModelHandle,
          message: 'Model handle is invalid or belongs to another session.',
        ),
      );
    }
  }
}
