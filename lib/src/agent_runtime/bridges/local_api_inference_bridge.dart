import 'dart:convert';
import 'package:meta/meta.dart';
import 'package:http/http.dart' as http;
import '../inference_bridge.dart';
import '../output/actor_output_sanitizer.dart';
import '../output/actor_output_sanitization_request.dart';
import '../output/output_policy_failure.dart';

/// Bridge d'inferenza attivo via HTTP che comunica con il server API locale di LM Studio.
///
/// Gestisce la comunicazione di rete, l'inoltro dei parametri di inferenza (incluso il thinking),
/// e la post-elaborazione/pulizia avanzata delle risposte tramite [ActorOutputSanitizer].
class LocalApiInferenceBridge implements InferenceBridge {
  /// L'URL di base del server API locale (es. 'http://127.0.0.1:1234').
  final String baseUrl;

  /// Il componente di sanitizzazione e validazione dell'output LLM.
  final ActorOutputSanitizer sanitizer;

  /// Il timeout a livello di trasporto HTTP. Rappresenta una protezione ultima della connessione,
  /// differente dal timeout applicativo degli agenti.
  static const Duration httpTransportTimeout = Duration(seconds: 300);

  const LocalApiInferenceBridge({
    this.baseUrl = "http://127.0.0.1:1234",
    this.sanitizer = const ActorOutputSanitizer(),
  });

  @override
  Future<String> generateText({
    required String modelId,
    required List<Map<String, String>> messages,
    double temperature = 0.7,
    int maxTokens = 150,
    bool? thinking,
  }) async {
    final url = Uri.parse("$baseUrl/v1/chat/completions");
    final Map<String, dynamic> requestBody = {
      "model": modelId,
      "messages": messages,
      "temperature": temperature,
      "max_tokens": maxTokens,
    };

    if (thinking != null) {
      requestBody["enable_thinking"] = thinking;
      requestBody["chat_template_kwargs"] = {
        "enable_thinking": thinking,
      };
      requestBody["thinking"] = {
        "type": thinking ? "enabled" : "disabled",
      };
    }

    final body = jsonEncode(requestBody);

    final response = await http
        .post(
          url,
          headers: {"Content-Type": "application/json"},
          body: body,
        )
        .timeout(httpTransportTimeout);

    if (response.statusCode != 200) {
      throw Exception(
          "Impossibile generare testo: Status ${response.statusCode}, Body: ${response.body}");
    }

    final data = jsonDecode(response.body);
    final choice = data['choices']?[0];
    final message = choice?['message'] ?? const {};
    final finishReason = choice?['finish_reason'] as String? ?? '';

    final content = message['content'] as String? ?? '';
    final reasoning = message['reasoning_content'] as String? ?? '';

    final conversationHistory =
        messages.map((m) => m['content']?.trim() ?? '').toList();

    try {
      final result = sanitizer.sanitize(
        ActorOutputSanitizationRequest(
          content: content,
          reasoningContent: reasoning,
          finishReason: finishReason,
          requestedMaxTokens: maxTokens,
          conversationHistory: conversationHistory,
        ),
      );
      return result.content;
    } on OutputPolicyFailure {
      rethrow;
    } catch (e) {
      rethrow;
    }
  }

  @visibleForTesting
  String cleanLLMResponseForTesting(String response,
      {bool isNativeReasoningPresent = false}) {
    final result = sanitizer.sanitize(
      ActorOutputSanitizationRequest(
        content: response,
        reasoningContent: isNativeReasoningPresent ? 'native' : '',
      ),
    );
    return result.content;
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

    final response = await http
        .post(
          url,
          headers: {"Content-Type": "application/json"},
          body: body,
        )
        .timeout(httpTransportTimeout);

    if (response.statusCode != 200) {
      throw Exception(
          "Impossibile generare output strutturato: Status ${response.statusCode}, Body: ${response.body}");
    }

    final data = jsonDecode(response.body);
    final choice = data['choices']?[0];
    final message = choice?['message'] ?? const {};
    final rawJson = message['content'] as String? ?? '';

    return jsonDecode(rawJson) as Map<String, dynamic>;
  }

  @override
  Future<List<String>> discoverModels() async {
    try {
      final response = await http
          .get(Uri.parse("$baseUrl/v1/models"))
          .timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final modelsList = data['data'] as List?;
        if (modelsList != null) {
          return modelsList
              .map((m) => m['id'] as String? ?? '')
              .where((id) => id.isNotEmpty)
              .toList();
        }
      }
    } catch (_) {
      // Fallback in caso di errori di connessione o timeout
    }
    return const [];
  }
}
