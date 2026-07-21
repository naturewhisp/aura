import 'dart:async';
import 'package:aura_core/aura_testing.dart';
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
        logicalModelId: 'aura.evaluator.primary',
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
        logicalModelId: 'aura.evaluator.primary',
        roles: const {ModelRole.evaluator},
      );

      final handle = await runtime.loadModel(loadReq);
      expect(handle.logicalModelId, equals('aura.evaluator.primary'));
      expect(
          handle.runtimeInstanceId, equals(const RuntimeInstanceId('sess-1')));
      expect(runtime.state, equals(RuntimeState.modelReady));
    });

    test('Rejects handle belonging to another session or instance', () async {
      await runtime.initialize(
        const RuntimeInitializationRequest(
            instanceId: RuntimeInstanceId('sess-1')),
      );

      final foreignHandle = ModelHandle(
        id: const ModelHandleId('foreign-handle'),
        runtimeInstanceId: const RuntimeInstanceId('other-session'),
        logicalModelId: 'aura.evaluator.primary',
        modelVariantId: 'variant-01',
        roles: const {ModelRole.evaluator},
        loadedAt: DateTime.now(),
      );

      final genReq = TextGenerationRequest(
        requestId: const GenerationRequestId('gen-1'),
        model: foreignHandle,
        messages: const [
          InferenceMessage(role: InferenceRole.user, content: 'Hi')
        ],
        traceContext: const InferenceTraceContext(
          traceId: RuntimeTraceId('trace-1'),
          sessionId: 'sess-1',
          agentId: 'evaluator',
          logicalModelId: 'aura.evaluator.primary',
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
          logicalModelId: 'aura.actor.primary',
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
          logicalModelId: 'aura.actor.primary',
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
          logicalModelId: 'aura.evaluator.primary',
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
          logicalModelId: 'aura.evaluator.primary',
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
          logicalModelId: 'aura.actor.primary',
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
          logicalModelId: 'aura.actor.primary',
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

    group('Cancellation semantics -', () {
      test(
          'Cancels generation or throws cancellationUnsupported based on capability',
          () async {
        await runtime.initialize(
          const RuntimeInitializationRequest(
              instanceId: RuntimeInstanceId('sess-cancel')),
        );

        final handle = await runtime.loadModel(
          ModelLoadRequest(
            requestId: const ModelLoadRequestId('load-cancel'),
            artifact: const ResolvedModelArtifact(
              modelVariantId: 'variant-01',
              sha256: 'abc',
              format: 'gguf',
              quantization: 'Q4_K_M',
              architecture: 'llama',
              compatibility: ModelRuntimeCompatibility(compatible: true),
            ),
            logicalModelId: 'aura.actor.primary',
            roles: const {ModelRole.actor},
          ),
        );

        if (!profile.supportsCancellation) {
          expect(
            () => runtime.cancel(const GenerationRequestId('req-1')),
            throwsA(
              isA<RuntimeException>().having(
                (e) => e.failure.code,
                'code',
                equals(RuntimeFailureCode.cancellationUnsupported),
              ),
            ),
          );
        } else if (runtime is MockInferenceRuntime) {
          final mock = runtime as MockInferenceRuntime;
          mock.autoCompleteRequests = false;

          final genFuture = mock.generateText(
            TextGenerationRequest(
              requestId: const GenerationRequestId('req-pending-cancel'),
              model: handle,
              messages: const [
                InferenceMessage(role: InferenceRole.user, content: 'Wait')
              ],
              traceContext: const InferenceTraceContext(
                traceId: RuntimeTraceId('trace-cancel'),
                sessionId: 'sess-cancel',
                agentId: 'actor',
                logicalModelId: 'aura.actor.primary',
              ),
            ),
          );

          final expectCancelFuture = expectLater(
            genFuture,
            throwsA(
              isA<RuntimeException>().having(
                (e) => e.failure.code,
                'code',
                equals(RuntimeFailureCode.cancelled),
              ),
            ),
          );

          await runtime.cancel(const GenerationRequestId('req-pending-cancel'));
          await expectCancelFuture;

          // Verify model handle remains valid post-cancellation
          mock.autoCompleteRequests = true;
          final res = await mock.generateText(
            TextGenerationRequest(
              requestId: const GenerationRequestId('req-post-cancel'),
              model: handle,
              messages: const [
                InferenceMessage(role: InferenceRole.user, content: 'Retry')
              ],
              traceContext: const InferenceTraceContext(
                traceId: RuntimeTraceId('trace-retry'),
                sessionId: 'sess-cancel',
                agentId: 'actor',
                logicalModelId: 'aura.actor.primary',
              ),
            ),
          );
          expect(res.content, isNotEmpty);
        }
      });
    });

    group('Multiple handles support -', () {
      test('Loads multiple handles and manages separate residency', () async {
        if (!profile.supportsMultipleHandles) return;

        await runtime.initialize(
          const RuntimeInitializationRequest(
              instanceId: RuntimeInstanceId('sess-multi')),
        );

        final handleEval = await runtime.loadModel(
          ModelLoadRequest(
            requestId: const ModelLoadRequestId('load-eval'),
            artifact: const ResolvedModelArtifact(
              modelVariantId: 'variant-eval',
              sha256: 'abc',
              format: 'gguf',
              quantization: 'Q4_K_M',
              architecture: 'llama',
              compatibility: ModelRuntimeCompatibility(compatible: true),
            ),
            logicalModelId: 'aura.evaluator.primary',
            roles: const {ModelRole.evaluator},
          ),
        );

        final handleActor = await runtime.loadModel(
          ModelLoadRequest(
            requestId: const ModelLoadRequestId('load-actor'),
            artifact: const ResolvedModelArtifact(
              modelVariantId: 'variant-actor',
              sha256: 'def',
              format: 'gguf',
              quantization: 'Q4_K_M',
              architecture: 'llama',
              compatibility: ModelRuntimeCompatibility(compatible: true),
            ),
            logicalModelId: 'aura.actor.primary',
            roles: const {ModelRole.actor},
          ),
        );

        expect(handleEval.id, isNot(equals(handleActor.id)));

        // Unload one, other remains valid
        await runtime.unloadModel(handleEval);

        final genReq = TextGenerationRequest(
          requestId: const GenerationRequestId('gen-actor-still-valid'),
          model: handleActor,
          messages: const [
            InferenceMessage(role: InferenceRole.user, content: 'Still here')
          ],
          traceContext: const InferenceTraceContext(
            traceId: RuntimeTraceId('trace-multi'),
            sessionId: 'sess-multi',
            agentId: 'actor',
            logicalModelId: 'aura.actor.primary',
          ),
        );

        final res = await runtime.generateText(genReq);
        expect(res.content, isNotEmpty);
      });
    });

    group('Event ordering -', () {
      test('Emits events in valid sequence during lifecycle', () async {
        final eventsList = <RuntimeEvent>[];
        final subscription = runtime.events.listen(eventsList.add);

        await runtime.initialize(
          const RuntimeInitializationRequest(
              instanceId: RuntimeInstanceId('sess-events')),
        );

        final handle = await runtime.loadModel(
          ModelLoadRequest(
            requestId: const ModelLoadRequestId('load-events'),
            artifact: const ResolvedModelArtifact(
              modelVariantId: 'variant-01',
              sha256: 'abc',
              format: 'gguf',
              quantization: 'Q4_K_M',
              architecture: 'llama',
              compatibility: ModelRuntimeCompatibility(compatible: true),
            ),
            logicalModelId: 'aura.evaluator.primary',
            roles: const {ModelRole.evaluator},
          ),
        );

        await runtime.generateText(
          TextGenerationRequest(
            requestId: const GenerationRequestId('gen-events'),
            model: handle,
            messages: const [
              InferenceMessage(role: InferenceRole.user, content: 'Event test')
            ],
            traceContext: const InferenceTraceContext(
              traceId: RuntimeTraceId('trace-events'),
              sessionId: 'sess-events',
              agentId: 'evaluator',
              logicalModelId: 'aura.evaluator.primary',
            ),
          ),
        );

        await runtime.unloadModel(handle);
        await runtime.dispose();
        await subscription.cancel();

        final types = eventsList.map((e) => e.runtimeType).toList();
        expect(types, contains(RuntimeStateChanged));
        expect(types, contains(RuntimeInitialized));
        expect(types, contains(ModelLoadStarted));
        expect(types, contains(ModelLoadCompleted));
        expect(types, contains(GenerationStarted));
        expect(types, contains(GenerationCompleted));
        expect(types, contains(ModelUnloadStarted));
        expect(types, contains(ModelUnloadCompleted));
        expect(types, contains(RuntimeDisposing));
        expect(types, contains(RuntimeDisposed));
      });
    });

    group('Post-dispose operations -', () {
      test(
          'Enforces RuntimeFailureCode.disposed across all operations post-dispose',
          () async {
        await runtime.initialize(
          const RuntimeInitializationRequest(
              instanceId: RuntimeInstanceId('sess-dispose')),
        );

        final handle = await runtime.loadModel(
          ModelLoadRequest(
            requestId: const ModelLoadRequestId('load-dispose'),
            artifact: const ResolvedModelArtifact(
              modelVariantId: 'variant-01',
              sha256: 'abc',
              format: 'gguf',
              quantization: 'Q4_K_M',
              architecture: 'llama',
              compatibility: ModelRuntimeCompatibility(compatible: true),
            ),
            logicalModelId: 'aura.evaluator.primary',
            roles: const {ModelRole.evaluator},
          ),
        );

        await runtime.dispose();
        expect(runtime.state, equals(RuntimeState.disposed));

        final dummyLoad = ModelLoadRequest(
          requestId: const ModelLoadRequestId('dummy-load'),
          artifact: const ResolvedModelArtifact(
            modelVariantId: 'v',
            sha256: 'a',
            format: 'gguf',
            quantization: 'q',
            architecture: 'a',
            compatibility: ModelRuntimeCompatibility(compatible: true),
          ),
          logicalModelId: 'aura.evaluator.primary',
          roles: const {ModelRole.evaluator},
        );

        final dummyGenText = TextGenerationRequest(
          requestId: const GenerationRequestId('dummy-gen'),
          model: handle,
          messages: const [
            InferenceMessage(role: InferenceRole.user, content: 'x')
          ],
          traceContext: const InferenceTraceContext(
            traceId: RuntimeTraceId('t'),
            sessionId: 's',
            agentId: 'a',
            logicalModelId: 'm',
          ),
        );

        final dummyGenStruct = StructuredGenerationRequest(
          requestId: const GenerationRequestId('dummy-struct'),
          model: handle,
          messages: const [
            InferenceMessage(role: InferenceRole.user, content: 'x')
          ],
          schema: const JsonSchemaDocument(schemaId: 's', document: {}),
          traceContext: const InferenceTraceContext(
            traceId: RuntimeTraceId('t'),
            sessionId: 's',
            agentId: 'a',
            logicalModelId: 'm',
          ),
        );

        expect(
          () => runtime.loadModel(dummyLoad),
          throwsA(
            isA<RuntimeException>().having(
              (e) => e.failure.code,
              'code',
              equals(RuntimeFailureCode.disposed),
            ),
          ),
        );

        expect(
          () => runtime.unloadModel(handle),
          throwsA(
            isA<RuntimeException>().having(
              (e) => e.failure.code,
              'code',
              equals(RuntimeFailureCode.disposed),
            ),
          ),
        );

        expect(
          () => runtime.generateText(dummyGenText),
          throwsA(
            isA<RuntimeException>().having(
              (e) => e.failure.code,
              'code',
              equals(RuntimeFailureCode.disposed),
            ),
          ),
        );

        expect(
          () => runtime.generateStructured(dummyGenStruct),
          throwsA(
            isA<RuntimeException>().having(
              (e) => e.failure.code,
              'code',
              equals(RuntimeFailureCode.disposed),
            ),
          ),
        );

        expect(
          () => runtime.cancel(const GenerationRequestId('dummy-cancel')),
          throwsA(
            isA<RuntimeException>().having(
              (e) => e.failure.code,
              'code',
              equals(RuntimeFailureCode.disposed),
            ),
          ),
        );

        expect(
          () => runtime.health(),
          throwsA(
            isA<RuntimeException>().having(
              (e) => e.failure.code,
              'code',
              equals(RuntimeFailureCode.disposed),
            ),
          ),
        );
      });
    });
  });
}
