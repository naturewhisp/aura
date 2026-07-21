import 'package:aura_core/aura_offline.dart';
import 'package:aura_core/aura_testing.dart';
import 'package:test/test.dart';

void main() {
  group('ManagedLlamaServerRuntime Tests', () {
    const config = ManagedLlamaServerConfiguration(
      executablePath: 'llama-server.exe',
      modelPath: 'model.gguf',
      modelAlias: 'test-model',
    );

    late LlamaServerProcessSupervisor supervisor;
    late ManagedLlamaServerRuntime runtime;

    setUp(() {
      supervisor = LlamaServerProcessSupervisor(
        configuration: config,
        processLauncher: FakeProcessLauncher(),
        portAllocator: const FakePortAllocator(allocatedPort: 8080),
        healthProbe:
            FakeLlamaServerHealthProbe(isResponsive: true, modelVisible: true),
      );

      runtime = ManagedLlamaServerRuntime(
        configuration: config,
        supervisor: supervisor,
        delegateFactory: (clientConfig, bindings) => ExternalOpenAiRuntime(
          configuration: clientConfig,
          client: FakeExternalOpenAiClient(healthy: true),
          bindings: bindings,
        ),
      );
    });

    tearDown(() async {
      await runtime.dispose();
    });

    test(
        'initialize starts supervisor and prepares delegate runtime capabilities',
        () async {
      final capabilities = await runtime.initialize();

      expect(capabilities.runtimeName, equals('llama-server'));
      expect(capabilities.maxLoadedModels, equals(1));
      expect(capabilities.extensions['managed'], isTrue);
      expect(capabilities.extensions['allocatedPort'], equals(8080));
    });

    test(
        'loadModel creates model handle and rejects conflicting second physical model',
        () async {
      await runtime.initialize();

      final loadReq = ModelLoadRequest(
        requestId: const ModelLoadRequestId('load-1'),
        artifact: ResolvedModelArtifact(
          modelVariantId: 'test-model',
          sha256: 'sha',
          format: 'gguf',
          quantization: 'q4',
          architecture: 'llama',
          compatibility: const ModelRuntimeCompatibility(compatible: true),
          localArtifactUri: Uri.file('model.gguf'),
        ),
        logicalModelId: 'aura.actor.primary',
        roles: const {ModelRole.actor, ModelRole.evaluator},
      );

      final handle = await runtime.loadModel(loadReq);

      expect(handle.logicalModelId, equals('aura.actor.primary'));

      final loadReq2 = ModelLoadRequest(
        requestId: const ModelLoadRequestId('load-2'),
        artifact: ResolvedModelArtifact(
          modelVariantId: 'different-model',
          sha256: 'sha2',
          format: 'gguf',
          quantization: 'q4',
          architecture: 'llama',
          compatibility: const ModelRuntimeCompatibility(compatible: true),
          localArtifactUri: Uri.file('different_model.gguf'),
        ),
        logicalModelId: 'aura.evaluator.secondary',
        roles: const {ModelRole.evaluator},
      );

      expect(
        () => runtime.loadModel(loadReq2),
        throwsA(isA<RuntimeException>().having(
          (e) => e.failure.code,
          'code',
          equals(RuntimeFailureCode.unsupportedCapability),
        )),
      );
    });

    test('generateText and generateStructured are delegated successfully',
        () async {
      await runtime.initialize();

      final handle = await runtime.loadModel(
        ModelLoadRequest(
          requestId: const ModelLoadRequestId('load-1'),
          artifact: ResolvedModelArtifact(
            modelVariantId: 'test-model',
            sha256: 'sha',
            format: 'gguf',
            quantization: 'q4',
            architecture: 'llama',
            compatibility: const ModelRuntimeCompatibility(compatible: true),
            localArtifactUri: Uri.file('model.gguf'),
          ),
          logicalModelId: 'aura.actor.primary',
          roles: const {ModelRole.actor, ModelRole.evaluator},
        ),
      );

      final textRes = await runtime.generateText(
        TextGenerationRequest(
          requestId: const GenerationRequestId('req-1'),
          model: handle,
          messages: const [
            InferenceMessage(role: InferenceRole.user, content: 'Hello')
          ],
          traceContext: const InferenceTraceContext(
            traceId: RuntimeTraceId('t-1'),
            sessionId: 's-1',
            agentId: 'a-1',
            logicalModelId: 'aura.actor.primary',
          ),
        ),
      );

      expect(textRes.content, isNotEmpty);

      final structuredRes = await runtime.generateStructured(
        StructuredGenerationRequest(
          requestId: const GenerationRequestId('req-2'),
          model: handle,
          messages: const [
            InferenceMessage(role: InferenceRole.user, content: 'Evaluate')
          ],
          schema: const JsonSchemaDocument(
              schemaId: 'schema-1', document: {'type': 'object'}),
          traceContext: const InferenceTraceContext(
            traceId: RuntimeTraceId('t-2'),
            sessionId: 's-1',
            agentId: 'eval-1',
            logicalModelId: 'aura.evaluator.primary',
          ),
        ),
      );

      expect(structuredRes.rawContent, isNotEmpty);
    });

    test('health combines supervisor status and delegate health', () async {
      await runtime.initialize();

      final health = await runtime.health();

      expect(health.responsive, isTrue);
      expect(health.state, equals(RuntimeState.ready));
    });

    test('dispose is idempotent and single-flight', () async {
      await runtime.initialize();

      final f1 = runtime.dispose();
      final f2 = runtime.dispose();

      await f1;
      await f2;

      expect(supervisor.state, equals(LlamaServerSupervisorState.disposed));
    });
  });
}
