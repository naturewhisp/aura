import 'dart:convert';
import 'package:aura_core/aura_offline.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  group('LocalApiInferenceBridge', () {
    test(
        'retries with json_object when json_schema returns 400 sampler error and updates capability cache',
        () async {
      int postCount = 0;

      final mockClient = MockClient((request) async {
        postCount++;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final responseFormat = body['response_format'] as Map<String, dynamic>?;

        if (responseFormat?['type'] == 'json_schema') {
          return http.Response(
            jsonEncode({
              "error": {
                "code": 400,
                "message":
                    "Failed to initialize samplers: Unexpected empty grammar stack after accepting piece: assistant (13892)",
                "type": "invalid_request_error"
              }
            }),
            400,
            headers: {'content-type': 'application/json'},
          );
        } else if (responseFormat?['type'] == 'json_object') {
          return http.Response(
            jsonEncode({
              "choices": [
                {
                  "message": {
                    "content": jsonEncode({
                      "delta_alert": 0,
                      "delta_imperative": 10,
                      "delta_control": 0,
                      "delta_dissonance": 0,
                      "creativity_index": 3,
                      "injection_risk": 0,
                      "semantic_category": "moral_imperative"
                    })
                  }
                }
              ]
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        return http.Response("Bad request", 400);
      });

      final bridge = LocalApiInferenceBridge(
        baseUrl: 'http://127.0.0.1:1234',
        client: mockClient,
      );

      // Prima chiamata: scatta retry da json_schema a json_object
      final res1 = await bridge.generateStructuredWithMetadata(
        modelId: 'mistral-model',
        messages: [
          {'role': 'user', 'content': 'Test prompt'}
        ],
        schema: const {},
      );

      expect(res1.mode, equals(EvaluatorExecutionMode.llmJsonObject));
      expect(res1.value['semantic_category'], equals('moral_imperative'));
      expect(postCount, equals(2));

      // Seconda chiamata: usa direttamente json_object dalla capability cache per istanza
      postCount = 0;
      final res2 = await bridge.generateStructuredWithMetadata(
        modelId: 'mistral-model',
        messages: [
          {'role': 'user', 'content': 'Second prompt'}
        ],
        schema: const {},
      );

      expect(res2.mode, equals(EvaluatorExecutionMode.llmJsonObject));
      expect(postCount, equals(1));
    });

    test(
        'does not retry and throws LocalInferenceException immediately on HTTP 401',
        () async {
      final mockClient = MockClient((request) async {
        return http.Response("Unauthorized", 401);
      });

      final bridge = LocalApiInferenceBridge(
        baseUrl: 'http://127.0.0.1:1234',
        client: mockClient,
      );

      expect(
        () => bridge.generateStructuredWithMetadata(
          modelId: 'protected-model',
          messages: [
            {'role': 'user', 'content': 'Test'}
          ],
          schema: const {},
        ),
        throwsA(isA<LocalInferenceException>().having(
          (e) => e.statusCode,
          'statusCode',
          equals(401),
        )),
      );
    });

    test('extracts JSON from Markdown code fence correctly', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            "choices": [
              {
                "message": {
                  "content":
                      "Ecco la risposta:\n```json\n{\"delta_alert\": 5, \"semantic_category\": \"logical_paradox\"}\n```"
                }
              }
            ]
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final bridge = LocalApiInferenceBridge(
        baseUrl: 'http://127.0.0.1:1234',
        client: mockClient,
      );

      final res = await bridge.generateStructuredWithMetadata(
        modelId: 'test-model',
        messages: [
          {'role': 'user', 'content': 'Test'}
        ],
        schema: const {},
      );

      expect(res.value['semantic_category'], equals('logical_paradox'));
      expect(res.value['delta_alert'], equals(5));
    });
  });
}
