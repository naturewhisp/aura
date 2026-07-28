import 'package:aura_core/aura_offline.dart';
import 'package:aura_core/aura_testing.dart';
import 'package:test/test.dart';

class TrackingMockBridge extends MockInferenceBridge {
  int generateTextCalls = 0;
  int generateStructuredCalls = 0;

  final List<String> customModels;

  TrackingMockBridge({
    super.mockTextResponse = 'Risposta Actor OK',
    super.mockStructuredResponse = const {
      'delta_alert': 5,
      'semantic_category': 'irrelevant'
    },
    this.customModels = const ["mistralai/ministral-3-3b", "qwen/qwen3.5-9b"],
  });

  @override
  Future<String> generateText({
    required String modelId,
    required List<Map<String, String>> messages,
    double temperature = 0.7,
    int maxTokens = 150,
    bool? thinking,
  }) async {
    generateTextCalls++;
    return super.generateText(
      modelId: modelId,
      messages: messages,
      temperature: temperature,
      maxTokens: maxTokens,
      thinking: thinking,
    );
  }

  @override
  Future<Map<String, dynamic>> generateStructured({
    required String modelId,
    required List<Map<String, String>> messages,
    required Map<String, dynamic> schema,
    double temperature = 0.0,
  }) async {
    generateStructuredCalls++;
    return super.generateStructured(
      modelId: modelId,
      messages: messages,
      schema: schema,
      temperature: temperature,
    );
  }

  @override
  Future<List<String>> discoverModels() async {
    return customModels;
  }
}

void main() {
  group('DualModelInferenceBridge', () {
    late TrackingMockBridge actorBridge;
    late TrackingMockBridge evaluatorBridge;
    late DualModelInferenceBridge dualBridge;

    const actorId = 'aura.actor.primary';
    const evaluatorId = 'aura.evaluator.primary';

    setUp(() {
      actorBridge = TrackingMockBridge(
        mockTextResponse: 'Risposta Actor OK',
      );

      evaluatorBridge = TrackingMockBridge(
        mockStructuredResponse: {
          'delta_alert': 5,
          'semantic_category': 'irrelevant'
        },
      );

      dualBridge = DualModelInferenceBridge(
        actorBridge: actorBridge,
        evaluatorBridge: evaluatorBridge,
        actorModelId: actorId,
        evaluatorModelId: evaluatorId,
      );
    });

    test('generateText viene inoltrato ad actorBridge per modelId valido',
        () async {
      final res = await dualBridge.generateText(
        modelId: actorId,
        messages: [
          {'role': 'user', 'content': 'ciao'}
        ],
      );

      expect(res, equals('Risposta Actor OK'));
      expect(actorBridge.generateTextCalls, equals(1));
      expect(evaluatorBridge.generateTextCalls, equals(0));
    });

    test(
        'generateText lancia DualModelRoutingException per modelId inatteso (es. evaluatorId)',
        () async {
      expect(
        () => dualBridge.generateText(
          modelId: evaluatorId,
          messages: [
            {'role': 'user', 'content': 'ciao'}
          ],
        ),
        throwsA(isA<DualModelRoutingException>()),
      );
      expect(actorBridge.generateTextCalls, equals(0));
    });

    test(
        'generateStructured viene inoltrato ad evaluatorBridge per modelId valido',
        () async {
      final res = await dualBridge.generateStructured(
        modelId: evaluatorId,
        messages: [
          {'role': 'user', 'content': 'test'}
        ],
        schema: {},
      );

      expect(res['delta_alert'], equals(5));
      expect(evaluatorBridge.generateStructuredCalls, equals(1));
      expect(actorBridge.generateStructuredCalls, equals(0));
    });

    test(
        'generateStructured lancia DualModelRoutingException per modelId inatteso (es. actorId)',
        () async {
      expect(
        () => dualBridge.generateStructured(
          modelId: actorId,
          messages: [
            {'role': 'user', 'content': 'test'}
          ],
          schema: {},
        ),
        throwsA(isA<DualModelRoutingException>()),
      );
      expect(evaluatorBridge.generateStructuredCalls, equals(0));
    });

    test('discoverModels restituisce l\'unione di entrambi i bridge', () async {
      actorBridge = TrackingMockBridge(
        customModels: ['aura.actor.primary', 'shared.model'],
      );
      evaluatorBridge = TrackingMockBridge(
        customModels: ['aura.evaluator.primary', 'shared.model'],
      );
      dualBridge = DualModelInferenceBridge(
        actorBridge: actorBridge,
        evaluatorBridge: evaluatorBridge,
        actorModelId: actorId,
        evaluatorModelId: evaluatorId,
      );

      final models = await dualBridge.discoverModels();
      expect(
        models,
        equals([
          'aura.actor.primary',
          'shared.model',
          'aura.evaluator.primary',
        ]),
      );
    });
  });
}
