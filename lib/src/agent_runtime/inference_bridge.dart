/// Abstract interface wrapping LLM chat completions and structured outputs.
abstract class InferenceBridge {
  /// Generates a text response from the model based on messages.
  Future<String> generateText({
    required String modelId,
    required List<Map<String, String>> messages,
    double temperature = 0.7,
    int maxTokens = 150,
    bool? thinking,
  });

  /// Generates a structured JSON object matching the requested schema.
  Future<Map<String, dynamic>> generateStructured({
    required String modelId,
    required List<Map<String, String>> messages,
    required Map<String, dynamic> schema,
    double temperature = 0.0,
  });
}
