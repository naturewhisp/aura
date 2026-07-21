import 'package:aura_core/aura_testing.dart';
import 'package:test/test.dart';

void main() {
  group('LlamaServerProcessSupervisor Tests', () {
    const config = ManagedLlamaServerConfiguration(
      executablePath: 'llama-server.exe',
      modelPath: 'model.gguf',
      startupTimeout: Duration(seconds: 2),
      healthPollInterval: Duration(milliseconds: 50),
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
      );

      final startFuture = supervisor.start();
      fakeProcess.completeExit(1);

      expect(startFuture, throwsA(anything));
      await Future.delayed(const Duration(milliseconds: 100));

      expect(supervisor.state, equals(LlamaServerSupervisorState.failed));
      expect(supervisor.failureCode,
          equals(ManagedLlamaServerFailureCode.processExitedEarly));
      expect(supervisor.lastExitCode, equals(1));
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
      );

      expect(supervisor.start(), throwsA(anything));
      await Future.delayed(const Duration(milliseconds: 300));

      expect(supervisor.state, equals(LlamaServerSupervisorState.failed));
      expect(supervisor.failureCode,
          equals(ManagedLlamaServerFailureCode.startupTimeout));
    });

    test('Captures bounded log tail in diagnosticMode', () async {
      final fakeProcess = FakeManagedProcess();
      final fakeLauncher = FakeProcessLauncher(process: fakeProcess);
      final supervisor = LlamaServerProcessSupervisor(
        configuration: config.copyWith(diagnosticMode: true),
        processLauncher: fakeLauncher,
        portAllocator: const FakePortAllocator(allocatedPort: 8080),
        healthProbe: FakeLlamaServerHealthProbe(isResponsive: true),
      );

      await supervisor.start();
      fakeProcess.emitStdout('llama-server initialized successfully\n');
      await Future.delayed(const Duration(milliseconds: 50));

      final diags = supervisor.getDiagnostics();
      expect(diags['logTail'], isNotNull);
      expect(
          (diags['logTail'] as List)
              .any((l) => l.toString().contains('initialized')),
          isTrue);

      await supervisor.dispose();
      expect(supervisor.state, equals(LlamaServerSupervisorState.disposed));
    });

    test('Dispose is single-flight and idempotent', () async {
      final supervisor = LlamaServerProcessSupervisor(
        configuration: config,
        processLauncher: FakeProcessLauncher(),
        portAllocator: const FakePortAllocator(allocatedPort: 8080),
        healthProbe: FakeLlamaServerHealthProbe(isResponsive: true),
      );

      await supervisor.start();
      final f1 = supervisor.dispose();
      final f2 = supervisor.dispose();

      await f1;
      await f2;

      expect(supervisor.state, equals(LlamaServerSupervisorState.disposed));
    });
  });
}
