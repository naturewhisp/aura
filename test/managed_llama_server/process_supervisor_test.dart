import 'package:aura_core/aura_testing.dart';
import 'package:test/test.dart';

void main() {
  group('LlamaServerProcessSupervisor Tests', () {
    const config = ManagedLlamaServerConfiguration(
      executablePath: 'llama-server.exe',
      modelPath: 'model.gguf',
      startupTimeout: Duration(seconds: 2),
      healthPollInterval: Duration(milliseconds: 50),
      maxStartupAttempts: 2,
    );

    test('Nominal start transitions state to ready and records port and pid',
        () async {
      final fakeLauncher = FakeProcessLauncher();
      final supervisor = LlamaServerProcessSupervisor(
        configuration: config,
        processLauncher: fakeLauncher,
        portAllocator: const FakePortAllocator(allocatedPort: 8080),
        healthProbe:
            FakeLlamaServerHealthProbe(isResponsive: true, modelVisible: true),
        fileSystem: const FakeFileSystem(
          existingFiles: {'llama-server.exe', 'model.gguf'},
        ),
      );

      expect(supervisor.state, equals(LlamaServerSupervisorState.idle));

      final port = await supervisor.start();

      expect(port, equals(8080));
      expect(supervisor.state, equals(LlamaServerSupervisorState.ready));
      expect(supervisor.pid, equals(4242));
      expect(supervisor.allocatedPort, equals(8080));

      await supervisor.stop();
      expect(supervisor.state, equals(LlamaServerSupervisorState.stopped));
    });

    test('Process exit early transitions state to failed', () async {
      final fakeProcess = FakeManagedProcess();
      final fakeLauncher = FakeProcessLauncher(process: fakeProcess);
      final supervisor = LlamaServerProcessSupervisor(
        configuration: config,
        processLauncher: fakeLauncher,
        portAllocator: const FakePortAllocator(allocatedPort: 8080),
        healthProbe: FakeLlamaServerHealthProbe(isResponsive: false),
        fileSystem: const FakeFileSystem(
          existingFiles: {'llama-server.exe', 'model.gguf'},
        ),
      );

      final startFuture = supervisor.start();
      fakeProcess.completeExit(1);

      expect(startFuture, throwsA(isA<ManagedLlamaServerException>()));
      await Future.delayed(const Duration(milliseconds: 100));

      expect(supervisor.state, equals(LlamaServerSupervisorState.failed));
      expect(supervisor.failureCode,
          equals(ManagedLlamaServerFailureCode.processExitedEarly));
      expect(supervisor.lastExitCode, equals(1));
    });

    test('Unexpected process exit after ready transitions state to failed',
        () async {
      final fakeProcess = FakeManagedProcess();
      final fakeLauncher = FakeProcessLauncher(process: fakeProcess);
      final supervisor = LlamaServerProcessSupervisor(
        configuration: config,
        processLauncher: fakeLauncher,
        portAllocator: const FakePortAllocator(allocatedPort: 8080),
        healthProbe:
            FakeLlamaServerHealthProbe(isResponsive: true, modelVisible: true),
        fileSystem: const FakeFileSystem(
          existingFiles: {'llama-server.exe', 'model.gguf'},
        ),
      );

      await supervisor.start();
      expect(supervisor.state, equals(LlamaServerSupervisorState.ready));

      fakeProcess.completeExit(5);
      await Future.delayed(const Duration(milliseconds: 100));

      expect(supervisor.state, equals(LlamaServerSupervisorState.failed));
      expect(supervisor.failureCode,
          equals(ManagedLlamaServerFailureCode.processExitedEarly));
      expect(supervisor.lastExitCode, equals(5));
    });

    test('Startup timeout when health probe never becomes responsive',
        () async {
      final fakeProcess = FakeManagedProcess();
      final fakeLauncher = FakeProcessLauncher(process: fakeProcess);
      final supervisor = LlamaServerProcessSupervisor(
        configuration:
            config.copyWith(startupTimeout: const Duration(milliseconds: 200)),
        processLauncher: fakeLauncher,
        portAllocator: const FakePortAllocator(allocatedPort: 8080),
        healthProbe: FakeLlamaServerHealthProbe(isResponsive: false),
        fileSystem: const FakeFileSystem(
          existingFiles: {'llama-server.exe', 'model.gguf'},
        ),
      );

      expect(supervisor.start(), throwsA(isA<ManagedLlamaServerException>()));
      await Future.delayed(const Duration(milliseconds: 300));

      expect(supervisor.state, equals(LlamaServerSupervisorState.failed));
      expect(supervisor.failureCode,
          equals(ManagedLlamaServerFailureCode.startupTimeout));
    });

    test('Startup retry loop executes multiple attempts and then fails',
        () async {
      final fakeLauncher = FakeProcessLauncher();
      final healthProbe = FakeLlamaServerHealthProbe(isResponsive: false);
      final supervisor = LlamaServerProcessSupervisor(
        configuration: config.copyWith(
          startupTimeout: const Duration(milliseconds: 100),
          maxStartupAttempts: 3,
        ),
        processLauncher: fakeLauncher,
        portAllocator: const FakePortAllocator(allocatedPort: 8080),
        healthProbe: healthProbe,
        fileSystem: const FakeFileSystem(
          existingFiles: {'llama-server.exe', 'model.gguf'},
        ),
      );

      expect(
        supervisor.start(),
        throwsA(isA<ManagedLlamaServerException>().having(
          (e) => e.code,
          'code',
          equals(ManagedLlamaServerFailureCode.startupTimeout),
        )),
      );

      await Future.delayed(const Duration(milliseconds: 500));
      expect(supervisor.state, equals(LlamaServerSupervisorState.failed));
    });

    test(
        'Captures bounded log tail in diagnosticMode and sanitizes ANSI escape codes',
        () async {
      final fakeProcess = FakeManagedProcess();
      final fakeLauncher = FakeProcessLauncher(process: fakeProcess);
      final supervisor = LlamaServerProcessSupervisor(
        configuration: config.copyWith(diagnosticMode: true),
        processLauncher: fakeLauncher,
        portAllocator: const FakePortAllocator(allocatedPort: 8080),
        healthProbe: FakeLlamaServerHealthProbe(isResponsive: true),
        fileSystem: const FakeFileSystem(
          existingFiles: {'llama-server.exe', 'model.gguf'},
        ),
      );

      await supervisor.start();
      fakeProcess
          .emitStdout('\x1B[1mllama-server\x1B[0m initialized successfully\n');
      fakeProcess.emitStdout('${"A" * 600}\n'); // over max line length
      await Future.delayed(const Duration(milliseconds: 50));

      final diags = supervisor.getDiagnostics();
      expect(diags['logTail'], isNotNull);
      final logLines = diags['logTail'] as List<String>;
      expect(
          logLines
              .any((l) => l.contains('llama-server initialized successfully')),
          isTrue);
      expect(logLines.any((l) => l.contains('\x1B[')), isFalse); // Sanitized
      expect(logLines.any((l) => l.contains('TRUNCATED')),
          isTrue); // Bounded length

      await supervisor.dispose();
      expect(supervisor.state, equals(LlamaServerSupervisorState.disposed));
    });

    test('Forced termination failure transitions to failed state', () async {
      final fakeProcess = FakeManagedProcess()..killResult = false;
      final fakeLauncher = FakeProcessLauncher(process: fakeProcess);
      final supervisor = LlamaServerProcessSupervisor(
        configuration: config,
        processLauncher: fakeLauncher,
        portAllocator: const FakePortAllocator(allocatedPort: 8080),
        healthProbe:
            FakeLlamaServerHealthProbe(isResponsive: true, modelVisible: true),
        fileSystem: const FakeFileSystem(
          existingFiles: {'llama-server.exe', 'model.gguf'},
        ),
      );

      await supervisor.start();
      expect(supervisor.state, equals(LlamaServerSupervisorState.ready));

      // Attempt to stop, which should trigger sigkill and fail
      expect(supervisor.stop(), throwsA(isA<ManagedLlamaServerException>()));
      await Future.delayed(const Duration(milliseconds: 100));

      expect(supervisor.state, equals(LlamaServerSupervisorState.failed));
      expect(supervisor.failureCode,
          equals(ManagedLlamaServerFailureCode.forcedTerminationFailed));
    });

    test(
        'Dispose is single-flight, idempotent, and disposes health probe client',
        () async {
      final healthProbe = FakeLlamaServerHealthProbe(isResponsive: true);
      final supervisor = LlamaServerProcessSupervisor(
        configuration: config,
        processLauncher: FakeProcessLauncher(),
        portAllocator: const FakePortAllocator(allocatedPort: 8080),
        healthProbe: healthProbe,
        fileSystem: const FakeFileSystem(
          existingFiles: {'llama-server.exe', 'model.gguf'},
        ),
      );

      await supervisor.start();
      expect(healthProbe.isDisposed, isFalse);

      final f1 = supervisor.dispose();
      final f2 = supervisor.dispose();

      await f1;
      await f2;

      expect(supervisor.state, equals(LlamaServerSupervisorState.disposed));
      expect(healthProbe.isDisposed, isTrue);
    });
  });
}
