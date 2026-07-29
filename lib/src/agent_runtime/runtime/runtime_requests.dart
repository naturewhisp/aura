import 'package:meta/meta.dart';
import 'model_handle.dart';
import 'runtime_backend.dart';
import 'runtime_ids.dart';

/// Resource policy limits specified during runtime initialization.
@immutable
class RuntimeResourceLimits {
  final int? maxMemoryBytes;
  final int? maxGpuMemoryBytes;
  final int? maxCpuThreads;

  const RuntimeResourceLimits({
    this.maxMemoryBytes,
    this.maxGpuMemoryBytes,
    this.maxCpuThreads,
  });
}

/// Request parameters for initializing an [InferenceRuntime].
@immutable
class RuntimeInitializationRequest {
  final RuntimeInstanceId instanceId;
  final RuntimeBackendPreference backendPreference;
  final RuntimeResourceLimits resourceLimits;
  final Duration startupTimeout;
  final bool diagnosticsEnabled;
  final Map<String, String> adapterOptions;

  const RuntimeInitializationRequest({
    required this.instanceId,
    this.backendPreference = RuntimeBackendPreference.automatic,
    this.resourceLimits = const RuntimeResourceLimits(),
    this.startupTimeout = const Duration(seconds: 30),
    this.diagnosticsEnabled = true,
    this.adapterOptions = const {},
  });
}

/// Compatibility evaluation result for a resolved model artifact.
@immutable
class ModelRuntimeCompatibility {
  final bool compatible;
  final String? reason;

  const ModelRuntimeCompatibility({
    required this.compatible,
    this.reason,
  });
}

/// Resolved artifact description supplied to `loadModel()`.
@immutable
class ResolvedModelArtifact {
  final String modelVariantId;
  final Uri? localArtifactUri;
  final String sha256;
  final String format;
  final String quantization;
  final String architecture;
  final ModelRuntimeCompatibility compatibility;

  const ResolvedModelArtifact({
    required this.modelVariantId,
    required this.sha256,
    required this.format,
    required this.quantization,
    required this.architecture,
    required this.compatibility,
    this.localArtifactUri,
  });
}

/// Options governing native or sidecar model loading.
@immutable
class ModelLoadOptions {
  final int? contextSize;
  final int? gpuLayerCount;
  final int? cpuThreadCount;
  final int? batchSize;
  final bool? memoryMap;
  final bool? memoryLock;
  final bool allowFallback;
  final Map<String, Object?> adapterOptions;

  const ModelLoadOptions({
    this.contextSize,
    this.gpuLayerCount,
    this.cpuThreadCount,
    this.batchSize,
    this.memoryMap,
    this.memoryLock,
    this.allowFallback = true,
    this.adapterOptions = const {},
  });
}

/// Request payload for loading a model into an [InferenceRuntime].
@immutable
class ModelLoadRequest {
  final ModelLoadRequestId requestId;
  final ResolvedModelArtifact artifact;
  final String logicalModelId;
  final Set<ModelRole> roles;
  final ModelLoadOptions options;
  final Duration timeout;

  const ModelLoadRequest({
    required this.requestId,
    required this.artifact,
    required this.logicalModelId,
    required this.roles,
    this.options = const ModelLoadOptions(),
    this.timeout = const Duration(seconds: 60),
  });
}

/// Role of a message inside an inference context.
enum InferenceRole {
  system,
  user,
  assistant,
}

/// Single text message supplied in an inference request.
@immutable
class InferenceMessage {
  final InferenceRole role;
  final String content;

  const InferenceMessage({
    required this.role,
    required this.content,
  });
}

/// Policy for reasoning / thinking content handling in supporting models.
enum ThinkingPolicy {
  runtimeDefault,
  disabled,
  enabled,
}

/// Parameters for text generation requests.
@immutable
class GenerationParameters {
  final double temperature;
  final int maxOutputTokens;
  final double? topP;
  final int? topK;
  final double? repetitionPenalty;
  final int? seed;
  final ThinkingPolicy thinkingPolicy;
  final List<String> stopSequences;
  final Map<String, Object?> adapterOptions;

  const GenerationParameters({
    this.temperature = 0.7,
    this.maxOutputTokens = 256,
    this.topP,
    this.topK,
    this.repetitionPenalty,
    this.seed,
    this.thinkingPolicy = ThinkingPolicy.runtimeDefault,
    this.stopSequences = const [],
    this.adapterOptions = const {},
  });
}

/// Correlation context for logging and replay tracing.
@immutable
class InferenceTraceContext {
  final RuntimeTraceId traceId;
  final String sessionId;
  final int? gameplayTurnId;
  final String agentId;
  final String logicalModelId;
  final Map<String, String> tags;

  const InferenceTraceContext({
    required this.traceId,
    required this.sessionId,
    required this.agentId,
    required this.logicalModelId,
    this.gameplayTurnId,
    this.tags = const {},
  });
}

/// Request for plain text generation.
@immutable
class TextGenerationRequest {
  final GenerationRequestId requestId;
  final ModelHandle model;
  final List<InferenceMessage> messages;
  final GenerationParameters parameters;
  final Duration timeout;
  final InferenceTraceContext traceContext;

  const TextGenerationRequest({
    required this.requestId,
    required this.model,
    required this.messages,
    required this.traceContext,
    this.parameters = const GenerationParameters(),
    this.timeout = const Duration(seconds: 30),
  });
}

/// JSON Schema description for structured output generation.
@immutable
class JsonSchemaDocument {
  final String schemaId;
  final Map<String, Object?> document;
  final bool rejectUnknownProperties;

  const JsonSchemaDocument({
    required this.schemaId,
    required this.document,
    this.rejectUnknownProperties = true,
  });
}

/// Output mode for structured generation requests.
enum StructuredOutputMode {
  automatic,
  jsonSchema,
  grammar,
  promptConstrained,
}

/// Parameters for structured generation requests.
@immutable
class StructuredGenerationParameters {
  final double temperature;
  final int maxOutputTokens;
  final int? seed;
  final StructuredOutputMode mode;
  final ThinkingPolicy thinkingPolicy;
  final Map<String, Object?> adapterOptions;

  const StructuredGenerationParameters({
    this.temperature = 0.2,
    this.maxOutputTokens = 256,
    this.seed,
    this.mode = StructuredOutputMode.automatic,
    this.thinkingPolicy = ThinkingPolicy.runtimeDefault,
    this.adapterOptions = const {},
  });
}

/// Request for structured JSON generation constrained by schema.
@immutable
class StructuredGenerationRequest {
  final GenerationRequestId requestId;
  final ModelHandle model;
  final List<InferenceMessage> messages;
  final JsonSchemaDocument schema;
  final StructuredGenerationParameters parameters;
  final Duration timeout;
  final InferenceTraceContext traceContext;

  const StructuredGenerationRequest({
    required this.requestId,
    required this.model,
    required this.messages,
    required this.schema,
    required this.traceContext,
    this.parameters = const StructuredGenerationParameters(),
    this.timeout = const Duration(seconds: 30),
  });
}
