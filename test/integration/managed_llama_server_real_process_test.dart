@Tags(['network', 'real-model'])
import 'dart:io';
import 'package:aura_core/aura_offline.dart';
import 'package:test/test.dart';

void main() {
  final execPath = Platform.environment['AURA_TEST_LLAMA_EXECUTABLE'];
  final modelPath = Platform.environment['AURA_TEST_LLAMA_MODEL'];

  final shouldSkip = execPath == null ||
      execPath.isEmpty ||
      modelPath == null ||
      modelPath.isEmpty;

  group('Integration Test - Real Managed Llama Server Process', () {
    test(
      'Launches real llama-server process and executes single inference turn',
      () async {
        final config = ManagedLlamaServerConfiguration(
          executablePath: execPath!,
          modelPath: modelPath!,
          startupTimeout: const Duration(seconds: 45),
        );

        final supervisor = LlamaServerProcessSupervisor(
          configuration: config,
          processLauncher: const DartIoProcessLauncher(),
          portAllocator: const LoopbackPortAllocator(),
          healthProbe: HttpLlamaServerHealthProbe(),
        );

        final runtime = ManagedLlamaServerRuntime(
          configuration: config,
          supervisor: supervisor,
        );

        try {
          final capabilities = await runtime.initialize();
          expect(capabilities.runtimeName, equals('llama-server'));

          final handle = await runtime.loadModel(
            ModelLoadRequest(
              requestId: const ModelLoadRequestId('real-load-1'),
              artifact: ResolvedModelArtifact(
                modelVariantId: 'real-model',
                sha256: 'sha',
                format: 'gguf',
                quantization: 'q4',
                architecture: 'llama',
                compatibility:
                    const ModelRuntimeCompatibility(compatible: true),
                localArtifactUri: Uri.file(modelPath),
              ),
              logicalModelId: 'aura.actor.primary',
              roles: const {ModelRole.actor, ModelRole.evaluator},
            ),
          );

          final result = await runtime.generateText(
            TextGenerationRequest(
              requestId: const GenerationRequestId('real-gen-1'),
              model: handle,
              messages: const [
                InferenceMessage(
                    role: InferenceRole.user, content: 'Respond OK')
              ],
              traceContext: const InferenceTraceContext(
                traceId: RuntimeTraceId('real-trace-1'),
                sessionId: 'real-session-1',
                agentId: 'actor-1',
                logicalModelId: 'aura.actor.primary',
              ),
            ),
          );

          expect(result.content, isNotEmpty);
        } finally {
          await runtime.dispose();
        }
      },
      skip: shouldSkip
          ? 'Saltato: impostare AURA_TEST_LLAMA_EXECUTABLE e AURA_TEST_LLAMA_MODEL per eseguire il test reale.'
          : false,
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });
}
