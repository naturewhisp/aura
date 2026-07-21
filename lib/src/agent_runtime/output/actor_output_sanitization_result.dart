import 'actor_output_extraction_strategy.dart';

/// Output result produced by [ActorOutputSanitizer].
class ActorOutputSanitizationResult {
  final String content;
  final ActorOutputExtractionStrategy extractionStrategy;
  final bool usedReasoningFallback;
  final List<String> warnings;

  const ActorOutputSanitizationResult({
    required this.content,
    required this.extractionStrategy,
    this.usedReasoningFallback = false,
    this.warnings = const [],
  });
}
