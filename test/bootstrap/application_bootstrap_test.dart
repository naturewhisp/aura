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
      expect(result.runtime, equals(mockRuntime));
      expect(result.status.isHealthy, isTrue);

      await result.dispose();
    });

    test(
        'External OpenAI path with shared model creates single handle execution plan',
        () async {
      const factory = ApplicationBootstrapFactory();
      final bootstrap = factory.create();
      final mockRuntime = MockInferenceRuntime();

      final result = await bootstrap.bootstrap(
        ApplicationBootstrapRequest(
          configuration: const ApplicationRuntimeConfiguration(
            runtimeMode: ApplicationRuntimeMode.externalOpenAiRuntime,
            actorModelId: 'shared-model-v1',
            evaluatorModelId: 'shared-model-v1',
            useSharedModel: true,
            skipHealthCheck: true,
          ),
          customRuntime: mockRuntime,
        ),
      );

      expect(result.runtimeMode,
          equals(ApplicationRuntimeMode.externalOpenAiRuntime));
      expect(result.activeBridge, isA<RuntimeInferenceBridge>());

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
        'Missing model ID in external mode throws typed ApplicationBootstrapException',
        () async {
      const factory = ApplicationBootstrapFactory();
      final bootstrap = factory.create();

      expect(
        () => bootstrap.bootstrap(
          const ApplicationBootstrapRequest(
            configuration: ApplicationRuntimeConfiguration(
              runtimeMode: ApplicationRuntimeMode.externalOpenAiRuntime,
              actorModelId: '',
            ),
          ),
        ),
        throwsA(
          isA<ApplicationBootstrapException>().having(
            (e) => e.failure.code,
            'code',
            equals(ApplicationBootstrapFailureCode.missingActorModelId),
          ),
        ),
      );
    });
  });
}
