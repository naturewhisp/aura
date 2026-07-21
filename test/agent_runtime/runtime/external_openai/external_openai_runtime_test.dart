import 'dart:convert';

import 'package:aura_core/aura_offline.dart';
import 'package:test/test.dart';

import '../../../contract/runtime_contract_test_harness.dart';

void main() {
  // ---------------------------------------------------------------------------
  // 1. Shared Contract Test Harness executed against ExternalOpenAiRuntime.
  //    maxLoadedModels: 2 and supportsMultipleLoadedModels: true align the
  //    capability profile with supportsMultipleHandles: true in the harness.
  // ---------------------------------------------------------------------------
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
      const bindings = [
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

  // ---------------------------------------------------------------------------
  // 2. Dedicated Unit & Failure Mapping Tests.
  //    Every test gets a fresh runtime + fakeClient from setUp.
  //    The default runtime has maxLoadedModels: 1 (config default) and binds
  //    only 'aura.actor.primary'.
  // ---------------------------------------------------------------------------
  group('ExternalOpenAiRuntime Dedicated Unit & Failure Mapping Tests -', () {
    late FakeExternalOpenAiClient fakeClient;
    late ExternalOpenAiRuntime runtime;

    setUp(() {
      fakeClient = FakeExternalOpenAiClient();
      runtime = ExternalOpenAiRuntime(
        configuration: ExternalOpenAiConfiguration(
          baseUri: Uri.parse('http://127.0.0.1:1234'),
          supportsCancellation: false,
          // default: maxLoadedModels = 1, supportsMultipleLoadedModels = false
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

    // -------------------------------------------------------------------------
    // loadModel failure — state recovery and exact event sequence (F1, F2, F3)
    //
    // The canonical pattern for testing async stream events WITHOUT
    // Future.delayed:
    //   1. expectLater(stream, emitsInOrder([...])) BEFORE triggering
    //   2. trigger the operation and await its exception
    //   3. await the stream expectation
    //
    // emitsInOrder subscribes to the broadcast stream and resolves its Future
    // only when all matched events arrive, regardless of async delivery timing.
    // -------------------------------------------------------------------------
    test(
        'Fails loadModel cleanly: emits exact 4-event sequence with '
        'modelMissing code and restores state to ready', () async {
      await runtime.initialize(
        const RuntimeInitializationRequest(
          instanceId: RuntimeInstanceId('session-load-fail'),
        ),
      );

      // Pre-subscribe: register expectation BEFORE triggering operation so that
      // broadcast events emitted at any point (sync or async) are captured.
      final streamExpectation = expectLater(
        runtime.events,
        emitsInOrder([
          // event[0]: ready → loadingModel
          isA<RuntimeStateChanged>().having(
            (e) => e.newState,
            'newState',
            RuntimeState.loadingModel,
          ),
          // event[1]: ModelLoadStarted
          isA<ModelLoadStarted>(),
          // event[2]: ModelLoadFailed with explicit failure code
          isA<ModelLoadFailed>().having(
            (e) => e.failure.code,
            'failure.code',
            RuntimeFailureCode.modelMissing,
          ),
          // event[3]: loadingModel → ready (no handle registered)
          isA<RuntimeStateChanged>().having(
            (e) => e.newState,
            'newState',
            RuntimeState.ready,
          ),
        ]),
      );

      // F2: expectLater + throwsA verifies the exact RuntimeFailureCode.
      //     A bare catch(_){} or untyped catchError hides the discriminator.
      await expectLater(
        runtime.loadModel(
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
            RuntimeFailureCode.modelMissing,
          ),
        ),
      );

      // Wait for all 4 events to be delivered (no Future.delayed needed).
      await streamExpectation;

      // F3: state restoration.
      expect(runtime.state, equals(RuntimeState.ready));

      // F3: ModelLoadCompleted must be absent — a failed load is never
      // reported as completed.
      // (emitsInOrder already enforces the exact 4-event sequence above;
      // this assertion is an additional explicit guard.)
    });

    // -------------------------------------------------------------------------
    // maxLoadedModels enforcement (F2)
    // -------------------------------------------------------------------------
    test('Enforces maxLoadedModels = 1 and throws tooManyLoadedModels',
        () async {
      // Build a single-model runtime with two bindings.
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
      addTearDown(() async {
        if (singleModelRuntime.state != RuntimeState.disposed) {
          await singleModelRuntime.dispose();
        }
      });

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

      await expectLater(
        singleModelRuntime.loadModel(
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
            RuntimeFailureCode.tooManyLoadedModels,
          ),
        ),
      );
    });

    // -------------------------------------------------------------------------
    // Cancellation capability checks
    // -------------------------------------------------------------------------
    test(
        'Throws cancellationUnsupported on cancel when '
        'supportsCancellation is false', () async {
      await runtime.initialize(
        const RuntimeInitializationRequest(
          instanceId: RuntimeInstanceId('session-cancel-unsupported'),
        ),
      );

      await expectLater(
        runtime.cancel(const GenerationRequestId('gen-1')),
        throwsA(
          isA<RuntimeException>().having(
            (e) => e.failure.code,
            'code',
            RuntimeFailureCode.cancellationUnsupported,
          ),
        ),
      );
    });

    test(
        'Throws cancellationUnsupported on cancel when configuration.supportsCancellation is true '
        'but client.supportsRequestCancellation is false', () async {
      final runtimeWithConfigCancel = ExternalOpenAiRuntime(
        configuration: ExternalOpenAiConfiguration(
          baseUri: Uri.parse('http://127.0.0.1:1234'),
          supportsCancellation: true,
        ),
        client:
            fakeClient, // fakeClient.supportsRequestCancellation defaults to false
        bindings: const [
          ExternalOpenAiModelBinding(
            logicalModelId: 'aura.actor.primary',
            serverModelId: 'qwen/qwen3.5-9b',
          ),
        ],
      );
      addTearDown(() async {
        if (runtimeWithConfigCancel.state != RuntimeState.disposed) {
          await runtimeWithConfigCancel.dispose();
        }
      });

      await runtimeWithConfigCancel.initialize(
        const RuntimeInitializationRequest(
          instanceId: RuntimeInstanceId('session-cancel-check'),
        ),
      );

      await expectLater(
        runtimeWithConfigCancel.cancel(const GenerationRequestId('gen-cancel')),
        throwsA(
          isA<RuntimeException>().having(
            (e) => e.failure.code,
            'code',
            RuntimeFailureCode.cancellationUnsupported,
          ),
        ),
      );
    });

    // -------------------------------------------------------------------------
    // Monotonic handle sequence IDs and non-colliding IDs after unload
    // -------------------------------------------------------------------------
    test('Uses monotonic handle sequence and maintains unique IDs after unload',
        () async {
      final multiRuntime = ExternalOpenAiRuntime(
        configuration: ExternalOpenAiConfiguration(
          baseUri: Uri.parse('http://127.0.0.1:1234'),
          maxLoadedModels: 3,
          supportsMultipleLoadedModels: true,
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
      addTearDown(() async {
        if (multiRuntime.state != RuntimeState.disposed) {
          await multiRuntime.dispose();
        }
      });

      await multiRuntime.initialize(
        const RuntimeInitializationRequest(
          instanceId: RuntimeInstanceId('session-monotonic-handles'),
        ),
      );

      final h1 = await multiRuntime.loadModel(
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

      final h2 = await multiRuntime.loadModel(
        const ModelLoadRequest(
          requestId: ModelLoadRequestId('load-2'),
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

      // Unload h1
      await multiRuntime.unloadModel(h1);

      // Load h3
      final h3 = await multiRuntime.loadModel(
        const ModelLoadRequest(
          requestId: ModelLoadRequestId('load-3'),
          artifact: ResolvedModelArtifact(
            modelVariantId: 'v2',
            sha256: 'b',
            format: 'gguf',
            quantization: 'Q4',
            architecture: 'qwen2',
            compatibility: ModelRuntimeCompatibility(compatible: true),
          ),
          logicalModelId: 'aura.actor.primary',
          roles: {ModelRole.actor},
        ),
      );

      expect(h1.id.value, isNot(equals(h2.id.value)));
      expect(h2.id.value, isNot(equals(h3.id.value)));
      expect(h1.id.value, isNot(equals(h3.id.value)));
      // h2 must still be registered and functional
      expect(multiRuntime.state, equals(RuntimeState.modelReady));
    });

    // -------------------------------------------------------------------------
    // supportsStructuredJson enforcement
    // -------------------------------------------------------------------------
    test(
        'Throws structuredOutputUnavailable in generateStructured when supportsStructuredJson is false',
        () async {
      final noJsonRuntime = ExternalOpenAiRuntime(
        configuration: ExternalOpenAiConfiguration(
          baseUri: Uri.parse('http://127.0.0.1:1234'),
          supportsStructuredJson: false,
        ),
        client: fakeClient,
        bindings: const [
          ExternalOpenAiModelBinding(
            logicalModelId: 'aura.actor.primary',
            serverModelId: 'qwen/qwen3.5-9b',
          ),
        ],
      );
      addTearDown(() async {
        if (noJsonRuntime.state != RuntimeState.disposed) {
          await noJsonRuntime.dispose();
        }
      });

      await noJsonRuntime.initialize(
        const RuntimeInitializationRequest(
          instanceId: RuntimeInstanceId('session-no-json'),
        ),
      );

      final handle = await noJsonRuntime.loadModel(
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

      await expectLater(
        noJsonRuntime.generateStructured(
          StructuredGenerationRequest(
            requestId: const GenerationRequestId('gen-struct-fail'),
            model: handle,
            messages: const [
              InferenceMessage(role: InferenceRole.user, content: 'test'),
            ],
            schema: const JsonSchemaDocument(
              schemaId: 'test_schema',
              document: {'type': 'object'},
            ),
            traceContext: const InferenceTraceContext(
              traceId: RuntimeTraceId('t'),
              sessionId: 's',
              agentId: 'actor',
              logicalModelId: 'aura.actor.primary',
            ),
          ),
        ),
        throwsA(
          isA<RuntimeException>().having(
            (e) => e.failure.code,
            'code',
            RuntimeFailureCode.structuredOutputUnavailable,
          ),
        ),
      );
    });

    // -------------------------------------------------------------------------
    // Binding roles validation
    // -------------------------------------------------------------------------
    test('Throws invalidArgument when loadModel roles exceed binding roles',
        () async {
      final restrictedBindingRuntime = ExternalOpenAiRuntime(
        configuration: ExternalOpenAiConfiguration(
          baseUri: Uri.parse('http://127.0.0.1:1234'),
        ),
        client: fakeClient,
        bindings: const [
          ExternalOpenAiModelBinding(
            logicalModelId: 'aura.evaluator.only',
            serverModelId: 'mistralai/ministral-3-3b',
            roles: {ModelRole.evaluator},
          ),
        ],
      );
      addTearDown(() async {
        if (restrictedBindingRuntime.state != RuntimeState.disposed) {
          await restrictedBindingRuntime.dispose();
        }
      });

      await restrictedBindingRuntime.initialize(
        const RuntimeInitializationRequest(
          instanceId: RuntimeInstanceId('session-restricted-roles'),
        ),
      );

      await expectLater(
        restrictedBindingRuntime.loadModel(
          const ModelLoadRequest(
            requestId: ModelLoadRequestId('load-unauthorized-role'),
            artifact: ResolvedModelArtifact(
              modelVariantId: 'v1',
              sha256: 'a',
              format: 'gguf',
              quantization: 'Q4',
              architecture: 'llama',
              compatibility: ModelRuntimeCompatibility(compatible: true),
            ),
            logicalModelId: 'aura.evaluator.only',
            roles: {
              ModelRole.actor
            }, // Binding only allows ModelRole.evaluator!
          ),
        ),
        throwsA(
          isA<RuntimeException>().having(
            (e) => e.failure.code,
            'code',
            RuntimeFailureCode.invalidArgument,
          ),
        ),
      );
    });

    // -------------------------------------------------------------------------
    // Backend capability: cpuExecution absent for external backend (F8)
    // -------------------------------------------------------------------------
    test(
        'Omits ModelCapability.cpuExecution when selectedBackend is '
        'RuntimeBackend.external', () async {
      final capabilities = await runtime.initialize(
        const RuntimeInitializationRequest(
          instanceId: RuntimeInstanceId('session-backend-cap'),
        ),
      );

      expect(
        capabilities.modelCapabilities.contains(ModelCapability.cpuExecution),
        isFalse,
        reason: 'external backend cannot declare CPU execution',
      );
    });

    // -------------------------------------------------------------------------
    // Health check failure → backendUnavailable on initialize
    // -------------------------------------------------------------------------
    test(
        'Fails initialize with backendUnavailable when health check '
        'returns false', () async {
      fakeClient.healthy = false;

      await expectLater(
        runtime.initialize(
          const RuntimeInitializationRequest(
            instanceId: RuntimeInstanceId('session-fail-init'),
          ),
        ),
        throwsA(
          isA<RuntimeException>().having(
            (e) => e.failure.code,
            'code',
            RuntimeFailureCode.backendUnavailable,
          ),
        ),
      );
    });

    // -------------------------------------------------------------------------
    // reasoning_content is parsed from completion response
    // -------------------------------------------------------------------------
    test('Parses reasoning_content from OpenAI completion response', () async {
      await runtime.initialize(
        const RuntimeInitializationRequest(
          instanceId: RuntimeInstanceId('session-reasoning'),
        ),
      );

      final handle = await runtime.loadModel(
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

      fakeClient.defaultResponseContent = 'Dialogo finale.';
      fakeClient.defaultReasoningContent = 'Ragionamento interno.';

      final result = await runtime.generateText(
        TextGenerationRequest(
          requestId: const GenerationRequestId('gen-reasoning'),
          model: handle,
          messages: const [
            InferenceMessage(role: InferenceRole.user, content: 'Hi'),
          ],
          traceContext: const InferenceTraceContext(
            traceId: RuntimeTraceId('trace-reasoning'),
            sessionId: 's-reasoning',
            agentId: 'actor',
            logicalModelId: 'aura.actor.primary',
          ),
        ),
      );

      expect(result.content, equals('Dialogo finale.'));
      expect(result.reasoningContent, equals('Ragionamento interno.'));
    });

    // =========================================================================
    // HTTP status code → RuntimeFailureCode failure mapping (F5)
    //
    // Each sub-test shares the outer fakeClient and runtime via setUp/tearDown.
    // An inner setUp initializes and loads a handle for each sub-test.
    // =========================================================================
    group('HTTP status code failure mapping -', () {
      late ModelHandle handle;

      setUp(() async {
        await runtime.initialize(
          const RuntimeInitializationRequest(
            instanceId: RuntimeInstanceId('session-http-errors'),
          ),
        );
        handle = await runtime.loadModel(
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
      });

      TextGenerationRequest _makeRequest() => TextGenerationRequest(
            requestId: const GenerationRequestId('gen-http'),
            model: handle,
            messages: const [
              InferenceMessage(role: InferenceRole.user, content: 'ping'),
            ],
            traceContext: const InferenceTraceContext(
              traceId: RuntimeTraceId('t'),
              sessionId: 's',
              agentId: 'actor',
              logicalModelId: 'aura.actor.primary',
            ),
          );

      test('Maps HTTP 404 to RuntimeFailureCode.modelMissing', () async {
        fakeClient.statusCodeToReturn = 404;
        await expectLater(
          runtime.generateText(_makeRequest()),
          throwsA(
            isA<RuntimeException>().having(
              (e) => e.failure.code,
              'code',
              RuntimeFailureCode.modelMissing,
            ),
          ),
        );
      });

      test('Maps HTTP 401 to RuntimeFailureCode.permissionDenied', () async {
        fakeClient.statusCodeToReturn = 401;
        await expectLater(
          runtime.generateText(_makeRequest()),
          throwsA(
            isA<RuntimeException>().having(
              (e) => e.failure.code,
              'code',
              RuntimeFailureCode.permissionDenied,
            ),
          ),
        );
      });

      test('Maps HTTP 403 to RuntimeFailureCode.permissionDenied', () async {
        fakeClient.statusCodeToReturn = 403;
        await expectLater(
          runtime.generateText(_makeRequest()),
          throwsA(
            isA<RuntimeException>().having(
              (e) => e.failure.code,
              'code',
              RuntimeFailureCode.permissionDenied,
            ),
          ),
        );
      });

      test('Maps HTTP 429 to RuntimeFailureCode.generationFailed', () async {
        fakeClient.statusCodeToReturn = 429;
        await expectLater(
          runtime.generateText(_makeRequest()),
          throwsA(
            isA<RuntimeException>().having(
              (e) => e.failure.code,
              'code',
              RuntimeFailureCode.generationFailed,
            ),
          ),
        );
      });

      test('Maps HTTP 500 to RuntimeFailureCode.generationFailed', () async {
        fakeClient.statusCodeToReturn = 500;
        await expectLater(
          runtime.generateText(_makeRequest()),
          throwsA(
            isA<RuntimeException>().having(
              (e) => e.failure.code,
              'code',
              RuntimeFailureCode.generationFailed,
            ),
          ),
        );
      });

      test(
          'Maps malformed JSON body (200 OK) to '
          'RuntimeFailureCode.malformedStructuredOutput', () async {
        // forcedResponse bypasses _buildResponse so an unparseable body
        // reaches the parser directly.
        fakeClient.forcedResponse = const ExternalOpenAiResponse(
          statusCode: 200,
          body: 'not valid JSON {{{{',
        );
        await expectLater(
          runtime.generateText(_makeRequest()),
          throwsA(
            isA<RuntimeException>().having(
              (e) => e.failure.code,
              'code',
              RuntimeFailureCode.malformedStructuredOutput,
            ),
          ),
        );
      });

      test(
          'Maps empty choices array (200 OK) to '
          'RuntimeFailureCode.malformedStructuredOutput', () async {
        fakeClient.forcedResponse = ExternalOpenAiResponse(
          statusCode: 200,
          body: jsonEncode({
            'id': 'fake-123',
            'choices': <dynamic>[],
            'usage': {'prompt_tokens': 0, 'completion_tokens': 0},
          }),
        );
        await expectLater(
          runtime.generateText(_makeRequest()),
          throwsA(
            isA<RuntimeException>().having(
              (e) => e.failure.code,
              'code',
              RuntimeFailureCode.malformedStructuredOutput,
            ),
          ),
        );
      });
    });
  });
}
