import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import 'external_openai_configuration.dart';

/// Immutable HTTP-level response wrapper for external OpenAI-compatible requests.
@immutable
class ExternalOpenAiResponse {
  final int statusCode;
  final String body;
  final Map<String, String> headers;

  const ExternalOpenAiResponse({
    required this.statusCode,
    required this.body,
    this.headers = const {},
  });
}

/// Abstract transport client interface for external OpenAI-compatible communication.
abstract interface class ExternalOpenAiClient {
  /// Posts a chat completions request and returns raw HTTP response data.
  Future<ExternalOpenAiResponse> chatCompletions(
    Map<String, dynamic> payload, {
    String? requestId,
  });

  /// Queries the `/v1/models` endpoint for available model IDs.
  Future<List<String>> discoverModels();

  /// Probes the server health endpoint.
  Future<bool> checkHealth();

  /// Requests HTTP-level cancellation for [requestId] if supported by transport.
  Future<void> cancel(String requestId);

  /// Closes underlying client resources.
  Future<void> close();
}

/// Production transport implementation backed by `package:http`.
class HttpExternalOpenAiClient implements ExternalOpenAiClient {
  final ExternalOpenAiConfiguration configuration;
  final http.Client _httpClient;

  HttpExternalOpenAiClient({
    required this.configuration,
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  Map<String, String> get _defaultHeaders {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      ...configuration.staticHeaders,
    };
    if (configuration.apiKey != null && configuration.apiKey!.isNotEmpty) {
      headers['Authorization'] = 'Bearer ${configuration.apiKey}';
    }
    return headers;
  }

  @override
  Future<ExternalOpenAiResponse> chatCompletions(
    Map<String, dynamic> payload, {
    String? requestId,
  }) async {
    final uri = configuration.baseUri.replace(
      path: configuration.chatCompletionsEndpointPath,
    );

    final response = await _httpClient
        .post(
          uri,
          headers: _defaultHeaders,
          body: jsonEncode(payload),
        )
        .timeout(configuration.transportTimeout);

    return ExternalOpenAiResponse(
      statusCode: response.statusCode,
      body: response.body,
      headers: response.headers,
    );
  }

  @override
  Future<List<String>> discoverModels() async {
    if (!configuration.supportsDiscovery) return const [];
    try {
      final uri = configuration.baseUri.replace(
        path: configuration.modelsEndpointPath,
      );
      final response = await _httpClient
          .get(uri, headers: _defaultHeaders)
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = data['data'] as List?;
        if (list != null) {
          return list
              .map((m) => m['id'] as String? ?? '')
              .where((id) => id.isNotEmpty)
              .toList();
        }
      }
    } catch (_) {}
    return const [];
  }

