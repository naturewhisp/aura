import 'dart:async';
import 'dart:convert';
import 'dart:io' as io show Directory, File, Platform;

import '../../agent_runtime/runtime/adapters/managed_llama_server/dart_io_process_launcher.dart';
import '../../agent_runtime/runtime/adapters/managed_llama_server/process_launcher.dart';
import '../domain/runtime_dependency_models.dart';
import 'json_model_configuration_repository.dart';
import 'provisioning_file_system.dart';
import 'provisioning_path_resolver.dart';

/// Contratto astratto per la gestione della dipendenza esterna `llama-server`.
abstract interface class LlamaServerDependencyService {
  /// Esegue la discovery deterministica dell'eseguibile `llama-server`.
  Future<LlamaServerDetectionResult> detect();

  /// Valida operativamente un candidato eseguibile tramite probe processuale sicuro.
  Future<LlamaServerValidationResult> validateExecutable({
    required String executablePath,
  });

  /// Configura e persiste il percorso dell'eseguibile `llama-server`.
  Future<LlamaServerConfiguration> configureExecutable({
    required String executablePath,
  });

  /// Azzera la configurazione persistita dell'eseguibile.
  Future<void> clearConfiguration();

  /// Legge la configurazione persistita attuale.
  Future<LlamaServerConfiguration?> readConfiguration();
}

