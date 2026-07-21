import 'package:meta/meta.dart';
import 'runtime_ids.dart';

/// Role assigned to a model within the agent runtime architecture.
enum ModelRole {
  evaluator,
  actor,
  shared,
  memory,
  testing,
}

/// Represents a model loaded into an active [InferenceRuntime] session.
@immutable
class ModelHandle {
  final ModelHandleId id;
  final RuntimeInstanceId runtimeInstanceId;
  final String logicalModelId;
  final String modelVariantId;
  final Set<ModelRole> roles;
  final DateTime loadedAt;
  final Map<String, Object?> runtimeMetadata;

  const ModelHandle({
    required this.id,
    required this.runtimeInstanceId,
    required this.logicalModelId,
    required this.modelVariantId,
    required this.roles,
    required this.loadedAt,
    this.runtimeMetadata = const {},
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ModelHandle &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          runtimeInstanceId == other.runtimeInstanceId;

  @override
  int get hashCode => Object.hash(id, runtimeInstanceId);

  @override
  String toString() =>
      'ModelHandle(id: ${id.value}, logicalModelId: $logicalModelId, roles: $roles)';
}
