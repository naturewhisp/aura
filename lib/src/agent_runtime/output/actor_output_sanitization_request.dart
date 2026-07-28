/// Input parameters for [ActorOutputSanitizer].
class ActorOutputSanitizationRequest {
  final String content;
  final String reasoningContent;
  final String finishReason;
  final int requestedMaxTokens;
  final List<String> conversationHistory;

  /// Indica se il thinking (CoT nativo) era abilitato nella richiesta originale.
  ///
  /// Quando [thinkingRequested] è `false`, il sanitizer deve rifiutare qualsiasi
  /// tentativo di estrarre dialogo da [reasoningContent]: la presenza di reasoning
  /// con content vuoto è un errore del modello, non un caso da recuperare.
  final bool thinkingRequested;

  const ActorOutputSanitizationRequest({
    required this.content,
    this.reasoningContent = '',
    this.finishReason = '',
    this.requestedMaxTokens = 150,
    this.conversationHistory = const [],
    this.thinkingRequested = true,
  });
}
