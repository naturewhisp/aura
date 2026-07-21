import 'package:aura_core/aura_offline.dart';
import 'package:aura_core/aura_testing.dart';
import 'package:test/test.dart';

class SpyInferenceRuntime implements InferenceRuntime {
  int disposeCallCount = 0;
  bool isUnhealthy;

  SpyInferenceRuntime({this.isUnhealthy = false});

  @override
  RuntimeState get state => RuntimeState.ready;

  @override
  Stream<RuntimeEvent> get events => const Stream.empty();

  @override
  Future<RuntimeCapabilities> initialize(
      RuntimeInitializationRequest request) async {
    return const RuntimeCapabilities(
      adapterId: RuntimeAdapterId('spy'),
      runtimeName: 'Spy Runtime',
      runtimeVersion: '1.0.0',
      runtimeBuildId: 'spy-build',
      selectedBackend: RuntimeBackend.external,
      generationCapabilities: {GenerationCapability.text},
      modelCapabilities: {ModelCapability.multipleLoadedModels},
      maxConcurrentGenerations: 1,
      maxLoadedModels: 2,
    );
  }

  @override
  Future<ModelHandle> loadModel(ModelLoadRequest request) async {
    return ModelHandle(
      id: ModelHandleId('handle-${request.logicalModelId}'),
      runtimeInstanceId: const RuntimeInstanceId('spy-instance'),
      logicalModelId: request.logicalModelId,
      modelVariantId: request.artifact.modelVariantId,
      roles: request.roles,
      loadedAt: DateTime.now(),
    );
  }

  @override
  Future<void> unloadModel(ModelHandle handle) async {}

  @override
  Future<TextGenerationResult> generateText(
      TextGenerationRequest request) async {
    throw UnimplementedError();
  }

  @override
  Future<StructuredGenerationResult> generateStructured(
      StructuredGenerationRequest request) async {
    throw UnimplementedError();
  }

  @override
  Future<void> cancel(GenerationRequestId requestId) async {}

  @override
  Future<RuntimeHealth> health() async {
    return RuntimeHealth(
      instanceId: const RuntimeInstanceId('spy-instance'),
      state: RuntimeState.ready,
      responsive: !isUnhealthy,
      observedAt: DateTime.now(),
      backend: RuntimeBackend.external,
    );
  }

  @override
  Future<void> dispose() async {
    disposeCallCount++;
  }
}

class FailingDisposeInferenceRuntime extends SpyInferenceRuntime {
  FailingDisposeInferenceRuntime({super.isUnhealthy});

  @override
  Future<void> dispose() async {
    await super.dispose();
    throw Exception('Simulated runtime dispose failure');
  }
}

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
        'Fallback policy none maintains unhealthy status when external health check fails without switching mode (offline deterministic test)',
        () async {
      const factory = ApplicationBootstrapFactory();
      final bootstrap = factory.create();
      final fakeClient = FakeExternalOpenAiClient(healthy: false);

      final result = await bootstrap.bootstrap(
        ApplicationBootstrapRequest(
          configuration: const ApplicationRuntimeConfiguration(
            runtimeMode: ApplicationRuntimeMode.externalOpenAiRuntime,
            actorModelId: 'qwen',
            evaluatorModelId: 'mistral',
            skipHealthCheck: false,
            fallbackPolicy: BootstrapFallbackPolicy.none,
          ),
          customHttpClient: fakeClient,
        ),
      );

      expect(result.runtimeMode,
          equals(ApplicationRuntimeMode.externalOpenAiRuntime));
      expect(result.status.isHealthy, isFalse);

      await result.dispose();
    });

    test(
        'Fallback policy ruleBased switches to ruleBased and cleanly disposes external runtime and client without leak',
        () async {
      const factory = ApplicationBootstrapFactory();
      final bootstrap = factory.create();
      final spyRuntime = SpyInferenceRuntime(isUnhealthy: true);
      final fakeClient = FakeExternalOpenAiClient(healthy: false);

      final result = await bootstrap.bootstrap(
        ApplicationBootstrapRequest(
          configuration: const ApplicationRuntimeConfiguration(
            runtimeMode: ApplicationRuntimeMode.externalOpenAiRuntime,
            actorModelId: 'qwen',
            evaluatorModelId: 'mistral',
            skipHealthCheck: false,
            fallbackPolicy: BootstrapFallbackPolicy.ruleBased,
          ),
          customRuntime: spyRuntime,
          customHttpClient: fakeClient,
        ),
      );

      expect(result.runtimeMode, equals(ApplicationRuntimeMode.ruleBased));
      expect(result.status.isHealthy, isTrue);
      expect(spyRuntime.disposeCallCount, equals(1));
      expect(fakeClient.isClosed, isTrue);
      expect(result.status.diagnostics['fallbackCleanupPerformed'], isTrue);
      expect(result.status.diagnostics['runtimeDisposeSucceeded'], isTrue);
      expect(result.status.diagnostics['clientCloseSucceeded'], isTrue);
      expect(
          result.status.diagnostics['fallbackCleanupFailureCount'], equals(0));

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
        'Dispose performs best-effort cleanup closing client even when runtime.dispose throws exception',
        () async {
      const factory = ApplicationBootstrapFactory();
      final bootstrap = factory.create();
      final fakeClient = FakeExternalOpenAiClient(healthy: true);
      final failingRuntime = FailingDisposeInferenceRuntime();

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

      try {
        await result.dispose();
        fail(
            'Expected ApplicationBootstrapException due to failing runtime dispose');
      } on ApplicationBootstrapException catch (e) {
        expect(e.failure.code,
            equals(ApplicationBootstrapFailureCode.disposeFailed));
      }

      expect(failingRuntime.disposeCallCount, equals(1));
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
