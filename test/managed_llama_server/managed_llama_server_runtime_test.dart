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
        fileSystem: const FakeFileSystem(
          existingFiles: {'llama-server.exe', 'model.gguf'},
        ),
      );

      runtime = ManagedLlamaServerRuntime(
        configuration: config,
        supervisor: supervisor,
        delegateFactory: (clientConfig, bindings) => ExternalOpenAiRuntime(
          configuration: clientConfig,
          client: FakeExternalOpenAiClient(
              healthy: true, availableModels: const ['test-model']),
          bindings: bindings,
        ),
      );
    });

    tearDown(() async {
      try {
        await runtime.dispose();
      } catch (_) {}
    });

    test(
        'initialize starts supervisor and prepares delegate runtime capabilities without leaking port/pid',
        () async {
      final capabilities = await runtime.initialize();

      expect(capabilities.runtimeName, equals('llama-server'));
      expect(capabilities.maxLoadedModels, equals(1));
      expect(
          capabilities.modelCapabilities
              .contains(ModelCapability.multipleLoadedModels),
          isFalse);
      expect(capabilities.extensions['managed'], isTrue);
      // Info Hiding: non deve esporre porta o PID nelle capabilities pubbliche
      expect(capabilities.extensions.containsKey('allocatedPort'), isFalse);
      expect(capabilities.extensions.containsKey('pid'), isFalse);
    });

    test(
        'loadModel allows multiple logical handles on the same physical model alias',
        () async {
      await runtime.initialize();

      final loadReq1 = ModelLoadRequest(
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
        roles: const {ModelRole.actor},
      );

      final handle1 = await runtime.loadModel(loadReq1);
      expect(handle1.logicalModelId, equals('aura.actor.primary'));

      final loadReq2 = ModelLoadRequest(
        requestId: const ModelLoadRequestId('load-2'),
        artifact: ResolvedModelArtifact(
          modelVariantId: 'test-model',
          sha256: 'sha',
          format: 'gguf',
          quantization: 'q4',
          architecture: 'llama',
          compatibility: const ModelRuntimeCompatibility(compatible: true),
          localArtifactUri: Uri.file('model.gguf'),
        ),
        logicalModelId: 'aura.evaluator.primary',
        roles: const {ModelRole.evaluator},
      );

      // Dev'essere caricato con successo (stesso alias fisico, ID logico differente)
      final handle2 = await runtime.loadModel(loadReq2);
      expect(handle2.logicalModelId, equals('aura.evaluator.primary'));

      final loadReq3 = ModelLoadRequest(
        requestId: const ModelLoadRequestId('load-3'),
        artifact: ResolvedModelArtifact(
          modelVariantId: 'different-physical-model',
          sha256: 'sha2',
          format: 'gguf',
          quantization: 'q4',
          architecture: 'llama',
          compatibility: const ModelRuntimeCompatibility(compatible: true),
          localArtifactUri: Uri.file('different_model.gguf'),
        ),
        logicalModelId: 'aura.actor.secondary',
        roles: const {ModelRole.actor},
      );

      // Deve rifiutare un modello fisico differente
      expect(
        () => runtime.loadModel(loadReq3),
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

    test(
        'health combines supervisor status and delegate health without exposing port/pid',
        () async {
      await runtime.initialize();

      final health = await runtime.health();

      expect(health.responsive, isTrue);
      expect(health.state, equals(RuntimeState.ready));
      // Info Hiding check
      expect(
          health.warnings.any((w) =>
              w.message.contains('allocatedPort') || w.message.contains('pid')),
          isFalse);
    });

    test(
        'Map ManagedLlamaServerException to RuntimeException on initialize failure',
        () async {
      final badSupervisor = LlamaServerProcessSupervisor(
        configuration: config,
        processLauncher: FakeProcessLauncher(shouldFail: true),
        portAllocator: const FakePortAllocator(allocatedPort: 8080),
        healthProbe: FakeLlamaServerHealthProbe(isResponsive: true),
        fileSystem: const FakeFileSystem(
          existingFiles: {'llama-server.exe', 'model.gguf'},
        ),
      );

      final badRuntime = ManagedLlamaServerRuntime(
        configuration: config,
        supervisor: badSupervisor,
        delegateFactory: (clientConfig, bindings) => ExternalOpenAiRuntime(
          configuration: clientConfig,
          client: FakeExternalOpenAiClient(
              healthy: true, availableModels: const ['test-model']),
          bindings: bindings,
        ),
      );

      expect(
        badRuntime.initialize(),
        throwsA(isA<RuntimeException>().having(
          (e) => e.failure.code,
          'code',
          equals(RuntimeFailureCode.runtimeInitializationFailed),
        )),
      );
    });

    test(
        'dispose propagates grouped errors on failure but completes best-effort',
        () async {
      final errorSupervisor = LlamaServerProcessSupervisor(
        configuration: config,
        processLauncher: FakeProcessLauncher(
            process: FakeManagedProcess()..killResult = false),
        portAllocator: const FakePortAllocator(allocatedPort: 8080),
        healthProbe: FakeLlamaServerHealthProbe(isResponsive: true),
        fileSystem: const FakeFileSystem(
          existingFiles: {'llama-server.exe', 'model.gguf'},
        ),
      );

      final errorRuntime = ManagedLlamaServerRuntime(
        configuration: config,
        supervisor: errorSupervisor,
        delegateFactory: (clientConfig, bindings) => ExternalOpenAiRuntime(
          configuration: clientConfig,
          client: FakeExternalOpenAiClient(
              healthy: true, availableModels: const ['test-model']),
          bindings: bindings,
        ),
      );

      await errorRuntime.initialize();

      expect(
        errorRuntime.dispose(),
        throwsA(isA<RuntimeException>().having(
          (e) => e.failure.code,
          'code',
          equals(RuntimeFailureCode.invalidState),
        )),
      );

      expect(errorRuntime.state, equals(RuntimeState.disposed));
    });
  });
}
