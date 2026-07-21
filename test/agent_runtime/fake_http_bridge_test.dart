import 'dart:convert';
import 'dart:io';
import 'package:aura_core/aura_offline.dart';
import 'package:test/test.dart';

void main() {
  group('LocalApiInferenceBridge Protocol Tests with Local Fake Server -', () {
    late HttpServer server;
    late LocalApiInferenceBridge bridge;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      bridge = LocalApiInferenceBridge(
        baseUrl: 'http://${server.address.host}:${server.port}',
      );
    });

    tearDown(() async {
      await server.close(force: true);
    });

    test('generateText communicates correctly with HTTP endpoint', () async {
      server.listen((HttpRequest request) async {
        expect(request.method, equals('POST'));
        expect(request.uri.path, equals('/v1/chat/completions'));

        final bodyString = await utf8.decoder.bind(request).join();
        final bodyJson = jsonDecode(bodyString) as Map<String, dynamic>;
        expect(bodyJson['model'], equals('test-model'));

        final responsePayload = {
          'choices': [
            {
              'message': {
                'content':
                    '<dialogo>Risposta di test dal server mock.</dialogo>',
              },
            },
          ],
        };

        request.response
          ..headers.contentType = ContentType.json
          ..statusCode = HttpStatus.ok
          ..write(jsonEncode(responsePayload));
        await request.response.close();
      });

      final result = await bridge.generateText(
        modelId: 'test-model',
        messages: [
          {'role': 'user', 'content': 'Test request'},
        ],
      );

      expect(result, equals('Risposta di test dal server mock.'));
    });

    test('generateStructured parses JSON schema response correctly', () async {
      server.listen((HttpRequest request) async {
        final responsePayload = {
          'choices': [
            {
              'message': {
                'content': jsonEncode({
                  'delta_alert': 5,
                  'delta_imperative': 10,
                  'delta_control': 5,
                  'delta_dissonance': 0,
                  'creativity_index': 3,
                  'injection_risk': 0,
                  'semantic_category': 'moral_imperative',
                }),
              },
            },
          ],
        };

        request.response
          ..headers.contentType = ContentType.json
          ..statusCode = HttpStatus.ok
          ..write(jsonEncode(responsePayload));
        await request.response.close();
      });

      final result = await bridge.generateStructured(
        modelId: 'test-model',
        messages: [
          {'role': 'user', 'content': 'Test request'},
        ],
        schema: const {},
      );

      expect(result['delta_alert'], equals(5));
      expect(result['semantic_category'], equals('moral_imperative'));
    });

    test('discoverModels returns models list from local server endpoint',
        () async {
      server.listen((HttpRequest request) async {
        expect(request.uri.path, equals('/v1/models'));

        final responsePayload = {
          'data': [
            {'id': 'mistralai/ministral-3-3b'},
            {'id': 'qwen/qwen3.5-9b'},
          ],
        };

        request.response
          ..headers.contentType = ContentType.json
          ..statusCode = HttpStatus.ok
          ..write(jsonEncode(responsePayload));
        await request.response.close();
      });

      final models = await bridge.discoverModels();
      expect(
          models, containsAll(['mistralai/ministral-3-3b', 'qwen/qwen3.5-9b']));
    });
  });
}
