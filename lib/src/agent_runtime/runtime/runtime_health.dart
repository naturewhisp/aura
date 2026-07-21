import 'package:meta/meta.dart';
import 'runtime_backend.dart';
import 'runtime_failure.dart';
import 'runtime_ids.dart';
import 'runtime_state.dart';

/// Resource utilization metrics for an active [InferenceRuntime].
@immutable
class RuntimeResourceSnapshot {
  final int? residentMemoryBytes;
  final int? deviceMemoryBytes;
  final double? cpuUtilization;
  final double? deviceUtilization;
  final double? temperatureCelsius;

  const RuntimeResourceSnapshot({
    this.residentMemoryBytes,
    this.deviceMemoryBytes,
    this.cpuUtilization,
    this.deviceUtilization,
    this.temperatureCelsius,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RuntimeResourceSnapshot &&
          runtimeType == other.runtimeType &&
          residentMemoryBytes == other.residentMemoryBytes &&
          deviceMemoryBytes == other.deviceMemoryBytes &&
          cpuUtilization == other.cpuUtilization &&
          deviceUtilization == other.deviceUtilization &&
          temperatureCelsius == other.temperatureCelsius;

  @override
  int get hashCode => Object.hash(
        residentMemoryBytes,
        deviceMemoryBytes,
        cpuUtilization,
        deviceUtilization,
        temperatureCelsius,
      );
}

/// Health and status snapshot for an [InferenceRuntime].
@immutable
class RuntimeHealth {
  final RuntimeInstanceId instanceId;
  final RuntimeState state;
  final bool responsive;
  final DateTime observedAt;
  final Duration? uptime;
  final int activeGenerations;
  final int loadedModelCount;
  final RuntimeBackend backend;
  final RuntimeResourceSnapshot? resources;
  final List<RuntimeWarning> warnings;
  final RuntimeFailure? lastFailure;

  const RuntimeHealth({
    required this.instanceId,
    required this.state,
    required this.responsive,
    required this.observedAt,
    required this.backend,
    this.uptime,
    this.activeGenerations = 0,
    this.loadedModelCount = 0,
    this.resources,
    this.warnings = const [],
    this.lastFailure,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RuntimeHealth &&
          runtimeType == other.runtimeType &&
          instanceId == other.instanceId &&
          state == other.state &&
          responsive == other.responsive &&
          backend == other.backend &&
          activeGenerations == other.activeGenerations &&
          loadedModelCount == other.loadedModelCount;

  @override
  int get hashCode => Object.hash(
        instanceId,
        state,
        responsive,
        backend,
        activeGenerations,
        loadedModelCount,
      );

  @override
  String toString() =>
      'RuntimeHealth(instanceId: ${instanceId.value}, state: $state, responsive: $responsive)';
}
