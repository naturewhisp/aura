import 'package:aura_core/aura_testing.dart';
import 'package:aura_core/aura_offline.dart';
import 'package:test/test.dart';

void main() {
  group('RuntimeInferenceBridge Comprehensive Unit Tests -', () {
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

      bridge = RuntimeInferenceBridge.fromHandleResolver(
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
        'Throws RuntimeFailureCode.modelMissing on unknown legacy model ID route',
        () async {
      expect(
        () => bridge.generateText(
          modelId: 'unknown/unregistered-model',
          messages: [
            {'role': 'user', 'content': 'Test'}
          ],
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

    test('Uses explicit RuntimeModelExecutionPlan in planResolver', () async {
      final customBridge = RuntimeInferenceBridge(
        runtime: runtime,
        planResolver: (role) {
          final handle =
              (role == ModelRole.actor) ? actorHandle : evaluatorHandle;
          return RuntimeModelExecutionPlan(
            role: role,
            logicalModelId: handle.logicalModelId,
            handle: handle,
          );
        },
      );

      runtime.textResponse = "<dialogo>Risposta attore</dialogo>";
      final result = await customBridge.generateText(
        modelId: 'aura.actor.primary',
        messages: [
          {'role': 'user', 'content': 'Hi'}
        ],
      );

      expect(result, equals('Risposta attore'));
    });

    test(
        'Handles timeout deterministically and captures cancellation unsupported status',
        () async {
      runtime.autoCompleteRequests = false;
      runtime.throwOnCancellation = true;

      final timeoutBridge = RuntimeInferenceBridge.fromHandleResolver(
        runtime: runtime,
        handleResolver: (role) => actorHandle,
        timeoutScheduler:
            const FakeTimeoutScheduler(shouldTriggerTimeout: true),
      );

      expect(
        () => timeoutBridge.generateText(
          modelId: 'qwen/qwen3.5-9b',
          messages: [
            {'role': 'user', 'content': 'Test timeout'}
          ],
        ),
        throwsA(
          isA<RuntimeException>().having(
            (e) => e.failure.diagnostics['cancellationDisposition'],
            'cancellationDisposition',
            equals('cancellationUnsupported'),
          ),
        ),
      );
    });

    test('Returns only registered legacy routes in discoverModels()', () async {
      final routes = await bridge.discoverModels();

      expect(routes, contains('qwen/qwen3.5-9b'));
      expect(routes, contains('mistralai/ministral-3-3b'));
      expect(routes, contains('aura.actor.primary'));
      expect(routes, contains('aura.evaluator.primary'));
    });
  });
}
