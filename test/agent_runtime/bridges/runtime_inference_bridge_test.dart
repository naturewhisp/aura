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
        'Resolves legacy model ID to role and executes Actor text generation '
        'with output policy', () async {
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
      runtime.textResponse = 'Evaluator raw text response';

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
        'Throws RuntimeFailureCode.modelMissing on unknown legacy model ID '
        'route', () async {
      // routeResolver.resolveRole throws synchronously before any await, so
      // the Future is immediately rejected.  expectLater correctly awaits it.
      await expectLater(
        bridge.generateText(
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

    test('Throws RuntimeFailureCode.invalidArgument on unknown message role',
        () async {
      await expectLater(
        bridge.generateText(
          modelId: 'qwen/qwen3.5-9b',
          messages: [
            {'role': 'unsupported_role', 'content': 'Hello'}
          ],
        ),
        throwsA(
          isA<RuntimeException>().having(
            (e) => e.failure.code,
            'code',
            equals(RuntimeFailureCode.invalidArgument),
          ),
        ),
      );
    });

    test('Validates execution plan and throws invalidState on role mismatch',
        () async {
      final mismatchedBridge = RuntimeInferenceBridge(
        runtime: runtime,
        planResolver: (role) => RuntimeModelExecutionPlan(
          role: ModelRole.evaluator, // mismatched when actor is requested
          logicalModelId: 'aura.actor.primary',
          handle: actorHandle,
        ),
      );

      await expectLater(
        mismatchedBridge.generateText(
          modelId: 'qwen/qwen3.5-9b',
          messages: [
            {'role': 'user', 'content': 'Hi'}
          ],
        ),
        throwsA(
          isA<RuntimeException>().having(
            (e) => e.failure.code,
            'code',
            equals(RuntimeFailureCode.invalidState),
          ),
        ),
      );
    });

    test('Maps thinking:true to ThinkingPolicy.enabled', () async {
      runtime.textResponse = '<dialogo>Thought response</dialogo>';

      await bridge.generateText(
        modelId: 'qwen/qwen3.5-9b',
        messages: [
          {'role': 'user', 'content': 'Test thinking'}
        ],
        thinking: true,
      );

      expect(
        runtime.textRequests.single.parameters.thinkingPolicy,
        equals(ThinkingPolicy.enabled),
      );
    });

    test('Maps thinking:false to ThinkingPolicy.disabled', () async {
      runtime.textResponse = '<dialogo>Response</dialogo>';

      await bridge.generateText(
        modelId: 'qwen/qwen3.5-9b',
        messages: [
          {'role': 'user', 'content': 'Test no thinking'}
        ],
        thinking: false,
      );

      expect(
        runtime.textRequests.single.parameters.thinkingPolicy,
        equals(ThinkingPolicy.disabled),
      );
    });

    test('Maps thinking:null to ThinkingPolicy.runtimeDefault', () async {
      runtime.textResponse = '<dialogo>Default response</dialogo>';

      await bridge.generateText(
        modelId: 'qwen/qwen3.5-9b',
        messages: [
          {'role': 'user', 'content': 'Test default thinking'}
        ],
        // thinking: null is the default
      );

      expect(
        runtime.textRequests.single.parameters.thinkingPolicy,
        equals(ThinkingPolicy.runtimeDefault),
      );
    });

    test(
        'Handles generation timeout deterministically using explicit '
        'TimeoutTarget.generation — captures cancellationUnsupported status',
        () async {
      runtime.autoCompleteRequests = false;
      runtime.throwOnCancellation = true;

      final timeoutBridge = RuntimeInferenceBridge.fromHandleResolver(
        runtime: runtime,
        handleResolver: (role) => actorHandle,
        // FakeTimeoutScheduler with shouldTriggerTimeout: true fires the
        // onTimeout handler when target == TimeoutTarget.generation.
        // No duration heuristic is used.
        timeoutScheduler:
            const FakeTimeoutScheduler(shouldTriggerTimeout: true),
      );

      await expectLater(
        timeoutBridge.generateText(
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
