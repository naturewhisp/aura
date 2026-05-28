import '../inference_bridge.dart';

/// An offline mock implementation of [InferenceBridge] returning predefined stubs.
class MockInferenceBridge implements InferenceBridge {
  String mockTextResponse;
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
}
