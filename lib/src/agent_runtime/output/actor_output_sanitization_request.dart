/// Input parameters for [ActorOutputSanitizer].
class ActorOutputSanitizationRequest {
  final String content;
  final String reasoningContent;
  final String finishReason;
  final int requestedMaxTokens;
  final List<String> conversationHistory;

  const ActorOutputSanitizationRequest({
    required this.content,
    this.reasoningContent = '',
    this.finishReason = '',
    this.requestedMaxTokens = 150,
    this.conversationHistory = const [],
  });
}
