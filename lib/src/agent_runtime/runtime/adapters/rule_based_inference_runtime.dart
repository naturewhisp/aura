import 'dart:async';
import 'dart:convert';
import '../../bridges/rule_based_evaluator_bridge.dart';
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

/// Platform-neutral adapter around [RuleBasedEvaluatorBridge] implementing [InferenceRuntime].
///
/// Provides deterministic offline evaluation without requiring a real neural backend.
class RuleBasedInferenceRuntime implements InferenceRuntime {
  final RuleBasedEvaluatorBridge _bridge;
  final StreamController<RuntimeEvent> _eventController =
      StreamController<RuntimeEvent>.broadcast();

  RuntimeState _state = RuntimeState.uninitialized;
  RuntimeInstanceId? _instanceId;
  final Set<ModelHandleId> _activeHandles = {};
  int _activeGenerationsCount = 0;

  RuleBasedInferenceRuntime({
    RuleBasedEvaluatorBridge bridge = const RuleBasedEvaluatorBridge(),
  }) : _bridge = bridge;

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

    const capabilities = RuntimeCapabilities(
      adapterId: RuntimeAdapterId('rule_based_deterministic'),
      runtimeName: 'Rule-Based Deterministic Engine',
      runtimeVersion: '1.0.0',
      runtimeBuildId: 'offline-rule-based-v1',
      selectedBackend: RuntimeBackend.deterministic,
      generationCapabilities: {
        GenerationCapability.text,
        GenerationCapability.structuredJson,
        GenerationCapability.deterministicSeed,
      },
      modelCapabilities: {
        ModelCapability.sharedModelAcrossRoles,
        ModelCapability.cpuExecution,
      },
      maxConcurrentGenerations: 1,
      maxLoadedModels: 10,
      supportsCancellation: false,
      supportsHealthCheck: true,
      supportsTokenStreaming: false,
      supportsGrammarConstraints: false,
      supportsJsonSchema: false,
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
    _eventController.add(
      ModelLoadStarted(
        instanceId: _instanceId!,
        timestamp: DateTime.now(),
        loadRequestId: request.requestId,
        logicalModelId: request.logicalModelId,
      ),
    );

    final handleId = ModelHandleId(
        'handle-${request.logicalModelId}-${DateTime.now().millisecondsSinceEpoch}');
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
    _ensureInitializedAndNotDisposed();
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
    _ensureInitializedAndNotDisposed();
    _validateHandle(request.model);

    _activeGenerationsCount++;
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
    try {
      const fallbackText =
          "PANOPTICON: Sistema deterministico in esecuzione offline.";
      stopwatch.stop();

      final result = TextGenerationResult(
        requestId: request.requestId,
        model: request.model,
        content: fallbackText,
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

      return result;
    } catch (e, st) {
      stopwatch.stop();
      final failure = RuntimeFailure(
        code: RuntimeFailureCode.generationFailed,
        message: 'Rule-based text generation failed: $e',
      );
      _eventController.add(
        GenerationFailed(
          instanceId: _instanceId!,
          timestamp: DateTime.now(),
          requestId: request.requestId,
          failure: failure,
          traceId: request.traceContext.traceId,
        ),
      );
      throw RuntimeException(failure, cause: e, stackTrace: st);
    } finally {
      _activeGenerationsCount--;
      if (_activeGenerationsCount == 0 && _state != RuntimeState.disposed) {
        _changeState(
          _activeHandles.isNotEmpty
              ? RuntimeState.modelReady
              : RuntimeState.ready,
          traceId: request.traceContext.traceId,
        );
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
    try {
      final legacyMessages = request.messages
          .map((m) => {'role': m.role.name, 'content': m.content})
          .toList();

      final parsedMap = await _bridge.generateStructured(
        modelId: request.model.logicalModelId,
        messages: legacyMessages,
        schema: request.schema.document,
      );

      stopwatch.stop();

      final result = StructuredGenerationResult(
        requestId: request.requestId,
        model: request.model,
        rawContent: jsonEncode(parsedMap),
        parsedObject: parsedMap,
        appliedMode: StructuredOutputMode.promptConstrained,
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

      return result;
    } catch (e, st) {
      stopwatch.stop();
      final failure = RuntimeFailure(
        code: RuntimeFailureCode.generationFailed,
        message: 'Rule-based structured generation failed: $e',
      );
      _eventController.add(
        GenerationFailed(
          instanceId: _instanceId!,
          timestamp: DateTime.now(),
          requestId: request.requestId,
          failure: failure,
          traceId: request.traceContext.traceId,
        ),
      );
      throw RuntimeException(failure, cause: e, stackTrace: st);
    } finally {
      _activeGenerationsCount--;
      if (_activeGenerationsCount == 0 && _state != RuntimeState.disposed) {
        _changeState(
          _activeHandles.isNotEmpty
              ? RuntimeState.modelReady
              : RuntimeState.ready,
          traceId: request.traceContext.traceId,
        );
      }
    }
  }

  @override
  Future<void> cancel(GenerationRequestId requestId) async {
    _ensureInitializedAndNotDisposed();
    throw const RuntimeException(
      RuntimeFailure(
        code: RuntimeFailureCode.cancellationUnsupported,
        message: 'Cancellation is unsupported by RuleBasedInferenceRuntime.',
        suggestedAction: RuntimeRecoveryAction.none,
      ),
    );
  }

  @override
  Future<RuntimeHealth> health() async {
    _ensureInitializedAndNotDisposed();
    return RuntimeHealth(
      instanceId: _instanceId!,
      state: _state,
      responsive: true,
      observedAt: DateTime.now(),
      backend: RuntimeBackend.deterministic,
      activeGenerations: _activeGenerationsCount,
      loadedModelCount: _activeHandles.length,
    );
  }

  @override
  Future<void> dispose() async {
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
    _activeGenerationsCount = 0;
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

  void _ensureInitializedAndNotDisposed() {
    if (_state == RuntimeState.disposed) {
      throw const RuntimeException(
        RuntimeFailure(
          code: RuntimeFailureCode.disposed,
          message: 'Runtime is disposed.',
        ),
      );
    }
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
