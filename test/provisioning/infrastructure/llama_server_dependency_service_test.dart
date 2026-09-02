import 'dart:async';
import 'dart:convert';
import 'package:aura_core/aura_offline.dart';
import 'package:crypto/crypto.dart';
import '../../provisioning/provisioning_test_helpers.dart';
import 'package:test/test.dart';

final class TestManagedProcess implements ManagedProcess {
  @override
  final int pid;
  final int exitCodeValue;
  final String stdoutText;
  final String stderrText;

  TestManagedProcess({
    this.pid = 1234,
    this.exitCodeValue = 0,
    this.stdoutText = '',
    this.stderrText = '',
  });

  @override
  Stream<List<int>> get stdoutBytes => Stream.multi((controller) {
        controller.add(utf8.encode(stdoutText));
        controller.close();
      });

  @override
  Stream<List<int>> get stderrBytes => Stream.multi((controller) {
        controller.add(utf8.encode(stderrText));
        controller.close();
      });

  @override
  Future<int> get exitCode async => exitCodeValue;

  @override
  bool kill([Object? signal]) => true;
}

final class TestProcessLauncher implements ProcessLauncher {
  final Future<ManagedProcess> Function(ProcessLaunchRequest request) handler;

  TestProcessLauncher(this.handler);

  @override
  Future<ManagedProcess> start(ProcessLaunchRequest request) {
    return handler(request);
  }
}