/// Implementazione predefinita basata su [JsonModelConfigurationRepository], [ProvisioningFileSystem] e [ProcessLauncher].
final class DefaultLlamaServerDependencyService
    implements LlamaServerDependencyService {
  final JsonModelConfigurationRepository _configurationRepository;
  final ProvisioningFileSystem _fileSystem;
  final ProvisioningPathResolver _pathResolver;
  final ProcessLauncher _processLauncher;
  final Duration _probeTimeout;

  DefaultLlamaServerDependencyService({
    required JsonModelConfigurationRepository configurationRepository,
    required ProvisioningFileSystem fileSystem,
    required ProvisioningPathResolver pathResolver,
    ProcessLauncher processLauncher = const DartIoProcessLauncher(),
    Duration probeTimeout = const Duration(seconds: 5),
  })  : _configurationRepository = configurationRepository,
        _fileSystem = fileSystem,
        _pathResolver = pathResolver,
        _processLauncher = processLauncher,
        _probeTimeout = probeTimeout;

  @override
  Future<LlamaServerConfiguration?> readConfiguration() async {
    final record = await _configurationRepository.readRecord();
    return record.runtime;
  }

  @override
  Future<void> clearConfiguration() async {
    await _configurationRepository.updateRecord((current) {
      return current.copyWith(runtime: null);
    });
  }

  @override
  Future<LlamaServerConfiguration> configureExecutable({
    required String executablePath,
  }) async {
    final validation = await validateExecutable(executablePath: executablePath);

    final config = LlamaServerConfiguration(
      executablePath: executablePath.trim(),
      detectedVersion: validation.detectedVersion,
      lastValidatedAtUtc: validation.lastValidatedAtUtc,
      validationStatus: validation.status,
      acceleration: validation.acceleration,
      gpuDeviceName: validation.gpuDeviceName,
    );

    await _configurationRepository.updateRecord((current) {
      return current.copyWith(runtime: config);
    });

    return config;
  }

  @override
  Future<LlamaServerDetectionResult> detect() async {
    final warnings = <String>[];
    String? configuredPath;
    var isConfiguredValid = false;

    // 1. Percorso selezionato e persistito dall'utente
    final persistedConfig = await readConfiguration();
    if (persistedConfig != null &&
        persistedConfig.executablePath.trim().isNotEmpty) {
      configuredPath = persistedConfig.executablePath.trim();
      final validation =
          await validateExecutable(executablePath: configuredPath);
      if (validation.isValid) {
        return LlamaServerDetectionResult(
          configuredCandidate: configuredPath,
          isConfiguredValid: true,
          effectiveCandidate: configuredPath,
          acceleration: validation.acceleration,
        );
      } else {
        warnings.add(
          'Il percorso configurato dall\'utente ("$configuredPath") non è più valido: '
          '${validation.errorMessage ?? validation.status.name}',
        );
      }
    }

    // 2. Eseguibile locale all'applicazione (portable bundle versionato e legacy)
    final portableCandidate1 =
        '${_pathResolver.appManagedRoot}\\runtime\\windows-x64-cuda\\llama-server.exe';
    final portableCandidate2 =
        '${_pathResolver.appManagedRoot}\\runtime\\llama-server.exe';
    final portableCandidate3 =
        '${_pathResolver.bundledRoot}\\runtime\\windows-x64-cuda\\llama-server.exe';
    final portableCandidate4 =
        '${_pathResolver.bundledRoot}\\runtime\\llama-server.exe';

    for (final candidate in [
      portableCandidate1,
      portableCandidate2,
      portableCandidate3,
      portableCandidate4
    ]) {
      if (await _fileSystem.fileExists(candidate)) {
        final validation = await validateExecutable(executablePath: candidate);
        if (validation.isValid) {
          return LlamaServerDetectionResult(
            configuredCandidate: configuredPath,
            isConfiguredValid: isConfiguredValid,
            detectedFallback: candidate,
            effectiveCandidate: candidate,
            warnings: warnings,
            acceleration: validation.acceleration,
          );
        }
      }
    }

    // 3. Eseguibili individuabili nelle estensioni di LM Studio (priorità GPU: vulkan, cuda, nvidia)
    final lmCandidates = await _detectFromLmStudioBackends();
    for (final candidate in lmCandidates) {
      if (await _fileSystem.fileExists(candidate)) {
        final validation = await validateExecutable(executablePath: candidate);
        if (validation.isValid) {
          return LlamaServerDetectionResult(
            configuredCandidate: configuredPath,
            isConfiguredValid: isConfiguredValid,
            detectedFallback: candidate,
            effectiveCandidate: candidate,
            warnings: warnings,
            acceleration: validation.acceleration,
          );
        }
      }
    }

    // 4. Eseguibile individuabile tramite il PATH di sistema (where.exe / where)
    final pathCandidate = await _detectFromSystemPath();
    if (pathCandidate != null) {
      final validation =
          await validateExecutable(executablePath: pathCandidate);
      if (validation.isValid) {
        return LlamaServerDetectionResult(
          configuredCandidate: configuredPath,
          isConfiguredValid: isConfiguredValid,
          detectedFallback: pathCandidate,
          effectiveCandidate: pathCandidate,
          warnings: warnings,
          acceleration: validation.acceleration,
        );
      }
    }

    // 4. Non trovato
    warnings.add(
      'Nessun eseguibile llama-server valido è stato individuato nel sistema.',
    );
    return LlamaServerDetectionResult(
      configuredCandidate: configuredPath,
      isConfiguredValid: false,
      effectiveCandidate: null,
      warnings: warnings,
    );
  }

  @override
  Future<LlamaServerValidationResult> validateExecutable({
    required String executablePath,
  }) async {
    final cleanPath = executablePath.trim();
    final now = DateTime.now().toUtc();

    if (cleanPath.isEmpty) {
      return LlamaServerValidationResult(
        status: LlamaServerValidationStatus.missing,
        executablePath: cleanPath,
        lastValidatedAtUtc: now,
        errorMessage: 'Il percorso dell\'eseguibile è vuoto.',
      );
    }

    // Verifiche fisiche essenziali sul filesystem
    if (await _fileSystem.directoryExists(cleanPath)) {
      return LlamaServerValidationResult(
        status: LlamaServerValidationStatus.notExecutable,
        executablePath: cleanPath,
        lastValidatedAtUtc: now,
        errorMessage: 'Il percorso specificato indica una directory.',
      );
    }

    if (!await _fileSystem.fileExists(cleanPath)) {
      return LlamaServerValidationResult(
        status: LlamaServerValidationStatus.missing,
        executablePath: cleanPath,
        lastValidatedAtUtc: now,
        errorMessage: 'Il file eseguibile non esiste sul disco.',
      );
    }

    try {
      final bytes = await _fileSystem.readAsBytes(cleanPath);
      if (bytes.isEmpty) {
        return LlamaServerValidationResult(
          status: LlamaServerValidationStatus.notExecutable,
          executablePath: cleanPath,
          lastValidatedAtUtc: now,
          errorMessage: 'Il file eseguibile ha dimensione 0 byte.',
        );
      }
    } catch (e) {
      return LlamaServerValidationResult(
        status: LlamaServerValidationStatus.notExecutable,
        executablePath: cleanPath,
        lastValidatedAtUtc: now,
        errorMessage: 'Impossibile leggere il file eseguibile: $e',
      );
    }

    // Probe processuale 1: Invocazione di --version
    final versionResult = await _runProbe(cleanPath, ['--version']);
    if (versionResult != null && versionResult.isSuccess) {
      final versionStr = _extractVersion(versionResult.output);
      final accel = _detectAcceleration(versionResult.output);
      return LlamaServerValidationResult(
        status: LlamaServerValidationStatus.valid,
        executablePath: cleanPath,
        detectedVersion: versionStr,
        lastValidatedAtUtc: now,
        acceleration: accel,
      );
    }

    // Probe processuale 2: Fallback ad invocazione di --help
    final helpResult = await _runProbe(cleanPath, ['--help']);
    if (helpResult != null && helpResult.looksLikeLlamaServerHelp) {
      final versionStr = _extractVersion(helpResult.output) ?? 'unknown';
      final accel = _detectAcceleration(helpResult.output);
      return LlamaServerValidationResult(
        status: LlamaServerValidationStatus.valid,
        executablePath: cleanPath,
        detectedVersion: versionStr,
        lastValidatedAtUtc: now,
        acceleration: accel,
      );
    }

    final errorOutput = versionResult?.output ??
        helpResult?.output ??
        'Timeout o probe fallito.';
    return LlamaServerValidationResult(
      status: LlamaServerValidationStatus.probeFailed,
      executablePath: cleanPath,
      lastValidatedAtUtc: now,
      errorMessage: 'Probe di avvio fallito: $errorOutput',
    );
  }

  Future<_ProbeRunOutput?> _runProbe(
    String executablePath,
    List<String> arguments,
  ) async {
    try {
      final env = Map<String, String>.from(io.Platform.environment);
      final userProfile = env['USERPROFILE'] ?? env['HOME'];
      if (userProfile != null && userProfile.isNotEmpty) {
        final vendorDir1 =
            '$userProfile\\.lmstudio\\extensions\\backends\\vendor\\win-llama-cuda12-vendor-v2';
        final vendorDir2 =
            '$userProfile\\.lmstudio\\extensions\\backends\\vendor\\win-llama-cuda-vendor-v2';
        final existingPath = env['PATH'] ?? '';
        env['PATH'] = '$vendorDir1;$vendorDir2;$existingPath';
      }

      final parentDir = io.File(executablePath).parent.path;

      final process = await _processLauncher.start(
        ProcessLaunchRequest(
          executable: executablePath,
          arguments: arguments,
          workingDirectory: parentDir,
          environment: env,
          runInShell: false,
        ),
      );

      final stdoutBuffer = StringBuffer();
      final stderrBuffer = StringBuffer();
      const maxBufferLength = 65536; // 64 KiB

      final stdoutSub = process.stdoutBytes.listen((chunk) {
        if (stdoutBuffer.length < maxBufferLength) {
          stdoutBuffer.write(utf8.decode(chunk, allowMalformed: true));
        }
      });

      final stderrSub = process.stderrBytes.listen((chunk) {
        if (stderrBuffer.length < maxBufferLength) {
          stderrBuffer.write(utf8.decode(chunk, allowMalformed: true));
        }
      });

      final exitCode = await process.exitCode.timeout(
        _probeTimeout,
        onTimeout: () {
          process.kill();
          return -999;
        },
      );

      unawaited(stdoutSub.cancel());
      unawaited(stderrSub.cancel());

      final fullOutput =
          '${stdoutBuffer.toString()}\n${stderrBuffer.toString()}';
      return _ProbeRunOutput(
        exitCode: exitCode,
        output: fullOutput,
      );
    } catch (_) {
      return null;
    }
  }

  Future<String?> _detectFromSystemPath() async {
    try {
      final process = await _processLauncher.start(
        const ProcessLaunchRequest(
          executable: 'where.exe',
          arguments: ['llama-server.exe'],
          runInShell: false,
        ),
      );

      final stdoutBuffer = StringBuffer();
      final stdoutDone = Completer<void>();

      final sub = process.stdoutBytes.listen(
        (chunk) {
          stdoutBuffer.write(utf8.decode(chunk, allowMalformed: true));
        },
        onDone: () {
          if (!stdoutDone.isCompleted) stdoutDone.complete();
        },
        onError: (_) {
          if (!stdoutDone.isCompleted) stdoutDone.complete();
        },
      );

      final exitCode = await process.exitCode.timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          process.kill();
          return -1;
        },
      );

      await stdoutDone.future
          .timeout(const Duration(milliseconds: 500), onTimeout: () {});

      unawaited(sub.cancel());

      if (exitCode == 0) {
        final lines = stdoutBuffer.toString().split('\n');
        for (final line in lines) {
          final clean = line.trim();
          if (clean.isNotEmpty && await _fileSystem.fileExists(clean)) {
            return clean;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  Future<List<String>> _detectFromLmStudioBackends() async {
    final candidates = <String>[];
    try {
      final userProfile = io.Platform.environment['USERPROFILE'] ??
          io.Platform.environment['HOME'];
      if (userProfile == null || userProfile.isEmpty) return candidates;

      final lmStudioBackendsDir =
          '$userProfile\\.lmstudio\\extensions\\backends';
      if (!await _fileSystem.directoryExists(lmStudioBackendsDir)) {
        return candidates;
      }

      final dir = io.Directory(lmStudioBackendsDir);
      if (!dir.existsSync()) return candidates;

      final found = <String>[];
      final entities = dir.listSync(recursive: true);
      for (final entity in entities) {
        if (entity is io.File &&
            entity.path.toLowerCase().endsWith('llama-server.exe')) {
          found.add(entity.path);
        }
      }

      found.sort((a, b) {
        final aLower = a.toLowerCase();
        final bLower = b.toLowerCase();
        final aScore = (aLower.contains('vulkan') ||
                aLower.contains('cuda') ||
                aLower.contains('nvidia'))
            ? 0
            : 1;
        final bScore = (bLower.contains('vulkan') ||
                bLower.contains('cuda') ||
                bLower.contains('nvidia'))
            ? 0
            : 1;
        return aScore.compareTo(bScore);
      });

      candidates.addAll(found);
    } catch (_) {}
    return candidates;
  }

  RuntimeAcceleration _detectAcceleration(String output) {
    final lower = output.toLowerCase();
    if (lower.contains('cuda') ||
        lower.contains('cublas') ||
        lower.contains('ggml-cuda') ||
        lower.contains('nvidia')) {
      return RuntimeAcceleration.cuda;
    }
    if (lower.contains('vulkan') || lower.contains('ggml-vulkan')) {
      return RuntimeAcceleration.vulkan;
    }
    return RuntimeAcceleration.cpu;
  }

  String? _extractVersion(String output) {
    final lower = output.toLowerCase();
    // Esempio output llama.cpp: "version: 3450 (b3450)" o "build: 3450"
    final buildMatch = RegExp(r'b\d{3,5}').firstMatch(output);
    if (buildMatch != null) {
      return buildMatch.group(0);
    }

    final versionMatch =
        RegExp(r'version[:\s]+([v\d\.]+)', caseSensitive: false)
            .firstMatch(output);
    if (versionMatch != null) {
      return versionMatch.group(1);
    }

    if (lower.contains('llama') || lower.contains('usage:')) {
      return 'detected';
    }
    return null;
  }
}

class _ProbeRunOutput {
  final int exitCode;
  final String output;

  const _ProbeRunOutput({
    required this.exitCode,
    required this.output,
  });

  bool get isSuccess => exitCode == 0;

  bool get looksLikeLlamaServerHelp {
    final lower = output.toLowerCase();
    return lower.contains('usage:') ||
        lower.contains('llama') ||
        lower.contains('options:') ||
        lower.contains('--model');
  }
}
