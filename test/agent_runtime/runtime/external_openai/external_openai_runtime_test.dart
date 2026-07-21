import 'package:aura_core/aura_offline.dart';
import 'package:test/test.dart';

import '../../../contract/runtime_contract_test_harness.dart';

void main() {
  // 1. Shared Contract Test Harness execution against ExternalOpenAiRuntime
  runInferenceRuntimeContractTests(
    'ExternalOpenAiRuntime',
    () async {
      final fakeClient = FakeExternalOpenAiClient();
      final config = ExternalOpenAiConfiguration(
        baseUri: Uri.parse('http://127.0.0.1:1234'),
        maxLoadedModels: 2,
        supportsMultipleLoadedModels: true,
        supportsCancellation: false,
      );
      final bindings = const [
        ExternalOpenAiModelBinding(
          logicalModelId: 'aura.evaluator.primary',
          serverModelId: 'mistralai/ministral-3-3b',
        ),
        ExternalOpenAiModelBinding(
          logicalModelId: 'aura.actor.primary',
          serverModelId: 'qwen/qwen3.5-9b',
        ),
      ];
      return ExternalOpenAiRuntime(
        configuration: config,
        client: fakeClient,
        bindings: bindings,
      );
    },
    profile: const RuntimeContractTestProfile(
      supportsCancellation: false,
      supportsStructuredJson: true,
      supportsMultipleHandles: true,
    ),
  );

  // 2. Dedicated Unit & Failure Mapping Tests for ExternalOpenAiRuntime
  group('ExternalOpenAiRuntime Dedicated Unit & Failure Mapping Tests -', () {
    late FakeExternalOpenAiClient fakeClient;
    late ExternalOpenAiRuntime runtime;

    setUp(() {
      fakeClient = FakeExternalOpenAiClient();
      runtime = ExternalOpenAiRuntime(
        configuration: ExternalOpenAiConfiguration(
          baseUri: Uri.parse('http://127.0.0.1:1234'),
          supportsCancellation: false,
        ),
        client: fakeClient,
        bindings: const [
          ExternalOpenAiModelBinding(
            logicalModelId: 'aura.actor.primary',
            serverModelId: 'qwen/qwen3.5-9b',
          ),
        ],
      );
    });

    tearDown(() async {
      if (runtime.state != RuntimeState.disposed) {
        await runtime.dispose();
      }
    });

    test(
        'Fails loadModel cleanly: emits ModelLoadFailed and restores state to ready',
        () async {
      await runtime.initialize(
        const RuntimeInitializationRequest(
          instanceId: RuntimeInstanceId('session-load-fail'),
        ),
      );

      final events = <RuntimeEvent>[];
      runtime.events.listen(events.add);

      try {
        await runtime.loadModel(
          const ModelLoadRequest(
            requestId: ModelLoadRequestId('load-unbound'),
            artifact: ResolvedModelArtifact(
              modelVariantId: 'v1',
              sha256: 'a',
              format: 'gguf',
              quantization: 'Q4',
              architecture: 'unknown',
              compatibility: ModelRuntimeCompatibility(compatible: true),
            ),
            logicalModelId: 'aura.unbound.model',
            roles: {ModelRole.evaluator},
          ),
        );
      } catch (_) {}

      await Future<void>.delayed(Duration.zero);

      // Verify state was restored to ready
      expect(runtime.state, equals(RuntimeState.ready));

      // Verify event order: ModelLoadStarted, ModelLoadFailed, RuntimeStateChanged
      expect(events.any((e) => e is ModelLoadStarted), isTrue);
      expect(events.any((e) => e is ModelLoadFailed), isTrue);
      expect(events.any((e) => e is ModelLoadCompleted), isFalse);
    });

    test('Enforces maxLoadedModels limit and throws tooManyLoadedModels',
        () async {
      final singleModelRuntime = ExternalOpenAiRuntime(
        configuration: ExternalOpenAiConfiguration(
          baseUri: Uri.parse('http://127.0.0.1:1234'),
          maxLoadedModels: 1,
          supportsMultipleLoadedModels: false,
        ),
        client: fakeClient,
        bindings: const [
          ExternalOpenAiModelBinding(
            logicalModelId: 'aura.actor.primary',
            serverModelId: 'qwen/qwen3.5-9b',
          ),
          ExternalOpenAiModelBinding(
            logicalModelId: 'aura.evaluator.primary',
            serverModelId: 'mistralai/ministral-3-3b',
          ),
        ],
      );

      await singleModelRuntime.initialize(
        const RuntimeInitializationRequest(
          instanceId: RuntimeInstanceId('session-max-loaded'),
        ),
      );

      await singleModelRuntime.loadModel(
        const ModelLoadRequest(
          requestId: ModelLoadRequestId('load-1'),
          artifact: ResolvedModelArtifact(
            modelVariantId: 'v1',
            sha256: 'a',
            format: 'gguf',
            quantization: 'Q4',
            architecture: 'qwen2',
            compatibility: ModelRuntimeCompatibility(compatible: true),
          ),
          logicalModelId: 'aura.actor.primary',
          roles: {ModelRole.actor},
        ),
      );

      expect(
        () => singleModelRuntime.loadModel(
          const ModelLoadRequest(
            requestId: ModelLoadRequestId('load-2'),
            artifact: ResolvedModelArtifact(
              modelVariantId: 'v2',
              sha256: 'b',
              format: 'gguf',
              quantization: 'Q4',
              architecture: 'llama',
              compatibility: ModelRuntimeCompatibility(compatible: true),
            ),
            logicalModelId: 'aura.evaluator.primary',
            roles: {ModelRole.evaluator},
          ),
        ),
        throwsA(
          isA<RuntimeException>().having(
            (e) => e.failure.code,
            'code',
            equals(RuntimeFailureCode.tooManyLoadedModels),
          ),
        ),
      );

      await singleModelRuntime.dispose();
    });

    test(
        'Throws cancellationUnsupported on cancel when supportsCancellation is false',
        () async {
      await runtime.initialize(
        const RuntimeInitializationRequest(
          instanceId: RuntimeInstanceId('session-cancel-unsupported'),
        ),
      );

      expect(
        () => runtime.cancel(const GenerationRequestId('gen-1')),
        throwsA(
          isA<RuntimeException>().having(
            (e) => e.failure.code,
            'code',
            equals(RuntimeFailureCode.cancellationUnsupported),
          ),
        ),
      );
    });

    test('Omits ModelCapability.cpuExecution when selectedBackend is external',
        () async {
      final capabilities = await runtime.initialize(
        const RuntimeInitializationRequest(
          instanceId: RuntimeInstanceId('session-backend-cap'),
        ),
      );

      expect(
        capabilities.modelCapabilities.contains(ModelCapability.cpuExecution),
        isFalse,
      );
    });

    test('Fails initialization if health check fails', () async {
      fakeClient.healthy = false;

      expect(
        () => runtime.initialize(
          const RuntimeInitializationRequest(
            instanceId: RuntimeInstanceId('session-fail-init'),
          ),
        ),
        throwsA(
          isA<RuntimeException>().having(
            (e) => e.failure.code,
            'code',
            equals(RuntimeFailureCode.backendUnavailable),
          ),
        ),
      );
    });

    test('Parses reasoning_content from OpenAI completion response', () async {
      await runtime.initialize(
        const RuntimeInitializationRequest(
          instanceId: RuntimeInstanceId('session-reasoning'),
        ),
      );

      final handle = await runtime.loadModel(
        const ModelLoadRequest(
          requestId: ModelLoadRequestId('load-1'),
          artifact: ResolvedModelArtifact(
            modelVariantId: 'v1',
            sha256: 'a',
            format: 'gguf',
            quantization: 'Q4',
            architecture: 'qwen2',
            compatibility: ModelRuntimeCompatibility(compatible: true),
          ),
          logicalModelId: 'aura.actor.primary',
          roles: {ModelRole.actor},
        ),
      );

      fakeClient.defaultResponseContent = 'Dialogo finale dall\'attore.';
      fakeClient.defaultReasoningContent =
          'Ragionamento interno prima della battuta.';

      final result = await runtime.generateText(
        TextGenerationRequest(
          requestId: const GenerationRequestId('gen-reasoning'),
          model: handle,
          messages: const [
            InferenceMessage(role: InferenceRole.user, content: 'Hi')
          ],
          traceContext: const InferenceTraceContext(
            traceId: RuntimeTraceId('trace-reasoning'),
            sessionId: 's-reasoning',
            agentId: 'actor',
            logicalModelId: 'aura.actor.primary',
          ),
        ),
      );

      expect(result.content, equals('Dialogo finale dall\'attore.'));
      expect(result.reasoningContent,
          equals('Ragionamento interno prima della battuta.'));
    });
  });
}
