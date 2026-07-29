import 'package:aura_core/aura_core.dart';
import 'package:test/test.dart';

void main() {
  group('ApplicationRuntimeConfiguration Tests -', () {
    test('Default constructor uses expected defaults', () {
      const config = ApplicationRuntimeConfiguration();

      expect(config.runtimeMode,
          equals(ApplicationRuntimeMode.legacyExternalOpenAi));
      expect(config.baseUri, isNull);
      expect(config.apiKey, isNull);
      expect(config.actorModelId, equals('gemma-4-12b-it-qat-q4-0'));
      expect(config.evaluatorModelId, equals('mistralai/ministral-3-3b'));
      expect(config.timeout, equals(const Duration(seconds: 30)));
      expect(config.skipHealthCheck, isFalse);
      expect(config.useSharedModel, isFalse);
      expect(config.fallbackPolicy, equals(BootstrapFallbackPolicy.none));
    });

    test('fromEnvironment parses valid environment variables', () {
      final env = {
        'AURA_RUNTIME_MODE': 'external',
        'AURA_INFERENCE_BASE_URL': 'http://127.0.0.1:8080',
        'AURA_ACTOR_MODEL_ID': 'custom-actor',
        'AURA_EVALUATOR_MODEL_ID': 'custom-eval',
        'AURA_INFERENCE_API_KEY': 'secret-key-123',
      };

      final config = ApplicationRuntimeConfiguration.fromEnvironment(env);

      expect(config.runtimeMode,
          equals(ApplicationRuntimeMode.externalOpenAiRuntime));
      expect(config.baseUri, equals(Uri.parse('http://127.0.0.1:8080')));
      expect(config.actorModelId, equals('custom-actor'));
      expect(config.evaluatorModelId, equals('custom-eval'));
      expect(config.apiKey, equals('secret-key-123'));
    });

    test('fromEnvironment parses legacy and ruleBased runtime modes', () {
      final legacyConfig = ApplicationRuntimeConfiguration.fromEnvironment({
        'AURA_RUNTIME_MODE': 'legacy',
      });
      expect(legacyConfig.runtimeMode,
          equals(ApplicationRuntimeMode.legacyExternalOpenAi));

      final ruleConfig = ApplicationRuntimeConfiguration.fromEnvironment({
        'AURA_RUNTIME_MODE': 'rule-based',
      });
      expect(ruleConfig.runtimeMode, equals(ApplicationRuntimeMode.ruleBased));
    });

    test('fromEnvironment throws FormatException for invalid runtime mode', () {
      expect(
        () => ApplicationRuntimeConfiguration.fromEnvironment({
          'AURA_RUNTIME_MODE': 'invalid_mode_xyz',
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test(
        'fromEnvironment throws FormatException for invalid URI without scheme',
        () {
      expect(
        () => ApplicationRuntimeConfiguration.fromEnvironment({
          'AURA_INFERENCE_BASE_URL': 'not-a-valid-uri',
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('fromEnvironment throws FormatException for empty actor model ID', () {
      expect(
        () => ApplicationRuntimeConfiguration.fromEnvironment({
          'AURA_ACTOR_MODEL_ID': '   ',
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('copyWith produces updated immutability copy', () {
      const config = ApplicationRuntimeConfiguration();
      final updated = config.copyWith(
        runtimeMode: ApplicationRuntimeMode.externalOpenAiRuntime,
        apiKey: 'test-key',
      );

      expect(updated.runtimeMode,
          equals(ApplicationRuntimeMode.externalOpenAiRuntime));
      expect(updated.apiKey, equals('test-key'));
      expect(updated.actorModelId, equals(config.actorModelId));
    });
  });
}
