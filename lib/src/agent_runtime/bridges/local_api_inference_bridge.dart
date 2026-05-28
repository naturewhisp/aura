import 'dart:convert';
import 'package:http/http.dart' as http;
import '../inference_bridge.dart';

/// Active HTTP bridge communicating with the local LM Studio API server.
class LocalApiInferenceBridge implements InferenceBridge {
  final String baseUrl;

  const LocalApiInferenceBridge({
    this.baseUrl = "http://127.0.0.1:1234",
  });

  @override
  Future<String> generateText({
    required String modelId,
    required List<Map<String, String>> messages,
    double temperature = 0.7,
    int maxTokens = 150,
  }) async {
    final url = Uri.parse("$baseUrl/v1/chat/completions");
    final body = jsonEncode({
      "model": modelId,
      "messages": messages,
      "temperature": temperature,
      "max_tokens": maxTokens,
    });

    final response = await http.post(
      url,
      headers: {"Content-Type": "application/json"},
      body: body,
    ).timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception("Failed to generate text: Status ${response.statusCode}, Body: ${response.body}");
    }

    final data = jsonDecode(response.body);
    final choice = data['choices']?[0];
    final message = choice?['message'] ?? const {};
    
    final content = message['content'] as String? ?? '';
    final reasoning = message['reasoning_content'] as String? ?? '';

    // Standard fallback to reasoning if content is empty (e.g. for reasoning models)
    return content.isNotEmpty ? content : reasoning;
  }

  @override
  Future<Map<String, dynamic>> generateStructured({
    required String modelId,
    required List<Map<String, String>> messages,
    required Map<String, dynamic> schema,
    double temperature = 0.0,
  }) async {
    final url = Uri.parse("$baseUrl/v1/chat/completions");
    
    final body = jsonEncode({
      "model": modelId,
      "messages": messages,
      "temperature": temperature,
      "response_format": {
        "type": "json_schema",
        "json_schema": {
          "name": "structured_schema",
          "strict": true,
          "schema": schema,
        }
      }
    });

    final response = await http.post(
      url,
      headers: {"Content-Type": "application/json"},
      body: body,
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception("Failed to generate structured output: Status ${response.statusCode}, Body: ${response.body}");
    }

    final data = jsonDecode(response.body);
    final choice = data['choices']?[0];
    final message = choice?['message'] ?? const {};
    final rawJson = message['content'] as String? ?? '';

    return jsonDecode(rawJson) as Map<String, dynamic>;
  }
}
