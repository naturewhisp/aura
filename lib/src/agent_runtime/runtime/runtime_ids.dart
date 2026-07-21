import 'package:meta/meta.dart';

/// Identifier for a single generation request submitted to an [InferenceRuntime].
@immutable
class GenerationRequestId {
  final String value;

  const GenerationRequestId(this.value);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GenerationRequestId &&
          runtimeType == other.runtimeType &&
          value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'GenerationRequestId($value)';
}

/// Trace context identifier for diagnostic correlation across logs and replay.
@immutable
class RuntimeTraceId {
  final String value;

  const RuntimeTraceId(this.value);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RuntimeTraceId &&
          runtimeType == other.runtimeType &&
          value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'RuntimeTraceId($value)';
}

/// Unique session identifier for a specific runtime instance.
@immutable
class RuntimeInstanceId {
  final String value;

  const RuntimeInstanceId(this.value);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RuntimeInstanceId &&
          runtimeType == other.runtimeType &&
          value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'RuntimeInstanceId($value)';
}

/// Unique identifier for a loaded model handle.
@immutable
class ModelHandleId {
  final String value;

  const ModelHandleId(this.value);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ModelHandleId &&
          runtimeType == other.runtimeType &&
          value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'ModelHandleId($value)';
}

/// Identifier for a model load request.
@immutable
class ModelLoadRequestId {
  final String value;

  const ModelLoadRequestId(this.value);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ModelLoadRequestId &&
          runtimeType == other.runtimeType &&
          value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'ModelLoadRequestId($value)';
}

/// Identifier for a runtime adapter implementation.
@immutable
class RuntimeAdapterId {
  final String value;

  const RuntimeAdapterId(this.value);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RuntimeAdapterId &&
          runtimeType == other.runtimeType &&
          value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'RuntimeAdapterId($value)';
}