void main() {
  late MemoryProvisioningFileSystem fileSystem;
  late ProvisioningPathResolver pathResolver;
  late JsonModelConfigurationRepository repo;
  const storePath = r'C:\Users\Test\AppData\Local\AURA\store';

  setUp(() {
    fileSystem = MemoryProvisioningFileSystem();
    pathResolver = ProvisioningPathResolver(
      appManagedRoot: r'C:\Users\Test\AppData\Local\AURA',
      bundledRoot: r'C:\Program Files\AURA',
    );
    repo = JsonModelConfigurationRepository(
      storeDirectoryPath: storePath,
      fileSystem: fileSystem,
      lock: InMemoryProvisioningLock(),
    );
  });

  group('Tranche 6.4f.2 — DefaultLlamaServerDependencyService Tests', () {
    test(
        'validateExecutable valida con successo eseguibile e ricava versione da --version',
        () async {
      const exePath = r'C:\Tools\llama-server.exe';
      await fileSystem.writeBytes(exePath, [1, 2, 3]);

      final launcher = TestProcessLauncher((req) async {
        if (req.executable == exePath && req.arguments.contains('--version')) {
          return TestManagedProcess(
            stdoutText: 'version: 3450 (b3450)\nbuild: 3450',
          );
        }
        return TestManagedProcess(exitCodeValue: 1);
      });

      final service = DefaultLlamaServerDependencyService(
        configurationRepository: repo,
        fileSystem: fileSystem,
        pathResolver: pathResolver,
        processLauncher: launcher,
        probeTimeout: const Duration(milliseconds: 100),
      );

      final result = await service.validateExecutable(executablePath: exePath);
      expect(result.isValid, isTrue);
      expect(result.status, equals(LlamaServerValidationStatus.valid));
      expect(result.detectedVersion, equals('b3450'));
    });

    test(
        'validateExecutable effettua il fallback a --help se --version fallisce',
        () async {
      const exePath = r'C:\Tools\llama-server.exe';
      await fileSystem.writeBytes(exePath, [1, 2, 3]);

      final launcher = TestProcessLauncher((req) async {
        if (req.arguments.contains('--version')) {
          return TestManagedProcess(
              exitCodeValue: 1, stderrText: 'unknown option');
        }
        if (req.arguments.contains('--help')) {
          return TestManagedProcess(
            exitCodeValue: 0,
            stdoutText: 'usage: llama-server [options]\n  --model PATH',
          );
        }
        return TestManagedProcess(exitCodeValue: 1);
      });

      final service = DefaultLlamaServerDependencyService(
        configurationRepository: repo,
        fileSystem: fileSystem,
        pathResolver: pathResolver,
        processLauncher: launcher,
        probeTimeout: const Duration(milliseconds: 100),
      );

      final result = await service.validateExecutable(executablePath: exePath);
      expect(result.isValid, isTrue);
      expect(result.status, equals(LlamaServerValidationStatus.valid));
      expect(result.detectedVersion, equals('detected'));
    });

    test('validateExecutable rifiuta file inesistente o vuoto', () async {
      final launcher = TestProcessLauncher((req) async => TestManagedProcess());
      final service = DefaultLlamaServerDependencyService(
        configurationRepository: repo,
        fileSystem: fileSystem,
        pathResolver: pathResolver,
        processLauncher: launcher,
        probeTimeout: const Duration(milliseconds: 100),
      );

      final resultMissing = await service.validateExecutable(
        executablePath: r'C:\Missing\llama-server.exe',
      );
      expect(resultMissing.status, equals(LlamaServerValidationStatus.missing));

      const emptyPath = r'C:\Empty\llama-server.exe';
      await fileSystem.writeBytes(emptyPath, []);

      final resultEmpty =
          await service.validateExecutable(executablePath: emptyPath);
      expect(resultEmpty.status,
          equals(LlamaServerValidationStatus.notExecutable));
    });

    test('detect rispetta l\'ordine di precedenza deterministico', () async {
      const userExe = r'C:\UserConfigured\llama-server.exe';
      await fileSystem.writeBytes(userExe, [1, 2, 3]);

      final launcher = TestProcessLauncher((req) async {
        return TestManagedProcess(stdoutText: 'version: b3400');
      });

      final service = DefaultLlamaServerDependencyService(
        configurationRepository: repo,
        fileSystem: fileSystem,
        pathResolver: pathResolver,
        processLauncher: launcher,
        probeTimeout: const Duration(milliseconds: 100),
      );

      await service.configureExecutable(executablePath: userExe);

      final detection = await service.detect();
      expect(detection.configuredCandidate, equals(userExe));
      expect(detection.isConfiguredValid, isTrue);
      expect(detection.effectiveCandidate, equals(userExe));
    });

    test(
        'detect continua la discovery con fallback se il percorso configurato è invalido',
        () async {
      const invalidUserExe = r'C:\BrokenPath\llama-server.exe';
      const portableExe =
          r'C:\Users\Test\AppData\Local\AURA\runtime\llama-server.exe';

      await fileSystem.writeBytes(portableExe, [1, 2, 3]);

      final launcher = TestProcessLauncher((req) async {
        if (req.executable == portableExe) {
          return TestManagedProcess(stdoutText: 'version: b3400');
        }
        return TestManagedProcess(exitCodeValue: 1, stderrText: 'error');
      });

      final service = DefaultLlamaServerDependencyService(
        configurationRepository: repo,
        fileSystem: fileSystem,
        pathResolver: pathResolver,
        processLauncher: launcher,
        probeTimeout: const Duration(milliseconds: 100),
      );

      // Persistiamo un percorso non esistente
      await repo.replaceRecord(ModelConfigurationRecord(
        schemaVersion: 1,
        runtime: const LlamaServerConfiguration(
          executablePath: invalidUserExe,
          validationStatus: LlamaServerValidationStatus.missing,
        ),
      ));

      final detection = await service.detect();
      expect(detection.configuredCandidate, equals(invalidUserExe));
      expect(detection.isConfiguredValid, isFalse);
      expect(detection.detectedFallback, equals(portableExe));
      expect(detection.effectiveCandidate, equals(portableExe));
      expect(detection.warnings, isNotEmpty);
    });

    test(
        'validateExecutable rileva accelerazione CUDA e gpuDeviceName da --list-devices',
        () async {
      const exePath = r'C:\Tools\llama-server.exe';
      await fileSystem.writeBytes(exePath, [1, 2, 3]);

      final launcher = TestProcessLauncher((req) async {
        if (req.executable == exePath && req.arguments.contains('--version')) {
          return TestManagedProcess(
            stdoutText:
                'version: 10256 (6c8dcaa7a)\nbuilt with Clang 20.1.8 for Windows x86_64',
          );
        }
        if (req.executable == exePath &&
            req.arguments.contains('--list-devices')) {
          return TestManagedProcess(
            stdoutText:
                'Available devices:\n  CUDA0: NVIDIA GeForce RTX 3060 (12287 MiB, 11253 MiB free)\n',
          );
        }
        return TestManagedProcess(exitCodeValue: 1);
      });

      final service = DefaultLlamaServerDependencyService(
        configurationRepository: repo,
        fileSystem: fileSystem,
        pathResolver: pathResolver,
        processLauncher: launcher,
        probeTimeout: const Duration(milliseconds: 100),
      );

      final result = await service.validateExecutable(
        executablePath: exePath,
        variantId: 'win-x64-cuda',
      );
      expect(result.isValid, isTrue);
      expect(result.acceleration, equals(RuntimeAcceleration.cuda));
      expect(result.gpuDeviceName, equals('NVIDIA GeForce RTX 3060'));
    });

    test(
        'validateExecutable restituisce CPU quando --list-devices non rileva device GPU anche se variantId è win-x64-cuda',
        () async {
      const exePath = r'C:\Tools\llama-server.exe';
      await fileSystem.writeBytes(exePath, [1, 2, 3]);

      final launcher = TestProcessLauncher((req) async {
        if (req.executable == exePath && req.arguments.contains('--version')) {
          return TestManagedProcess(
            stdoutText:
                'version: 10256 (6c8dcaa7a)\nbuilt with Clang for Windows x86_64 with CUDA',
          );
        }
        if (req.executable == exePath &&
            req.arguments.contains('--list-devices')) {
          return TestManagedProcess(
            stdoutText: 'Available devices:\n  (none)\n',
          );
        }
        return TestManagedProcess(exitCodeValue: 1);
      });

      final service = DefaultLlamaServerDependencyService(
        configurationRepository: repo,
        fileSystem: fileSystem,
        pathResolver: pathResolver,
        processLauncher: launcher,
        probeTimeout: const Duration(milliseconds: 100),
      );

      final result = await service.validateExecutable(
        executablePath: exePath,
        variantId: 'win-x64-cuda',
      );
      expect(result.isValid, isTrue);
      expect(result.acceleration, equals(RuntimeAcceleration.cpu));
      expect(result.gpuDeviceName, isNull);
    });

    test(
        'validateExecutable tratta --list-devices fallito o vuoto come non-GPU (CPU) per runtime bundled invece di ripiegare su --version',
        () async {
      const exePath = r'C:\Tools\llama-server.exe';
      await fileSystem.writeBytes(exePath, [1, 2, 3]);

      final launcher = TestProcessLauncher((req) async {
        if (req.executable == exePath && req.arguments.contains('--version')) {
          return TestManagedProcess(
            stdoutText:
                'version: 10256 (6c8dcaa7a)\nbuilt with Clang for Windows x86_64 with CUDA',
          );
        }
        if (req.executable == exePath &&
            req.arguments.contains('--list-devices')) {
          // Simula fallimento di --list-devices (es. crash driver, assenza DLL CUDA o uscita anomala)
          return TestManagedProcess(exitCodeValue: 1, stdoutText: '');
        }
        return TestManagedProcess(exitCodeValue: 1);
      });

      final service = DefaultLlamaServerDependencyService(
        configurationRepository: repo,
        fileSystem: fileSystem,
        pathResolver: pathResolver,
        processLauncher: launcher,
        probeTimeout: const Duration(milliseconds: 100),
      );

      final result = await service.validateExecutable(
        executablePath: exePath,
        variantId: 'win-x64-cuda',
      );
      expect(result.isValid, isTrue);
      expect(result.acceleration, equals(RuntimeAcceleration.cpu));
      expect(result.gpuDeviceName, isNull);
    });

    test(
        'detect scarta variante win-x64-cuda se priva di GPU CUDA e adotta win-x64-vulkan con GPU reale',
        () async {
      final manifestDir = r'C:\Users\Test\AppData\Local\AURA\runtime';
      final cudaExe = '$manifestDir\\bin\\win-x64-cuda\\llama-server.exe';
      final vulkanExe = '$manifestDir\\bin\\win-x64-vulkan\\llama-server.exe';

      await fileSystem.writeBytes(cudaExe, [1, 2, 3]);
      await fileSystem.writeBytes(vulkanExe, [1, 2, 3]);
      final hash = sha256.convert([1, 2, 3]).toString().toLowerCase();

      final manifestJson = '''
{
  "schemaVersion": 1,
  "runtimeSetId": "aura-runtime-v1",
  "variants": [
    {
      "id": "win-x64-cuda",
      "acceleration": "cuda",
      "targetArch": "x64",
      "requiredCpuFeatures": [],
      "backendCapabilities": ["cuda12"],
      "executable": "bin/win-x64-cuda/llama-server.exe",
      "workingDirectory": "bin/win-x64-cuda",
      "vendorDirectories": [],
      "files": [
        {"path": "bin/win-x64-cuda/llama-server.exe", "sizeBytes": 3, "sha256": "$hash"}
      ]
    },
    {
      "id": "win-x64-vulkan",
      "acceleration": "vulkan",
      "targetArch": "x64",
      "requiredCpuFeatures": [],
      "backendCapabilities": ["vulkan"],
      "executable": "bin/win-x64-vulkan/llama-server.exe",
      "workingDirectory": "bin/win-x64-vulkan",
      "vendorDirectories": [],
      "files": [
        {"path": "bin/win-x64-vulkan/llama-server.exe", "sizeBytes": 3, "sha256": "$hash"}
      ]
    }
  ]
}
''';
      await fileSystem.writeAsString(
          '$manifestDir\\runtime-manifest.json', manifestJson);

      final launcher = TestProcessLauncher((req) async {
        if (req.executable == cudaExe &&
            req.arguments.contains('--list-devices')) {
          return TestManagedProcess(
            stdoutText: 'Available devices:\n  (none)\n',
          );
        }
        if (req.executable == vulkanExe &&
            req.arguments.contains('--list-devices')) {
          return TestManagedProcess(
            stdoutText:
                'Available devices:\n  Vulkan0: AMD Radeon RX 6700 XT (12272 MiB)\n',
          );
        }
        return TestManagedProcess(stdoutText: 'version: b10256');
      });

      final service = DefaultLlamaServerDependencyService(
        configurationRepository: repo,
        fileSystem: fileSystem,
        pathResolver: pathResolver,
        processLauncher: launcher,
        probeTimeout: const Duration(milliseconds: 100),
      );

      final detection = await service.detect();
      expect(detection.effectiveCandidate, equals(vulkanExe));
      expect(detection.variantId, equals('win-x64-vulkan'));
      expect(detection.acceleration, equals(RuntimeAcceleration.vulkan));
      expect(detection.gpuDeviceName, equals('AMD Radeon RX 6700 XT'));
    });
  });
}