  @override
  Future<bool> checkHealth() async {
    try {
      final uri = configuration.baseUri.replace(
        path: configuration.healthEndpointPath,
      );
      final response = await _httpClient
          .get(uri, headers: _defaultHeaders)
          .timeout(const Duration(seconds: 4));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> cancel(String requestId) async {
    // HTTP/1.1 transport cancellation per request ID is handled at the adapter cancellation registry level.
  }

  @override
  Future<void> close() async {
    _httpClient.close();
  }
}

/// Pending request tracked by [FakeExternalOpenAiClient] when `autoCompleteRequests` is false.
class PendingFakeExternalRequest {
  final String? requestId;
  final Map<String, dynamic> payload;
  final Completer<ExternalOpenAiResponse> completer;

  PendingFakeExternalRequest({
    required this.requestId,
    required this.payload,
    required this.completer,
  });
}

/// Deterministic fake client for offline contract and unit testing.
class FakeExternalOpenAiClient implements ExternalOpenAiClient {
  bool healthy;
  List<String> availableModels;
  String defaultResponseContent;
  String defaultStructuredResponseContent;
  String? defaultReasoningContent;
  String defaultFinishReason;
  int statusCodeToReturn;
  String? errorBodyToReturn;
  bool autoCompleteRequests;

  final Set<String> cancelledRequestIds = {};
  final List<PendingFakeExternalRequest> pendingRequests = [];

  int chatCompletionsCalls = 0;
  int discoverModelsCalls = 0;
  int checkHealthCalls = 0;
  int cancelCalls = 0;
  bool isClosed = false;

  FakeExternalOpenAiClient({
    this.healthy = true,
    this.availableModels = const [
      'aura.evaluator.primary',
      'aura.actor.primary',
      'mistralai/ministral-3-3b',
      'qwen/qwen3.5-9b'
    ],
    this.defaultResponseContent = 'Fake model text response',
    this.defaultStructuredResponseContent =
        '{"mockKey": "mockValue", "key": "value"}',
    this.defaultReasoningContent,
    this.defaultFinishReason = 'stop',
    this.statusCodeToReturn = 200,
    this.errorBodyToReturn,
    this.autoCompleteRequests = true,
  });

  ExternalOpenAiResponse _buildResponse(Map<String, dynamic> payload,
      {String? requestId}) {
    if (requestId != null && cancelledRequestIds.contains(requestId)) {
      return ExternalOpenAiResponse(
        statusCode: 499,
        body: jsonEncode({'error': 'Request cancelled by client'}),
      );
    }

    if (statusCodeToReturn != 200) {
      return ExternalOpenAiResponse(
        statusCode: statusCodeToReturn,
        body: errorBodyToReturn ??
            jsonEncode({'error': 'Server error $statusCodeToReturn'}),
      );
    }

    final isStructured = payload.containsKey('response_format');
    final messageObj = <String, dynamic>{
      'role': 'assistant',
      'content': isStructured
          ? defaultStructuredResponseContent
          : defaultResponseContent,
    };
    if (defaultReasoningContent != null) {
      messageObj['reasoning_content'] = defaultReasoningContent;
    }

    final body = jsonEncode({
      'id': 'fake-chatcmpl-123',
      'object': 'chat.completion',
      'created': 1780000000,
      'model': payload['model'] ?? 'fake-model',
      'choices': [
        {
          'index': 0,
          'message': messageObj,
          'finish_reason': defaultFinishReason,
        }
      ],
      'usage': {
        'prompt_tokens': 12,
        'completion_tokens': 24,
        'total_tokens': 36,
      }
    });

    return ExternalOpenAiResponse(statusCode: 200, body: body);
  }

  @override
  Future<ExternalOpenAiResponse> chatCompletions(
    Map<String, dynamic> payload, {
    String? requestId,
  }) {
    chatCompletionsCalls++;
    if (autoCompleteRequests) {
      return Future.value(_buildResponse(payload, requestId: requestId));
    } else {
      final completer = Completer<ExternalOpenAiResponse>();
      pendingRequests.add(
        PendingFakeExternalRequest(
          requestId: requestId,
          payload: payload,
          completer: completer,
        ),
      );
      return completer.future;
    }
  }

  void completeNextRequest({ExternalOpenAiResponse? response}) {
    if (pendingRequests.isEmpty) return;
    final req = pendingRequests.removeAt(0);
    req.completer.complete(
      response ?? _buildResponse(req.payload, requestId: req.requestId),
    );
  }

  void failNextRequest(int statusCode, String errorMessage) {
    if (pendingRequests.isEmpty) return;
    final req = pendingRequests.removeAt(0);
    req.completer.complete(
      ExternalOpenAiResponse(
        statusCode: statusCode,
        body: jsonEncode({'error': errorMessage}),
      ),
    );
  }

  @override
  Future<List<String>> discoverModels() async {
    discoverModelsCalls++;
    if (!healthy) return const [];
    return List.from(availableModels);
  }

  @override
  Future<bool> checkHealth() async {
    checkHealthCalls++;
    return healthy;
  }

  @override
  Future<void> cancel(String requestId) async {
    cancelCalls++;
    cancelledRequestIds.add(requestId);
  }

  @override
  Future<void> close() async {
    isClosed = true;
  }
}
