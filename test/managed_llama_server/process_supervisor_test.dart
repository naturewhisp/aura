import 'package:aura_core/aura_testing.dart';
import 'package:test/test.dart';

void main() {
  group('LlamaServerProcessSupervisor Tests', () {
    const config = ManagedLlamaServerConfiguration(
      executablePath: 'llama-server.exe',
      modelPath: 'model.gguf',
      startupTimeout: Duration(milliseconds: 200),
      healthPollInterval: Duration(milliseconds: 10),
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

    test('Executes two full start/stop cycles stopping process on both cycles',
        () async {
      int launchCount = 0;
      final fakeLauncher = FakeProcessLauncher(
        processFactory: () {
          launchCount++;
          return FakeManagedProcess(pid: 4000 + launchCount);
        },
      );
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

      // Cycle 1
      await supervisor.start();
      expect(supervisor.state, equals(LlamaServerSupervisorState.ready));
      expect(supervisor.pid, equals(4001));

      await supervisor.stop();
      expect(supervisor.state, equals(LlamaServerSupervisorState.stopped));
      expect(supervisor.pid, isNull);

      // Cycle 2
      await supervisor.start();
      expect(supervisor.state, equals(LlamaServerSupervisorState.ready));
      expect(supervisor.pid, equals(4002));

      await supervisor.stop();
      expect(supervisor.state, equals(LlamaServerSupervisorState.stopped));
      expect(supervisor.pid, isNull);
    });

    test('Process exit early transitions state to failed', () async {
      final fakeProcess = FakeManagedProcess();
      final fakeLauncher = FakeProcessLauncher(process: fakeProcess);
      final supervisor = LlamaServerProcessSupervisor(
        configuration: config.copyWith(maxStartupAttempts: 1),
        processLauncher: fakeLauncher,
        portAllocator: const FakePortAllocator(allocatedPort: 8080),
        healthProbe: FakeLlamaServerHealthProbe(isResponsive: false),
        fileSystem: const FakeFileSystem(
          existingFiles: {'llama-server.exe', 'model.gguf'},
        ),
      );

      final startFuture = supervisor.start();
      await pumpEventQueue();
      fakeProcess.completeExit(1);

      await expectLater(
          startFuture, throwsA(isA<ManagedLlamaServerException>()));

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
      await pumpEventQueue();

      expect(supervisor.state, equals(LlamaServerSupervisorState.failed));
      expect(supervisor.failureCode,
          equals(ManagedLlamaServerFailureCode.processExitedEarly));
      expect(supervisor.lastExitCode, equals(5));
    });

    test(
        'Already exited process is cleaned up as success during stop without kill failure',
        () async {
      final fakeProcess = FakeManagedProcess();
      final supervisor = LlamaServerProcessSupervisor(
        configuration: config,
        processLauncher: FakeProcessLauncher(process: fakeProcess),
        portAllocator: const FakePortAllocator(allocatedPort: 8080),
        healthProbe:
            FakeLlamaServerHealthProbe(isResponsive: true, modelVisible: true),
        fileSystem: const FakeFileSystem(
          existingFiles: {'llama-server.exe', 'model.gguf'},
        ),
      );

      await supervisor.start();
      expect(supervisor.state, equals(LlamaServerSupervisorState.ready));

      // Process exits spontaneously
      fakeProcess.completeExit(0);
      await pumpEventQueue();

      expect(supervisor.state, equals(LlamaServerSupervisorState.failed));
      expect(supervisor.lastExitCode, equals(0));

      // stop() should succeed without throwing forcedTerminationFailed or attempting kill
      await supervisor.stop();

      expect(supervisor.state, equals(LlamaServerSupervisorState.stopped));
      expect(supervisor.pid, isNull);
    });

    test('Startup timeout when health probe never becomes responsive',
        () async {
      final fakeProcess = FakeManagedProcess();
      final fakeLauncher = FakeProcessLauncher(process: fakeProcess);
      final supervisor = LlamaServerProcessSupervisor(
        configuration:
            config.copyWith(startupTimeout: const Duration(milliseconds: 50)),
        processLauncher: fakeLauncher,
        portAllocator: const FakePortAllocator(allocatedPort: 8080),
        healthProbe: FakeLlamaServerHealthProbe(isResponsive: false),
        fileSystem: const FakeFileSystem(
          existingFiles: {'llama-server.exe', 'model.gguf'},
        ),
      );

      await expectLater(
          supervisor.start(), throwsA(isA<ManagedLlamaServerException>()));

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
          startupTimeout: const Duration(milliseconds: 50),
          maxStartupAttempts: 2,
        ),
        processLauncher: fakeLauncher,
        portAllocator: const FakePortAllocator(allocatedPort: 8080),
        healthProbe: healthProbe,
        fileSystem: const FakeFileSystem(
          existingFiles: {'llama-server.exe', 'model.gguf'},
        ),
      );

      await expectLater(
        supervisor.start(),
        throwsA(isA<ManagedLlamaServerException>().having(
          (e) => e.code,
          'code',
          equals(ManagedLlamaServerFailureCode.startupTimeout),
        )),
      );

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
      await pumpEventQueue();

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

    test(
        'Forced termination failure transitions to failed state and retains process handle',
        () async {
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
      await expectLater(
          supervisor.stop(), throwsA(isA<ManagedLlamaServerException>()));

      expect(supervisor.state, equals(LlamaServerSupervisorState.failed));
      expect(supervisor.failureCode,
          equals(ManagedLlamaServerFailureCode.forcedTerminationFailed));
      expect(supervisor.pid, equals(4242)); // Handle retained!
    });

    test('Retains failed state and throws when dispose cleanup fails',
        () async {
      final fakeProcess = FakeManagedProcess()..killResult = false;
      final supervisor = LlamaServerProcessSupervisor(
        configuration: config,
        processLauncher: FakeProcessLauncher(process: fakeProcess),
        portAllocator: const FakePortAllocator(allocatedPort: 8080),
        healthProbe: FakeLlamaServerHealthProbe(isResponsive: true),
        fileSystem: const FakeFileSystem(
          existingFiles: {'llama-server.exe', 'model.gguf'},
        ),
      );

      await supervisor.start();
      await expectLater(
          supervisor.dispose(), throwsA(isA<ManagedLlamaServerException>()));

      expect(supervisor.state,
          equals(LlamaServerSupervisorState.failed)); // Not disposed!
    });

    test('start() throws ManagedLlamaServerException when in invalid state',
        () async {
      final supervisor = LlamaServerProcessSupervisor(
        configuration: config,
        processLauncher: FakeProcessLauncher(),
        portAllocator: const FakePortAllocator(allocatedPort: 8080),
        healthProbe: FakeLlamaServerHealthProbe(isResponsive: true),
        fileSystem: const FakeFileSystem(
          existingFiles: {'llama-server.exe', 'model.gguf'},
        ),
      );

      await supervisor.start();
      expect(
        supervisor.start(),
        throwsA(isA<ManagedLlamaServerException>().having(
          (e) => e.code,
          'code',
          equals(ManagedLlamaServerFailureCode.unexpectedProcessState),
        )),
      );
    });

    test('getDiagnostics omits pid and allocatedPort', () async {
      final supervisor = LlamaServerProcessSupervisor(
        configuration: config,
        processLauncher: FakeProcessLauncher(),
        portAllocator: const FakePortAllocator(allocatedPort: 8080),
        healthProbe: FakeLlamaServerHealthProbe(isResponsive: true),
        fileSystem: const FakeFileSystem(
          existingFiles: {'llama-server.exe', 'model.gguf'},
        ),
      );

      await supervisor.start();
      final diags = supervisor.getDiagnostics();
      expect(diags.containsKey('pid'), isFalse);
      expect(diags.containsKey('allocatedPort'), isFalse);
    });

    test(
        'Dispose is single-flight, returns identical Future for concurrent calls, and disposes health probe client',
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

      expect(identical(f1, f2), isTrue);

      await f1;
      await f2;

      expect(supervisor.state, equals(LlamaServerSupervisorState.disposed));
      expect(healthProbe.isDisposed, isTrue);
    });
  });
}
