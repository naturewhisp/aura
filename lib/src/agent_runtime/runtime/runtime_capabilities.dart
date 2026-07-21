import 'package:meta/meta.dart';
import 'runtime_backend.dart';
import 'runtime_ids.dart';

/// Capabilities supported for text/structured generation.
enum GenerationCapability {
  text,
  structuredJson,
  tokenStreaming,
  cancellation,
  deterministicSeed,
  grammarConstraint,
  jsonSchemaConstraint,
  nativeReasoningField,
}

/// Capabilities supported for model lifecycle management.
enum ModelCapability {
  multipleLoadedModels,
  sequentialResidency,
  sharedModelAcrossRoles,
  gpuOffload,
  cpuExecution,
  contextResize,
  loRAAdapter,
  hotLoRASwap,
}

/// Discovered capabilities for an [InferenceRuntime] session.
@immutable
class RuntimeCapabilities {
  final RuntimeAdapterId adapterId;
  final String runtimeName;
  final String runtimeVersion;
  final String runtimeBuildId;
  final RuntimeBackend selectedBackend;
  final Set<GenerationCapability> generationCapabilities;
  final Set<ModelCapability> modelCapabilities;
  final int maxConcurrentGenerations;
  final int maxLoadedModels;
  final bool supportsCancellation;
  final bool supportsHealthCheck;
  final bool supportsTokenStreaming;
  final bool supportsGrammarConstraints;
  final bool supportsJsonSchema;
  final bool supportsLoRA;
  final Map<String, Object?> extensions;

  const RuntimeCapabilities({
    required this.adapterId,
    required this.runtimeName,
    required this.runtimeVersion,
    required this.runtimeBuildId,
    required this.selectedBackend,
    required this.generationCapabilities,
    required this.modelCapabilities,
    this.maxConcurrentGenerations = 1,
    this.maxLoadedModels = 1,
    this.supportsCancellation = true,
    this.supportsHealthCheck = true,
    this.supportsTokenStreaming = false,
    this.supportsGrammarConstraints = false,
    this.supportsJsonSchema = false,
    this.supportsLoRA = false,
    this.extensions = const {},
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RuntimeCapabilities &&
          runtimeType == other.runtimeType &&
          adapterId == other.adapterId &&
          runtimeName == other.runtimeName &&
          runtimeVersion == other.runtimeVersion &&
          runtimeBuildId == other.runtimeBuildId &&
          selectedBackend == other.selectedBackend &&
          maxConcurrentGenerations == other.maxConcurrentGenerations &&
          maxLoadedModels == other.maxLoadedModels &&
          supportsCancellation == other.supportsCancellation &&
          supportsHealthCheck == other.supportsHealthCheck &&
          supportsTokenStreaming == other.supportsTokenStreaming &&
          supportsGrammarConstraints == other.supportsGrammarConstraints &&
          supportsJsonSchema == other.supportsJsonSchema &&
          supportsLoRA == other.supportsLoRA;

  @override
  int get hashCode => Object.hash(
        adapterId,
        runtimeName,
        runtimeVersion,
        runtimeBuildId,
        selectedBackend,
        maxConcurrentGenerations,
        maxLoadedModels,
        supportsCancellation,
        supportsHealthCheck,
        supportsTokenStreaming,
        supportsGrammarConstraints,
        supportsJsonSchema,
        supportsLoRA,
      );

  @override
  String toString() =>
      'RuntimeCapabilities(adapterId: $adapterId, runtimeName: $runtimeName, backend: $selectedBackend)';
}
