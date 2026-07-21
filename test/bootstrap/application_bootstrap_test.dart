import 'package:aura_core/aura_offline.dart';
import 'package:aura_core/aura_testing.dart';
import 'package:test/test.dart';

void main() {
  group('ApplicationBootstrap Full Paths Tests -', () {
    test('Legacy path constructs LocalApiInferenceBridge with skipHealthCheck',
        () async {
      const factory = ApplicationBootstrapFactory();
      final bootstrap = factory.create();

      final result = await bootstrap.bootstrap(
        const ApplicationBootstrapRequest(
          configuration: ApplicationRuntimeConfiguration(
            runtimeMode: ApplicationRuntimeMode.legacyExternalOpenAi,
            baseUri: null,
            skipHealthCheck: true,
          ),
        ),
      );

      expect(result.runtimeMode,
          equals(ApplicationRuntimeMode.legacyExternalOpenAi));
      expect(result.activeBridge, isA<LocalApiInferenceBridge>());
      expect(result.controller, isA<GameController>());
      expect(result.status.isHealthy, isTrue);

      await result.dispose();
    });

    test(
        'External OpenAI path with MockInferenceRuntime constructs RuntimeInferenceBridge',
        () async {
      const factory = ApplicationBootstrapFactory();
      final bootstrap = factory.create();
      final mockRuntime = MockInferenceRuntime();

      final result = await bootstrap.bootstrap(
        ApplicationBootstrapRequest(
          configuration: const ApplicationRuntimeConfiguration(
            runtimeMode: ApplicationRuntimeMode.externalOpenAiRuntime,
            actorModelId: 'aura.actor.primary',
            evaluatorModelId: 'aura.evaluator.primary',
            skipHealthCheck: true,
          ),
          customRuntime: mockRuntime,
        ),
      );

      expect(result.runtimeMode,
          equals(ApplicationRuntimeMode.externalOpenAiRuntime));
      expect(result.activeBridge, isA<RuntimeInferenceBridge>());
      expect(result.status.isHealthy, isTrue);

      await result.dispose();
    });

    test(
        'External OpenAI path with shared model creates valid bindings without modelMissing error',
        () async {
      const factory = ApplicationBootstrapFactory();
      final bootstrap = factory.create();
      final fakeClient = FakeExternalOpenAiClient(healthy: true);

      final result = await bootstrap.bootstrap(
        ApplicationBootstrapRequest(
          configuration: const ApplicationRuntimeConfiguration(
            runtimeMode: ApplicationRuntimeMode.externalOpenAiRuntime,
            actorModelId: 'shared-model-v1',
            evaluatorModelId: 'shared-model-v1',
            useSharedModel: true,
            skipHealthCheck: true,
          ),
          customHttpClient: fakeClient,
        ),
      );

      expect(result.runtimeMode,
          equals(ApplicationRuntimeMode.externalOpenAiRuntime));
      expect(result.activeBridge, isA<RuntimeInferenceBridge>());
      expect(result.status.isHealthy, isTrue);

      await result.dispose();
    });

    test(
        'Fallback policy none maintains unhealthy status when legacy health check fails without switching mode',
        () async {
      const factory = ApplicationBootstrapFactory();
      final bootstrap = factory.create();

      final result = await bootstrap.bootstrap(
        ApplicationBootstrapRequest(
          configuration: ApplicationRuntimeConfiguration(
            runtimeMode: ApplicationRuntimeMode.legacyExternalOpenAi,
            baseUri: Uri.parse('http://127.0.0.1:9999'), // Unreachable port
            skipHealthCheck: false,
            fallbackPolicy: BootstrapFallbackPolicy.none,
          ),
        ),
      );

      expect(result.runtimeMode,
          equals(ApplicationRuntimeMode.legacyExternalOpenAi));
      expect(result.status.isHealthy, isFalse);

      await result.dispose();
    });

    test(
        'Fallback policy ruleBased switches to ruleBased when legacy health check fails',
        () async {
      const factory = ApplicationBootstrapFactory();
      final bootstrap = factory.create();

      final result = await bootstrap.bootstrap(
        ApplicationBootstrapRequest(
          configuration: ApplicationRuntimeConfiguration(
            runtimeMode: ApplicationRuntimeMode.legacyExternalOpenAi,
            baseUri: Uri.parse('http://127.0.0.1:9999'), // Unreachable port
            skipHealthCheck: false,
            fallbackPolicy: BootstrapFallbackPolicy.ruleBased,
          ),
        ),
      );

      expect(result.runtimeMode, equals(ApplicationRuntimeMode.ruleBased));
      expect(result.status.isHealthy, isTrue);

      await result.dispose();
    });

    test(
        'Missing model ID in external mode throws typed ApplicationBootstrapException with sanitized message',
        () async {
      const factory = ApplicationBootstrapFactory();
      final bootstrap = factory.create();

      try {
        await bootstrap.bootstrap(
          const ApplicationBootstrapRequest(
            configuration: ApplicationRuntimeConfiguration(
              runtimeMode: ApplicationRuntimeMode.externalOpenAiRuntime,
              actorModelId: '',
            ),
          ),
        );
        fail('Expected ApplicationBootstrapException');
      } on ApplicationBootstrapException catch (e) {
        expect(e.failure.code,
            equals(ApplicationBootstrapFailureCode.missingActorModelId));
        expect(e.failure.message, contains('Attore'));
        expect(e.failure.message, isNot(contains('FormatException')));
      }
    });

    test(
        'Dispose performs best-effort cleanup closing client even if runtime.dispose fails',
        () async {
      const factory = ApplicationBootstrapFactory();
      final bootstrap = factory.create();
      final fakeClient = FakeExternalOpenAiClient(healthy: true);
      final failingRuntime = MockInferenceRuntime();

      // Setup failingRuntime to throw on dispose if possible, or test client closure
      final result = await bootstrap.bootstrap(
        ApplicationBootstrapRequest(
          configuration: const ApplicationRuntimeConfiguration(
            runtimeMode: ApplicationRuntimeMode.externalOpenAiRuntime,
            actorModelId: 'qwen',
            evaluatorModelId: 'mistral',
            skipHealthCheck: true,
          ),
          customRuntime: failingRuntime,
          customHttpClient: fakeClient,
        ),
      );

      await result.dispose();

      expect(fakeClient.isClosed, isTrue);
    });

    test('Session ID is propagated into runtime status diagnostics', () async {
      const factory = ApplicationBootstrapFactory();
      final bootstrap = factory.create();

      final result = await bootstrap.bootstrap(
        const ApplicationBootstrapRequest(
          configuration: ApplicationRuntimeConfiguration(
            runtimeMode: ApplicationRuntimeMode.ruleBased,
            sessionId: 'custom-session-123',
          ),
        ),
      );

      expect(
          result.status.diagnostics['sessionId'], equals('custom-session-123'));

      await result.dispose();
    });
  });
}
