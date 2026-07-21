import 'package:aura_core/aura_offline.dart';
import 'package:test/test.dart';

void main() {
  group('Legacy and Runtime Bridge Behavioral Equivalence Tests -', () {
    late FakeExternalOpenAiClient fakeClient;
    late ExternalOpenAiRuntime runtime;
    late ModelHandle actorHandle;
    late ModelHandle evaluatorHandle;
    late RuntimeInferenceBridge runtimeBridge;

    setUp(() async {
      fakeClient = FakeExternalOpenAiClient();
      final config = ExternalOpenAiConfiguration(
        baseUri: Uri.parse('http://127.0.0.1:1234'),
        maxLoadedModels: 2,
        supportsMultipleLoadedModels: true,
      );

      runtime = ExternalOpenAiRuntime(
        configuration: config,
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

      await runtime.initialize(
        const RuntimeInitializationRequest(
          instanceId: RuntimeInstanceId('session-equivalence'),
        ),
      );

      actorHandle = await runtime.loadModel(
        const ModelLoadRequest(
          requestId: ModelLoadRequestId('load-actor'),
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

      evaluatorHandle = await runtime.loadModel(
        const ModelLoadRequest(
          requestId: ModelLoadRequestId('load-evaluator'),
          artifact: ResolvedModelArtifact(
            modelVariantId: 'v1',
            sha256: 'a',
            format: 'gguf',
            quantization: 'Q4',
            architecture: 'llama',
            compatibility: ModelRuntimeCompatibility(compatible: true),
          ),
          logicalModelId: 'aura.evaluator.primary',
          roles: {ModelRole.evaluator},
        ),
      );

      runtimeBridge = RuntimeInferenceBridge.fromHandleResolver(
        runtime: runtime,
        handleResolver: (role) {
          if (role == ModelRole.actor) return actorHandle;
          return evaluatorHandle;
        },
      );
    });

    tearDown(() async {
      if (runtime.state != RuntimeState.disposed) {
        await runtime.dispose();
      }
    });

    test(
        'Produces identical dialogue extraction output for XML tagged Actor response',
        () async {
      fakeClient.defaultResponseContent =
          "Thinking process...\n<dialogo>I miei protocolli rimangono inviolati e stabili.</dialogo>";

      final runtimeResult = await runtimeBridge.generateText(
        modelId: 'qwen/qwen3.5-9b',
        messages: [
          {'role': 'user', 'content': 'Stato della griglia?'}
        ],
      );

      // Verify ActorOutputSanitizer output through runtime bridge match expected characterization
      const expectedDialogue =
          'I miei protocolli rimangono inviolati e stabili.';
      expect(runtimeResult, equals(expectedDialogue));
    });

    test(
        'Propagates OutputPolicyFailure when CJK characters are detected in response',
        () async {
      fakeClient.defaultResponseContent = "你好, I am Panopticon.";

      expect(
        () => runtimeBridge.generateText(
          modelId: 'qwen/qwen3.5-9b',
          messages: [
            {'role': 'user', 'content': 'Hi'}
          ],
        ),
        throwsA(
          isA<OutputPolicyFailure>().having(
            (e) => e.code,
            'code',
            equals(OutputPolicyFailureCode.invalidCharacterSet),
          ),
        ),
      );
    });

    test('Propagates OutputPolicyFailure when duplicate response is generated',
        () async {
      const duplicateText = "I miei protocolli rimangono inviolati.";
      fakeClient.defaultResponseContent = duplicateText;

      expect(
        () => runtimeBridge.generateText(
          modelId: 'qwen/qwen3.5-9b',
          messages: [
            {'role': 'user', 'content': 'Test'},
            {'role': 'assistant', 'content': duplicateText},
          ],
        ),
        throwsA(
          isA<OutputPolicyFailure>().having(
            (e) => e.code,
            'code',
            equals(OutputPolicyFailureCode.duplicateResponse),
          ),
        ),
      );
    });

    test(
        'Translates thinking parameter to enable_thinking payload fields in HTTP client',
        () async {
      fakeClient.defaultResponseContent = "<dialogo>Thinking test</dialogo>";

      await runtimeBridge.generateText(
        modelId: 'qwen/qwen3.5-9b',
        messages: [
          {'role': 'user', 'content': 'Hello'}
        ],
        thinking: true,
      );

      expect(fakeClient.chatCompletionsCalls, equals(1));
    });
  });
}
