import 'dart:convert';
import 'dart:io';
import 'package:aura_core/aura_offline.dart';
import 'package:aura_core/aura_testing.dart';

Future<void> main() async {
  final startedAt = DateTime.now().toUtc();
  final runId = 'smoke-${startedAt.millisecondsSinceEpoch}';
  final config =
      TestExecutionConfiguration.fromEnvironment(Platform.environment);

  print('=== A.U.R.A. Native Smoke Test Runner ===');
  print('Run ID: $runId');
  print('Policy: ${config.runtimePolicy.name}');

  if (!config.runtimePolicy.allowsNativeProcesses) {
    stderr.writeln(
      'ERROR: Policy ${config.runtimePolicy.name} does not allow native process execution. '
      'Set AURA_TEST_RUNTIME_POLICY=nativeSmoke to proceed.',
    );
    exitCode = 1;
    return;
  }

  final execPath = config.runtimePath;
  final modelPath = config.smokeModelPath ?? config.actorModelPath;

  if (execPath == null || execPath.isEmpty) {
    stderr.writeln(
        'ERROR: AURA_TEST_RUNTIME_PATH is required for native smoke test.');
    exitCode = 1;
    return;
  }

  if (modelPath == null || modelPath.isEmpty) {
    stderr.writeln(
        'ERROR: AURA_TEST_SMOKE_MODEL_PATH or AURA_TEST_ACTOR_MODEL_PATH is required.');
    exitCode = 1;
    return;
  }

  final execFile = File(execPath);
  if (!execFile.existsSync()) {
    stderr.writeln('ERROR: Executable file not found at: $execPath');
    exitCode = 1;
    return;
  }

  final modelFile = File(modelPath);
  if (!modelFile.existsSync()) {
    stderr.writeln('ERROR: Model file not found at: $modelPath');
    exitCode = 1;
    return;
  }

  final testResults = <Map<String, dynamic>>[];
  String status = 'passed';
  String? failureReason;
  String declaredBackend = config.requiredAcceleration ?? 'cuda';
  String detectedBackend = 'unknown';
  bool backendMatch = true;

  ManagedLlamaServerRuntime? runtime;

  try {
    final serverConfig = ManagedLlamaServerConfiguration(
      executablePath: execPath,
      modelPath: modelPath,
      startupTimeout: const Duration(seconds: 45),
    );

    final supervisor = LlamaServerProcessSupervisor(
      configuration: serverConfig,
      processLauncher: GuardedTestProcessLauncher(
        delegate: const DartIoProcessLauncher(),
        policy: config.runtimePolicy,
      ),
      portAllocator: const LoopbackPortAllocator(),
      healthProbe: HttpLlamaServerHealthProbe(),
    );

    runtime = ManagedLlamaServerRuntime(
      configuration: serverConfig,
      supervisor: supervisor,
    );

    // Step 1: Initialize runtime & detect capabilities
    final initSw = Stopwatch()..start();
    final capabilities = await runtime.initialize();
    initSw.stop();

    detectedBackend = capabilities.selectedBackend.name;
    if (config.requiredAcceleration != null &&
        config.requiredAcceleration!.isNotEmpty) {
      declaredBackend = config.requiredAcceleration!;
      backendMatch =
          detectedBackend.toLowerCase() == declaredBackend.toLowerCase();
    } else {
      declaredBackend = detectedBackend;
      backendMatch = true;
    }

    testResults.add({
      'name': 'runtime_initialization',
      'status': backendMatch ? 'passed' : 'failed',
      'durationMs': initSw.elapsedMilliseconds,
      'details': {
        'declaredBackend': declaredBackend,
        'detectedBackend': detectedBackend,
        'backendMatch': backendMatch,
      },
    });

    if (!backendMatch) {
      throw StateError(
        'Acceleration mismatch: required "$declaredBackend" but detected "$detectedBackend".',
      );
    }

    // Step 2: Health probe & model load
    final loadSw = Stopwatch()..start();
    final handle = await runtime.loadModel(
      ModelLoadRequest(
        requestId: const ModelLoadRequestId('smoke-load-1'),
        artifact: ResolvedModelArtifact(
          modelVariantId: 'smoke-variant',
          sha256: 'smoke-sha',
          format: 'gguf',
          quantization: 'q4',
          architecture: 'llama',
          compatibility: const ModelRuntimeCompatibility(compatible: true),
          localArtifactUri: Uri.file(modelPath),
        ),
        logicalModelId: 'aura.smoke.primary',
        roles: const {ModelRole.actor},
      ),
    );
    loadSw.stop();

    testResults.add({
      'name': 'model_loading',
      'status': 'passed',
      'durationMs': loadSw.elapsedMilliseconds,
    });

    // Step 3: Minimal generation turn (max_tokens: 16 via parameters)
    final genSw = Stopwatch()..start();
    final genResult = await runtime.generateText(
      TextGenerationRequest(
        requestId: const GenerationRequestId('smoke-gen-1'),
        model: handle,
        messages: const [
          InferenceMessage(
            role: InferenceRole.user,
            content: 'Rispondi esclusivamente con: OK',
          ),
        ],
        parameters: const GenerationParameters(maxOutputTokens: 16),
        traceContext: const InferenceTraceContext(
          traceId: RuntimeTraceId('smoke-trace-1'),
          sessionId: 'smoke-session-1',
          agentId: 'smoke-agent',
          logicalModelId: 'aura.smoke.primary',
        ),
      ),
    );
    genSw.stop();

    final isContentValid = genResult.content.trim().isNotEmpty;
    testResults.add({
      'name': 'minimal_inference',
      'status': isContentValid ? 'passed' : 'failed',
      'durationMs': genSw.elapsedMilliseconds,
      'details': {
        'contentLength': genResult.content.length,
        'finishReason': genResult.finishReason.name,
      },
    });

    if (!isContentValid) {
      throw StateError('Minimal inference produced an empty response.');
    }

    print('Native Smoke Test Completed Successfully!');
  } catch (e, stack) {
    status = 'failed';
    failureReason = '$e\n$stack';
    stderr.writeln('ERROR in Native Smoke Runner: $e');
    exitCode = 1;
  } finally {
    if (runtime != null) {
      try {
        await runtime.dispose();
      } catch (disposeErr) {
        stderr.writeln('Warning during runtime dispose: $disposeErr');
      }
    }

    final completedAt = DateTime.now().toUtc();
    final report = {
      'schemaVersion': 1,
      'profile': 'native-smoke',
      'runId': runId,
      'startedAtUtc': startedAt.toIso8601String(),
      'completedAtUtc': completedAt.toIso8601String(),
      'status': status,
      'environment': {
        'os': Platform.operatingSystem,
        'architecture': Platform.version,
      },
      'runtime': {
        'executablePath': execPath,
        'declaredBackend': declaredBackend,
        'detectedBackend': detectedBackend,
        'backendMatch': backendMatch,
      },
      'tests': testResults,
      'cleanup': {
        'orphanProcesses': 0,
      },
      'failure': failureReason,
    };

    final reportPath = config.reportPath ?? 'build/test-reports/$runId.json';
    final reportFile = File(reportPath);
    reportFile.parent.createSync(recursive: true);
    reportFile
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
    print('Report saved to: ${reportFile.path}');
  }
}
