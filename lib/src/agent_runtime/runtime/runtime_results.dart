import 'package:meta/meta.dart';
import 'model_handle.dart';
import 'runtime_failure.dart';
import 'runtime_ids.dart';
import 'runtime_requests.dart';

/// Reason why a generation request completed.
enum GenerationFinishReason {
  completed,
  stopSequence,
  maxTokens,
  cancelled,
  timeout,
  contentRejected,
  backendError,
}

/// Token usage metadata returned by an inference adapter.
@immutable
class GenerationUsage {
  final int? inputTokens;
  final int? outputTokens;
  final int? reasoningTokens;
  final int? cachedInputTokens;

  const GenerationUsage({
    this.inputTokens,
    this.outputTokens,
    this.reasoningTokens,
    this.cachedInputTokens,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GenerationUsage &&
          runtimeType == other.runtimeType &&
          inputTokens == other.inputTokens &&
          outputTokens == other.outputTokens &&
          reasoningTokens == other.reasoningTokens &&
          cachedInputTokens == other.cachedInputTokens;

  @override
  int get hashCode => Object.hash(
        inputTokens,
        outputTokens,
        reasoningTokens,
        cachedInputTokens,
      );
}

/// Result returned by `generateText()`.
@immutable
class TextGenerationResult {
  final GenerationRequestId requestId;
  final ModelHandle model;
  final String content;
  final String? reasoningContent;
  final GenerationFinishReason finishReason;
  final GenerationUsage usage;
  final Duration latency;
  final List<RuntimeWarning> warnings;
  final Map<String, Object?> adapterMetadata;

  const TextGenerationResult({
    required this.requestId,
    required this.model,
    required this.content,
    required this.finishReason,
    this.reasoningContent,
    this.usage = const GenerationUsage(),
    this.latency = Duration.zero,
    this.warnings = const [],
    this.adapterMetadata = const {},
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TextGenerationResult &&
          runtimeType == other.runtimeType &&
          requestId == other.requestId &&
          model == other.model &&
          content == other.content &&
          reasoningContent == other.reasoningContent &&
          finishReason == other.finishReason;

  @override
  int get hashCode =>
      Object.hash(requestId, model, content, reasoningContent, finishReason);
}

/// Result returned by `generateStructured()`.
@immutable
class StructuredGenerationResult {
  final GenerationRequestId requestId;
  final ModelHandle model;
  final String rawContent;
  final Map<String, Object?>? parsedObject;
  final StructuredOutputMode appliedMode;
  final GenerationFinishReason finishReason;
  final GenerationUsage usage;
  final Duration latency;
  final List<RuntimeWarning> warnings;
  final Map<String, Object?> adapterMetadata;

  const StructuredGenerationResult({
    required this.requestId,
    required this.model,
    required this.rawContent,
    required this.appliedMode,
    required this.finishReason,
    this.parsedObject,
    this.usage = const GenerationUsage(),
    this.latency = Duration.zero,
    this.warnings = const [],
    this.adapterMetadata = const {},
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StructuredGenerationResult &&
          runtimeType == other.runtimeType &&
          requestId == other.requestId &&
          model == other.model &&
          rawContent == other.rawContent &&
          appliedMode == other.appliedMode &&
          finishReason == other.finishReason;

  @override
  int get hashCode =>
      Object.hash(requestId, model, rawContent, appliedMode, finishReason);
}
