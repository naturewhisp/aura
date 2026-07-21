/// Codes representing specific failures encountered during LLM output post-processing policy validation.
enum OutputPolicyFailureCode {
  /// The LLM produced an empty response or the content became empty after sanitization.
  emptyContent,

  /// The LLM output contained only reasoning/CoT artifacts with no usable diegetic dialogue.
  reasoningOnly,

  /// Generation was truncated due to max tokens without yielding any completed content.
  truncatedWithoutContent,

  /// The response contained forbidden character sets (e.g. CJK script hallucination).
  invalidCharacterSet,

  /// The candidate response repeats a line present in the conversation history.
  duplicateResponse,

  /// None of the 6 extraction strategies could isolate a valid diegetic response.
  noValidExtraction,
}

/// Typed, platform-neutral exception representing an output policy violation.
class OutputPolicyFailure implements Exception {
  final OutputPolicyFailureCode code;
  final String message;
  final Map<String, Object?> diagnostics;

  const OutputPolicyFailure({
    required this.code,
    required this.message,
    this.diagnostics = const {},
  });

  @override
  String toString() => 'OutputPolicyFailure($code): $message';
}
