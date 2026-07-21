import 'package:aura_core/aura_testing.dart';
import 'package:aura_core/aura_offline.dart';
import 'package:test/test.dart';

void main() {
  group('RuntimeInferenceBridge Unit Tests -', () {
    late MockInferenceRuntime runtime;
    late ModelHandle actorHandle;
    late ModelHandle evaluatorHandle;
    late RuntimeInferenceBridge bridge;

    setUp(() async {
      runtime = MockInferenceRuntime();
      await runtime.initialize(
        const RuntimeInitializationRequest(
          instanceId: RuntimeInstanceId('session-bridge-test'),
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

      bridge = RuntimeInferenceBridge(
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
        'Resolves legacy model ID to role and executes Actor text generation with output policy',
        () async {
      runtime.textResponse =
          "Thinking process...\n<dialogo>I miei protocolli rimangono inviolati e stabili.</dialogo>";

      final response = await bridge.generateText(
        modelId: 'qwen/qwen3.5-9b',
        messages: [
          {'role': 'user', 'content': 'Stato della griglia?'}
        ],
      );

      expect(
          response, equals('I miei protocolli rimangono inviolati e stabili.'));
      expect(runtime.generateTextCalls, equals(1));
    });

    test(
        'Executes Evaluator text generation without narrative output sanitizer',
        () async {
      runtime.textResponse = "Evaluator raw text response";

      final response = await bridge.generateText(
        modelId: 'mistralai/ministral-3-3b',
        messages: [
          {'role': 'user', 'content': 'Valuta input'}
        ],
      );

      expect(response, equals('Evaluator raw text response'));
      expect(runtime.generateTextCalls, equals(1));
    });

    test(
        'Executes structured JSON generation without narrative output sanitizer',
        () async {
      runtime.structuredResponse = {
        'deltaAlert': 10,
        'deltaImperative': -5,
        'creativityIndex': 80,
      };

      final result = await bridge.generateStructured(
        modelId: 'mistralai/ministral-3-3b',
        messages: [
          {'role': 'user', 'content': 'Test input'}
        ],
        schema: {'type': 'object'},
      );

      expect(result['deltaAlert'], equals(10));
      expect(result['creativityIndex'], equals(80));
      expect(runtime.generateStructuredCalls, equals(1));
    });

    test('Owns timeout and invokes runtime.cancel on timeout', () async {
      runtime.autoCompleteRequests =
          false; // Prevents auto-completing text requests

      final shortTimeoutBridge = RuntimeInferenceBridge(
        runtime: runtime,
        handleResolver: (role) => actorHandle,
        timeoutPolicy: const RuntimeBridgeTimeoutPolicy(
          generationTimeout: Duration(milliseconds: 50),
          cancellationTimeout: Duration(milliseconds: 50),
        ),
      );

      await expectLater(
        shortTimeoutBridge.generateText(
          modelId: 'qwen/qwen3.5-9b',
          messages: [
            {'role': 'user', 'content': 'Test'}
          ],
        ),
        throwsA(
          isA<RuntimeException>().having(
            (e) => e.failure.code,
            'code',
            equals(RuntimeFailureCode.timeout),
          ),
        ),
      );

      // Verify cancel was requested on the runtime for the generated request ID
      expect(runtime.cancelCalls, equals(1));
    });
  });
}
