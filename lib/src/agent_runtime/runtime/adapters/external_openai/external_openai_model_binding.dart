import 'package:meta/meta.dart';
import '../../model_handle.dart';

/// Maps an A.U.R.A. logical model ID to an external server model ID.
@immutable
class ExternalOpenAiModelBinding {
  /// Logical application model ID (e.g. `'aura.evaluator.primary'`).
  final String logicalModelId;

  /// Physical server model ID exposed by the OpenAI-compatible endpoint (e.g. `'mistralai/ministral-3-3b'`).
  final String serverModelId;

  /// Semantic roles assigned to this binding.
  final Set<ModelRole> roles;

  const ExternalOpenAiModelBinding({
    required this.logicalModelId,
    required this.serverModelId,
    this.roles = const {ModelRole.evaluator, ModelRole.actor},
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExternalOpenAiModelBinding &&
          runtimeType == other.runtimeType &&
          logicalModelId == other.logicalModelId &&
          serverModelId == other.serverModelId;

  @override
  int get hashCode => Object.hash(logicalModelId, serverModelId);
}
