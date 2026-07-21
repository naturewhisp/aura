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

    test('Fails loadModel if logical model binding is missing', () async {
      await runtime.initialize(
        const RuntimeInitializationRequest(
          instanceId: RuntimeInstanceId('session-missing-binding'),
        ),
      );

      expect(
        () => runtime.loadModel(
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
        ),
        throwsA(
          isA<RuntimeException>().having(
            (e) => e.failure.code,
            'code',
            equals(RuntimeFailureCode.modelMissing),
          ),
        ),
      );
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

    test('Maps HTTP 404 error to RuntimeFailureCode.modelMissing', () async {
      await runtime.initialize(
        const RuntimeInitializationRequest(
          instanceId: RuntimeInstanceId('session-404'),
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

      fakeClient.statusCodeToReturn = 404;

      expect(
        () => runtime.generateText(
          TextGenerationRequest(
            requestId: const GenerationRequestId('gen-404'),
            model: handle,
            messages: const [
              InferenceMessage(role: InferenceRole.user, content: 'Hi')
            ],
            traceContext: const InferenceTraceContext(
              traceId: RuntimeTraceId('trace-404'),
              sessionId: 's-404',
              agentId: 'actor',
              logicalModelId: 'aura.actor.primary',
            ),
          ),
        ),
        throwsA(
          isA<RuntimeException>().having(
            (e) => e.failure.code,
            'code',
            equals(RuntimeFailureCode.modelMissing),
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
