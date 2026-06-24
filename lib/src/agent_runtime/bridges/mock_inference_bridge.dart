import '../inference_bridge.dart';

/// Implementazione mock offline di [InferenceBridge] che restituisce risposte predefinite (stub).
///
/// Utilizzata principalmente per scopi di test unitari, test di integrazione offline e simulazioni.
class MockInferenceBridge implements InferenceBridge {
  /// Risposta testuale fittizia restituita da [generateText].
  String mockTextResponse;

  /// Risposta strutturata fittizia restituita da [generateStructured].
  Map<String, dynamic> mockStructuredResponse;

  MockInferenceBridge({
    this.mockTextResponse = "I am Panopticon. State your purpose.",
    this.mockStructuredResponse = const {},
  });

  @override
  Future<String> generateText({
    required String modelId,
    required List<Map<String, String>> messages,
    double temperature = 0.7,
    int maxTokens = 150,
    bool? thinking,
  }) async {
    return mockTextResponse;
  }

  @override
  Future<Map<String, dynamic>> generateStructured({
    required String modelId,
    required List<Map<String, String>> messages,
    required Map<String, dynamic> schema,
    double temperature = 0.0,
  }) async {
    return mockStructuredResponse;
  }

  @override
  Future<List<String>> discoverModels() async {
    return const ["mistralai/ministral-3-3b", "qwen/qwen3.5-9b"];
  }
}


