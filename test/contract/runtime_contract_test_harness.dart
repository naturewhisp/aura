import 'package:aura_core/aura_core.dart';
import 'package:test/test.dart';

/// Contract test profile to customize feature checks based on declared runtime capabilities.
class RuntimeContractTestProfile {
  final bool supportsCancellation;
  final bool supportsStructuredJson;
  final bool supportsMultipleHandles;

  const RuntimeContractTestProfile({
    this.supportsCancellation = true,
    this.supportsStructuredJson = true,
    this.supportsMultipleHandles = true,
  });
}

/// Shared contract test suite verifying that an [InferenceRuntime] implementation
/// strictly complies with INFERENCE_RUNTIME_CONTRACT.md invariants.
void runInferenceRuntimeContractTests(
  String adapterName,
  Future<InferenceRuntime> Function() createRuntime, {
  RuntimeContractTestProfile profile = const RuntimeContractTestProfile(),
}) {
  group('InferenceRuntime Contract Tests ($adapterName) -', () {
    late InferenceRuntime runtime;

    setUp(() async {
      runtime = await createRuntime();
    });

    tearDown(() async {
      if (runtime.state != RuntimeState.disposed) {
        await runtime.dispose();
      }
    });

    test('Initial state is uninitialized', () {
      expect(runtime.state, equals(RuntimeState.uninitialized));
    });

    test('Initializes successfully and transitions to ready', () async {
      final req = RuntimeInitializationRequest(
        instanceId: const RuntimeInstanceId('session-001'),
      );

      final caps = await runtime.initialize(req);
      expect(caps.runtimeName, isNotEmpty);
      expect(runtime.state, equals(RuntimeState.ready));
    });

    test('Rejects repeated initialization with typed failure', () async {
      final req = RuntimeInitializationRequest(
        instanceId: const RuntimeInstanceId('session-001'),
      );

      await runtime.initialize(req);

      expect(
        () => runtime.initialize(req),
        throwsA(
          isA<RuntimeException>().having(
            (e) => e.failure.code,
            'code',
            equals(RuntimeFailureCode.alreadyInitialized),
          ),
        ),
      );
    });

    test('Rejects model load before initialization', () async {
      final loadReq = ModelLoadRequest(
        requestId: const ModelLoadRequestId('load-1'),
        artifact: const ResolvedModelArtifact(
          modelVariantId: 'variant-01',
          sha256: 'abc',
          format: 'gguf',
          quantization: 'Q4_K_M',
          architecture: 'llama',
          compatibility: ModelRuntimeCompatibility(compatible: true),
        ),
        logicalModelId: 'mistralai/ministral-3-3b',
        roles: const {ModelRole.evaluator},
      );

      expect(
        () => runtime.loadModel(loadReq),
        throwsA(
          isA<RuntimeException>().having(
            (e) => e.failure.code,
            'code',
            equals(RuntimeFailureCode.invalidState),
          ),
        ),
      );
    });

    test('Loads a model and returns a valid ModelHandle', () async {
      await runtime.initialize(
        const RuntimeInitializationRequest(
            instanceId: RuntimeInstanceId('sess-1')),
      );

      final loadReq = ModelLoadRequest(
        requestId: const ModelLoadRequestId('load-1'),
        artifact: const ResolvedModelArtifact(
          modelVariantId: 'variant-01',
          sha256: 'abc',
          format: 'gguf',
          quantization: 'Q4_K_M',
          architecture: 'llama',
          compatibility: ModelRuntimeCompatibility(compatible: true),
        ),
        logicalModelId: 'mistralai/ministral-3-3b',
        roles: const {ModelRole.evaluator},
      );

      final handle = await runtime.loadModel(loadReq);
      expect(handle.logicalModelId, equals('mistralai/ministral-3-3b'));
      expect(
          handle.runtimeInstanceId, equals(const RuntimeInstanceId('sess-1')));
      expect(runtime.state, equals(RuntimeState.modelReady));
    });

    test('Rejects handle belonging to another session', () async {
      await runtime.initialize(
        const RuntimeInitializationRequest(
            instanceId: RuntimeInstanceId('sess-1')),
      );

      final invalidHandle = ModelHandle(
        id: const ModelHandleId('foreign-handle'),
        runtimeInstanceId: const RuntimeInstanceId('other-session'),
        logicalModelId: 'mistralai/ministral-3-3b',
        modelVariantId: 'variant-01',
        roles: const {ModelRole.evaluator},
        loadedAt: DateTime.now(),
      );

      final genReq = TextGenerationRequest(
        requestId: const GenerationRequestId('gen-1'),
        model: invalidHandle,
        messages: const [
          InferenceMessage(role: InferenceRole.user, content: 'Hi')
        ],
        traceContext: const InferenceTraceContext(
          traceId: RuntimeTraceId('trace-1'),
          sessionId: 'sess-1',
          agentId: 'evaluator',
          logicalModelId: 'mistralai/ministral-3-3b',
        ),
      );

      expect(
        () => runtime.generateText(genReq),
        throwsA(
          isA<RuntimeException>().having(
            (e) => e.failure.code,
            'code',
            equals(RuntimeFailureCode.invalidModelHandle),
          ),
        ),
      );
    });

    test('Generates text using a valid loaded model handle', () async {
      await runtime.initialize(
        const RuntimeInitializationRequest(
            instanceId: RuntimeInstanceId('sess-1')),
      );

      final handle = await runtime.loadModel(
        ModelLoadRequest(
          requestId: const ModelLoadRequestId('load-1'),
          artifact: const ResolvedModelArtifact(
            modelVariantId: 'variant-01',
            sha256: 'abc',
            format: 'gguf',
            quantization: 'Q4_K_M',
            architecture: 'llama',
            compatibility: ModelRuntimeCompatibility(compatible: true),
          ),
          logicalModelId: 'qwen/qwen3.5-9b',
          roles: const {ModelRole.actor},
        ),
      );

      final genReq = TextGenerationRequest(
        requestId: const GenerationRequestId('gen-1'),
        model: handle,
        messages: const [
          InferenceMessage(role: InferenceRole.user, content: 'Hello')
        ],
        traceContext: const InferenceTraceContext(
          traceId: RuntimeTraceId('trace-1'),
          sessionId: 'sess-1',
          agentId: 'actor',
          logicalModelId: 'qwen/qwen3.5-9b',
        ),
      );

      final res = await runtime.generateText(genReq);
      expect(res.requestId, equals(const GenerationRequestId('gen-1')));
      expect(res.content, isNotEmpty);
    });

    test('Generates structured output using a valid model handle', () async {
      if (!profile.supportsStructuredJson) return;

      await runtime.initialize(
        const RuntimeInitializationRequest(
            instanceId: RuntimeInstanceId('sess-1')),
      );

      final handle = await runtime.loadModel(
        ModelLoadRequest(
          requestId: const ModelLoadRequestId('load-1'),
          artifact: const ResolvedModelArtifact(
            modelVariantId: 'variant-01',
            sha256: 'abc',
            format: 'gguf',
            quantization: 'Q4_K_M',
            architecture: 'llama',
            compatibility: ModelRuntimeCompatibility(compatible: true),
          ),
          logicalModelId: 'mistralai/ministral-3-3b',
          roles: const {ModelRole.evaluator},
        ),
      );

      final req = StructuredGenerationRequest(
        requestId: const GenerationRequestId('gen-struct-1'),
        model: handle,
        messages: const [
          InferenceMessage(role: InferenceRole.user, content: 'Evaluate input')
        ],
        schema: const JsonSchemaDocument(
          schemaId: 'evaluator-schema',
          document: {},
        ),
        traceContext: const InferenceTraceContext(
          traceId: RuntimeTraceId('trace-struct-1'),
          sessionId: 'sess-1',
          agentId: 'evaluator',
          logicalModelId: 'mistralai/ministral-3-3b',
        ),
      );

      final res = await runtime.generateStructured(req);
      expect(res.requestId, equals(const GenerationRequestId('gen-struct-1')));
      expect(res.parsedObject, isNotNull);
    });

    test('Unloads model handle and invalidates subsequent requests', () async {
      await runtime.initialize(
        const RuntimeInitializationRequest(
            instanceId: RuntimeInstanceId('sess-1')),
      );

      final handle = await runtime.loadModel(
        ModelLoadRequest(
          requestId: const ModelLoadRequestId('load-1'),
          artifact: const ResolvedModelArtifact(
            modelVariantId: 'variant-01',
            sha256: 'abc',
            format: 'gguf',
            quantization: 'Q4_K_M',
            architecture: 'llama',
            compatibility: ModelRuntimeCompatibility(compatible: true),
          ),
          logicalModelId: 'qwen/qwen3.5-9b',
          roles: const {ModelRole.actor},
        ),
      );

      await runtime.unloadModel(handle);

      final genReq = TextGenerationRequest(
        requestId: const GenerationRequestId('gen-2'),
        model: handle,
        messages: const [
          InferenceMessage(role: InferenceRole.user, content: 'Test')
        ],
        traceContext: const InferenceTraceContext(
          traceId: RuntimeTraceId('trace-2'),
          sessionId: 'sess-1',
          agentId: 'actor',
          logicalModelId: 'qwen/qwen3.5-9b',
        ),
      );

      expect(
        () => runtime.generateText(genReq),
        throwsA(
          isA<RuntimeException>().having(
            (e) => e.failure.code,
            'code',
            equals(RuntimeFailureCode.invalidModelHandle),
          ),
        ),
      );
    });

    test('Health check returns correct state and responsiveness', () async {
      await runtime.initialize(
        const RuntimeInitializationRequest(
            instanceId: RuntimeInstanceId('sess-1')),
      );

      final h = await runtime.health();
      expect(h.instanceId, equals(const RuntimeInstanceId('sess-1')));
      expect(h.responsive, isTrue);
      expect(h.state, equals(RuntimeState.ready));
    });

    test('Dispose is idempotent and rejects further operations', () async {
      await runtime.initialize(
        const RuntimeInitializationRequest(
            instanceId: RuntimeInstanceId('sess-1')),
      );

      await runtime.dispose();
      expect(runtime.state, equals(RuntimeState.disposed));

      // Idempotent dispose
      await runtime.dispose();
      expect(runtime.state, equals(RuntimeState.disposed));

      final loadReq = ModelLoadRequest(
        requestId: const ModelLoadRequestId('load-after-dispose'),
        artifact: const ResolvedModelArtifact(
          modelVariantId: 'variant-01',
          sha256: 'abc',
          format: 'gguf',
          quantization: 'Q4_K_M',
          architecture: 'llama',
          compatibility: ModelRuntimeCompatibility(compatible: true),
        ),
        logicalModelId: 'mistralai/ministral-3-3b',
        roles: const {ModelRole.evaluator},
      );

      expect(
          () => runtime.loadModel(loadReq), throwsA(isA<RuntimeException>()));
    });
  });
}
