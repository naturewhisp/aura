import 'dart:async';
import 'dart:io' as io;

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

  // ---------------------------------------------------------------------------
  // Gruppo: boot metadata e resilienza del sink di log
  // ---------------------------------------------------------------------------
  // Questi test usano `dart:io` reale perché il ramo di apertura del sink è
  // protetto da `_fileSystem is LocalFileSystem`.
  // ---------------------------------------------------------------------------
  group('Boot Metadata Header & Log Sink Resilience', () {
    late io.Directory tempDir;
    late io.File executableFile;
    late io.File modelFile;

    setUp(() async {
      tempDir =
          await io.Directory.systemTemp.createTemp('aura_supervisor_test');
      executableFile = io.File('${tempDir.path}\\llama-server.exe')
        ..writeAsBytesSync([]);
      modelFile = io.File('${tempDir.path}\\model.gguf')..writeAsBytesSync([]);
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    ManagedLlamaServerConfiguration _baseConfig({
      String? logFilePath,
      ManagedModelProvenance? provenance,
    }) =>
        ManagedLlamaServerConfiguration(
          executablePath: executableFile.path,
          modelPath: modelFile.path,
          startupTimeout: const Duration(milliseconds: 200),
          healthPollInterval: const Duration(milliseconds: 10),
          maxStartupAttempts: 1,
          logFilePath: logFilePath,
          provenance: provenance,
        );

    test(
        'Errore in createSync (directory non creabile) non impedisce l\'avvio del supervisor',
        () async {
      // Specifica un percorso non valido (file esistente usato come directory)
      // così createSync() lancerà un'eccezione reale.
      final blockedPath =
          '${modelFile.path}\\nested\\supervisor.log'; // model.gguf non è una dir

      final supervisor = LlamaServerProcessSupervisor(
        configuration: _baseConfig(logFilePath: blockedPath),
        processLauncher: FakeProcessLauncher(),
        portAllocator: const FakePortAllocator(allocatedPort: 8080),
        healthProbe:
            FakeLlamaServerHealthProbe(isResponsive: true, modelVisible: true),
      );

      // Il supervisor deve avviarsi normalmente anche senza log file.
      final port = await supervisor.start();
      expect(port, equals(8080));
      expect(supervisor.state, equals(LlamaServerSupervisorState.ready));

      await supervisor.stop();
    });

    test(
        'Boot header scritto con provenance managed contiene tutti i campi semantici',
        () async {
      final logFile = io.File('${tempDir.path}\\supervisor.log');
      const provenance = ManagedModelProvenance(
        artifactId: 'ministral-3b-q4km',
        repository: 'lmstudio-community/Ministral-3-3B-Instruct-2512-GGUF',
        revision: 'ee46f8f2abc6cf5ab2e92d22bcd61965',
        fileName: 'Ministral-3-3B-Instruct-2512-Q4_K_M.gguf',
        expectedSha256: 'aabbcc',
        integrityVerified: true,
        modelArchitecture: 'mistral3',
      );

      final supervisor = LlamaServerProcessSupervisor(
        configuration: _baseConfig(
          logFilePath: logFile.path,
          provenance: provenance,
        ),
        processLauncher: FakeProcessLauncher(),
        portAllocator: const FakePortAllocator(allocatedPort: 9090),
        healthProbe:
            FakeLlamaServerHealthProbe(isResponsive: true, modelVisible: true),
      );

      await supervisor.start();
      await supervisor.stop();

      // Attende flush asincrono del sink prima di leggere.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(logFile.existsSync(), isTrue);
      final content = logFile.readAsStringSync();

      expect(content, contains('Artifact ID: ministral-3b-q4km'));
      expect(
        content,
        contains(
          'Repository: lmstudio-community/Ministral-3-3B-Instruct-2512-GGUF',
        ),
      );
      expect(content, contains('Revision: ee46f8f2abc6cf5ab2e92d22bcd61965'));
      expect(
        content,
        contains('File Name: Ministral-3-3B-Instruct-2512-Q4_K_M.gguf'),
      );
      expect(content, contains('Model Architecture: mistral3'));
      expect(content, contains('Integrity Verified: true'));
    });

    test(
        'Boot header scritto senza provenance mostra "not available" per istanza esterna',
        () async {
      final logFile = io.File('${tempDir.path}\\supervisor_ext.log');

      final supervisor = LlamaServerProcessSupervisor(
        configuration: _baseConfig(logFilePath: logFile.path),
        processLauncher: FakeProcessLauncher(),
        portAllocator: const FakePortAllocator(allocatedPort: 7070),
        healthProbe:
            FakeLlamaServerHealthProbe(isResponsive: true, modelVisible: true),
      );

      await supervisor.start();
      await supervisor.stop();

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(logFile.existsSync(), isTrue);
      final content = logFile.readAsStringSync();
      expect(content, contains('not available'));
      expect(content, isNot(contains('Artifact ID:')));
    });
  });
}
