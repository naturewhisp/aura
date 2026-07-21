import 'package:meta/meta.dart';
import 'model_handle.dart';
import 'runtime_failure.dart';
import 'runtime_ids.dart';
import 'runtime_state.dart';

/// Sealed hierarchy of diagnostic and orchestration events emitted by an [InferenceRuntime].
@immutable
sealed class RuntimeEvent {
  final RuntimeInstanceId instanceId;
  final DateTime timestamp;
  final RuntimeTraceId? traceId;

  const RuntimeEvent({
    required this.instanceId,
    required this.timestamp,
    this.traceId,
  });
}

class RuntimeStateChanged extends RuntimeEvent {
  final RuntimeState previousState;
  final RuntimeState newState;

  const RuntimeStateChanged({
    required super.instanceId,
    required super.timestamp,
    required this.previousState,
    required this.newState,
    super.traceId,
  });
}

class RuntimeInitialized extends RuntimeEvent {
  final String adapterName;
  final String runtimeVersion;

  const RuntimeInitialized({
    required super.instanceId,
    required super.timestamp,
    required this.adapterName,
    required this.runtimeVersion,
    super.traceId,
  });
}

class RuntimeInitializationFailed extends RuntimeEvent {
  final RuntimeFailure failure;

  const RuntimeInitializationFailed({
    required super.instanceId,
    required super.timestamp,
    required this.failure,
    super.traceId,
  });
}

class RuntimeCrashed extends RuntimeEvent {
  final RuntimeFailure failure;

  const RuntimeCrashed({
    required super.instanceId,
    required super.timestamp,
    required this.failure,
    super.traceId,
  });
}

class RuntimeRecoveryStarted extends RuntimeEvent {
  final String reason;

  const RuntimeRecoveryStarted({
    required super.instanceId,
    required super.timestamp,
    required this.reason,
    super.traceId,
  });
}

class RuntimeRecoveryCompleted extends RuntimeEvent {
  final RuntimeState recoveredState;

  const RuntimeRecoveryCompleted({
    required super.instanceId,
    required super.timestamp,
    required this.recoveredState,
    super.traceId,
  });
}

class ModelLoadStarted extends RuntimeEvent {
  final ModelLoadRequestId loadRequestId;
  final String logicalModelId;

  const ModelLoadStarted({
    required super.instanceId,
    required super.timestamp,
    required this.loadRequestId,
    required this.logicalModelId,
    super.traceId,
  });
}

class ModelLoadCompleted extends RuntimeEvent {
  final ModelLoadRequestId loadRequestId;
  final ModelHandle handle;

  const ModelLoadCompleted({
    required super.instanceId,
    required super.timestamp,
    required this.loadRequestId,
    required this.handle,
    super.traceId,
  });
}

class ModelLoadFailed extends RuntimeEvent {
  final ModelLoadRequestId loadRequestId;
  final RuntimeFailure failure;

  const ModelLoadFailed({
    required super.instanceId,
    required super.timestamp,
    required this.loadRequestId,
    required this.failure,
    super.traceId,
  });
}

class ModelUnloadStarted extends RuntimeEvent {
  final ModelHandle handle;

  const ModelUnloadStarted({
    required super.instanceId,
    required super.timestamp,
    required this.handle,
    super.traceId,
  });
}

class ModelUnloadCompleted extends RuntimeEvent {
  final ModelHandleId handleId;

  const ModelUnloadCompleted({
    required super.instanceId,
    required super.timestamp,
    required this.handleId,
    super.traceId,
  });
}

class GenerationQueued extends RuntimeEvent {
  final GenerationRequestId requestId;

  const GenerationQueued({
    required super.instanceId,
    required super.timestamp,
    required this.requestId,
    super.traceId,
  });
}

class GenerationStarted extends RuntimeEvent {
  final GenerationRequestId requestId;
  final ModelHandle handle;

  const GenerationStarted({
    required super.instanceId,
    required super.timestamp,
    required this.requestId,
    required this.handle,
    super.traceId,
  });
}

class GenerationCompleted extends RuntimeEvent {
  final GenerationRequestId requestId;
  final Duration latency;

  const GenerationCompleted({
    required super.instanceId,
    required super.timestamp,
    required this.requestId,
    required this.latency,
    super.traceId,
  });
}

class GenerationCancelled extends RuntimeEvent {
  final GenerationRequestId requestId;

  const GenerationCancelled({
    required super.instanceId,
    required super.timestamp,
    required this.requestId,
    super.traceId,
  });
}

class GenerationTimedOut extends RuntimeEvent {
  final GenerationRequestId requestId;

  const GenerationTimedOut({
    required super.instanceId,
    required super.timestamp,
    required this.requestId,
    super.traceId,
  });
}

class GenerationFailed extends RuntimeEvent {
  final GenerationRequestId requestId;
  final RuntimeFailure failure;

  const GenerationFailed({
    required super.instanceId,
    required super.timestamp,
    required this.requestId,
    required this.failure,
    super.traceId,
  });
}

class RuntimeWarningEmitted extends RuntimeEvent {
  final RuntimeWarning warning;

  const RuntimeWarningEmitted({
    required super.instanceId,
    required super.timestamp,
    required this.warning,
    super.traceId,
  });
}

class RuntimeDisposing extends RuntimeEvent {
  const RuntimeDisposing({
    required super.instanceId,
    required super.timestamp,
    super.traceId,
  });
}

class RuntimeDisposed extends RuntimeEvent {
  const RuntimeDisposed({
    required super.instanceId,
    required super.timestamp,
    super.traceId,
  });
}
