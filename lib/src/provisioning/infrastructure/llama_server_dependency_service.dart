import 'dart:async';
import 'dart:convert';
import 'dart:io' as io show File;

import '../../agent_runtime/runtime/adapters/managed_llama_server/dart_io_process_launcher.dart';
import '../../agent_runtime/runtime/adapters/managed_llama_server/llama_runtime_launch_environment_resolver.dart';
import '../../agent_runtime/runtime/adapters/managed_llama_server/process_launcher.dart';
import '../domain/runtime_dependency_models.dart';
import 'json_model_configuration_repository.dart';
import 'provisioning_file_system.dart';
import 'provisioning_path_resolver.dart';
import 'runtime_bundle_integrity_verifier.dart';
import 'runtime_manifest_repository.dart';

/// Contratto astratto per la gestione della dipendenza esterna `llama-server`.
abstract interface class LlamaServerDependencyService {
  /// Esegue la discovery deterministica dell'eseguibile `llama-server`.
  Future<LlamaServerDetectionResult> detect();

  /// Valida operativamente un candidato eseguibile tramite probe processuale sicuro.
  Future<LlamaServerValidationResult> validateExecutable({
    required String executablePath,
    String? variantId,
    List<String> vendorDirectories = const [],
  });

  /// Configura e persiste il percorso dell'eseguibile `llama-server`.
  Future<LlamaServerConfiguration> configureExecutable({
    required String executablePath,
    String? variantId,
    RuntimeSource? source,
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
  final LlamaRuntimeLaunchEnvironmentResolver _environmentResolver;
  final RuntimeManifestRepository _manifestRepository;
  final RuntimeBundleIntegrityVerifier _integrityVerifier;
  final Duration _probeTimeout;

  DefaultLlamaServerDependencyService({
    required JsonModelConfigurationRepository configurationRepository,
    required ProvisioningFileSystem fileSystem,
    required ProvisioningPathResolver pathResolver,
    ProcessLauncher processLauncher = const DartIoProcessLauncher(),
    LlamaRuntimeLaunchEnvironmentResolver environmentResolver =
        const DefaultLlamaRuntimeLaunchEnvironmentResolver(),
    RuntimeManifestRepository? manifestRepository,
    RuntimeBundleIntegrityVerifier? integrityVerifier,
    Duration probeTimeout = const Duration(seconds: 5),
  })  : _configurationRepository = configurationRepository,
        _fileSystem = fileSystem,
        _pathResolver = pathResolver,
        _processLauncher = processLauncher,
        _environmentResolver = environmentResolver,
        _manifestRepository = manifestRepository ??
            DefaultRuntimeManifestRepository(
              fileSystem: fileSystem,
              pathResolver: pathResolver,
            ),
        _integrityVerifier = integrityVerifier ??
            DefaultRuntimeBundleIntegrityVerifier(
              fileSystem: fileSystem,
            ),
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
    String? variantId,
    RuntimeSource? source,
  }) async {
    final validation = await validateExecutable(
      executablePath: executablePath,
      variantId: variantId,
    );

    final isBundled = executablePath.contains(_pathResolver.bundledRoot) ||
        executablePath.contains(_pathResolver.appManagedRoot) ||
        (variantId != null && variantId.isNotEmpty);

    final effectiveSource =
        source ?? (isBundled ? RuntimeSource.bundled : RuntimeSource.external);

    final config = LlamaServerConfiguration(
      schemaVersion: 1,
      source: effectiveSource,
      variantId: variantId ?? validation.variantId,
      externalExecutablePath: effectiveSource == RuntimeSource.external
          ? executablePath.trim()
          : null,
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

    // 1. Prova prima la configurazione gestita/persistita precedentemente valida (last-known-good)
    final persistedConfig = await readConfiguration();
    if (persistedConfig != null) {
      final rawConfigured = persistedConfig.externalExecutablePath ??
          persistedConfig.executablePath;
      if (rawConfigured.trim().isNotEmpty) {
        configuredPath = rawConfigured.trim();
      }

      if (persistedConfig.source == RuntimeSource.bundled &&
          persistedConfig.variantId != null) {
        final manifest = await _manifestRepository.readManifest();
        if (manifest != null) {
          final variant = manifest.findVariantById(persistedConfig.variantId!);
          if (variant != null) {
            final roots = [
              '${_pathResolver.bundledRoot}\\runtime',
              '${_pathResolver.appManagedRoot}\\runtime',
            ];
            for (final root in roots) {
              final integrity = await _integrityVerifier.verifyVariant(
                variant: variant,
                runtimeRootPath: root,
              );
              if (integrity.isValid) {
                final resolvedExe =
                    '$root\\${variant.executable.replaceAll('/', '\\')}';
                final resolvedVendors = variant.vendorDirectories
                    .map((v) => '$root\\${v.replaceAll('/', '\\')}')
                    .toList();

                final validation = await validateExecutable(
                  executablePath: resolvedExe,
                  variantId: variant.id,
                  vendorDirectories: resolvedVendors,
                );

                if (validation.isValid) {
                  return LlamaServerDetectionResult(
                    configuredCandidate: resolvedExe,
                    isConfiguredValid: true,
                    effectiveCandidate: resolvedExe,
                    variantId: variant.id,
                    declaredAcceleration: variant.acceleration,
                    acceleration: validation.acceleration,
                  );
                }
              }
            }
          }
        }
      } else if (configuredPath != null) {
        final validation = await validateExecutable(
          executablePath: configuredPath,
          variantId: persistedConfig.variantId,
        );
        if (validation.isValid) {
          return LlamaServerDetectionResult(
            configuredCandidate: configuredPath,
            isConfiguredValid: true,
            effectiveCandidate: configuredPath,
            variantId: validation.variantId ?? persistedConfig.variantId,
            declaredAcceleration: validation.declaredAcceleration,
            acceleration: validation.acceleration,
          );
        } else {
          warnings.add(
            'La configurazione runtime precedente ("$configuredPath") non è più valida: '
            '${validation.errorMessage ?? validation.status.name}',
          );
        }
      }
    }

    // 2. Discovery guidata dal manifest canonico runtime-manifest.json
    final manifest = await _manifestRepository.readManifest();
    String? lastFallbackReason;

    if (manifest != null) {
      final roots = [
        '${_pathResolver.bundledRoot}\\runtime',
        '${_pathResolver.appManagedRoot}\\runtime',
        _pathResolver.bundledRoot,
        _pathResolver.appManagedRoot,
      ];

      // Ordine di priorità variante: win-x64-cuda -> win-x64-vulkan -> win-x64-cpu-avx2
      final priorityVariantIds = [
        'win-x64-cuda',
        'win-x64-vulkan',
        'win-x64-cpu-avx2',
      ];

      final sortedVariants = manifest.variants.toList()
        ..sort((a, b) {
          final indexA = priorityVariantIds.indexOf(a.id);
          final indexB = priorityVariantIds.indexOf(b.id);
          final posA = indexA != -1 ? indexA : 99;
          final posB = indexB != -1 ? indexB : 99;
          return posA.compareTo(posB);
        });

      for (final variant in sortedVariants) {
        for (final root in roots) {
          final integrity = await _integrityVerifier.verifyVariant(
            variant: variant,
            runtimeRootPath: root,
          );

          if (integrity.isValid) {
            final resolvedExe =
                '$root\\${variant.executable.replaceAll('/', '\\')}';
            final resolvedVendors = variant.vendorDirectories
                .map((v) => '$root\\${v.replaceAll('/', '\\')}')
                .toList();

            final validation = await validateExecutable(
              executablePath: resolvedExe,
              variantId: variant.id,
              vendorDirectories: resolvedVendors,
            );

            if (validation.isValid) {
              return LlamaServerDetectionResult(
                configuredCandidate: configuredPath,
                isConfiguredValid: false,
                detectedFallback: resolvedExe,
                effectiveCandidate: resolvedExe,
                variantId: variant.id,
                declaredAcceleration: variant.acceleration,
                acceleration: validation.acceleration,
                warnings: warnings,
              );
            } else {
              lastFallbackReason =
                  'Probe operativo della variante ${variant.id} fallito (${validation.errorMessage}). Ripiego su variante successiva.';
              warnings.add(lastFallbackReason);
            }
          } else {
            lastFallbackReason =
                'Verifica integrità SHA-256 della variante ${variant.id} fallita (${integrity.errorMessage}). Ripiego su variante successiva.';
            warnings.add(lastFallbackReason);
          }
        }
      }
    }

    // 3. Fallback a candidati legacy hardcoded se manifest non disponibile o non soddisfacente
    final legacyCandidates = [
      (
        variantId: 'win-x64-cuda',
        accel: RuntimeAcceleration.cuda,
        paths: [
          '${_pathResolver.appManagedRoot}\\runtime\\bin\\win-x64-cuda\\llama-server.exe',
          '${_pathResolver.bundledRoot}\\runtime\\bin\\win-x64-cuda\\llama-server.exe',
          '${_pathResolver.appManagedRoot}\\runtime\\windows-x64-cuda\\llama-server.exe',
          '${_pathResolver.bundledRoot}\\runtime\\windows-x64-cuda\\llama-server.exe',
        ],
        vendorDirs: (String path) => [
              '${io.File(path).parent.path}\\vendor',
            ]
      ),
      (
        variantId: 'win-x64-vulkan',
        accel: RuntimeAcceleration.vulkan,
        paths: [
          '${_pathResolver.appManagedRoot}\\runtime\\bin\\win-x64-vulkan\\llama-server.exe',
          '${_pathResolver.bundledRoot}\\runtime\\bin\\win-x64-vulkan\\llama-server.exe',
        ],
        vendorDirs: (String path) => [
              '${io.File(path).parent.path}\\vendor',
            ]
      ),
      (
        variantId: 'win-x64-cpu-avx2',
        accel: RuntimeAcceleration.cpu,
        paths: [
          '${_pathResolver.appManagedRoot}\\runtime\\bin\\win-x64-cpu-avx2\\llama-server.exe',
          '${_pathResolver.bundledRoot}\\runtime\\bin\\win-x64-cpu-avx2\\llama-server.exe',
          '${_pathResolver.appManagedRoot}\\runtime\\llama-server.exe',
          '${_pathResolver.bundledRoot}\\runtime\\llama-server.exe',
        ],
        vendorDirs: (String path) => <String>[]
      ),
    ];

    for (final candidateGroup in legacyCandidates) {
      for (final candidate in candidateGroup.paths) {
        if (await _fileSystem.fileExists(candidate)) {
          final vendors = candidateGroup.vendorDirs(candidate);
          final validation = await validateExecutable(
            executablePath: candidate,
            variantId: candidateGroup.variantId,
            vendorDirectories: vendors,
          );
          if (validation.isValid) {
            return LlamaServerDetectionResult(
              configuredCandidate: configuredPath,
              isConfiguredValid: false,
              detectedFallback: candidate,
              effectiveCandidate: candidate,
              variantId: candidateGroup.variantId,
              declaredAcceleration: candidateGroup.accel,
              acceleration: validation.acceleration,
              warnings: warnings,
            );
          }
        }
      }
    }

    // 3. Fallback ad eseguibile nel PATH di sistema (where.exe / where)
    final pathCandidate = await _detectFromSystemPath();
    if (pathCandidate != null) {
      final validation =
          await validateExecutable(executablePath: pathCandidate);
      if (validation.isValid) {
        return LlamaServerDetectionResult(
          configuredCandidate: configuredPath,
          isConfiguredValid: false,
          detectedFallback: pathCandidate,
          effectiveCandidate: pathCandidate,
          acceleration: validation.acceleration,
          warnings: warnings,
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
      fallbackReason: lastFallbackReason,
    );
  }

  @override
  Future<LlamaServerValidationResult> validateExecutable({
    required String executablePath,
    String? variantId,
    List<String> vendorDirectories = const [],
  }) async {
    final cleanPath = executablePath.trim();
    final now = DateTime.now().toUtc();

    if (cleanPath.isEmpty) {
      return LlamaServerValidationResult(
        status: LlamaServerValidationStatus.missing,
        executablePath: cleanPath,
        variantId: variantId,
        lastValidatedAtUtc: now,
        errorMessage: 'Il percorso dell\'eseguibile è vuoto.',
      );
    }

    if (await _fileSystem.directoryExists(cleanPath)) {
      return LlamaServerValidationResult(
        status: LlamaServerValidationStatus.notExecutable,
        executablePath: cleanPath,
        variantId: variantId,
        lastValidatedAtUtc: now,
        errorMessage: 'Il percorso specificato indica una directory.',
      );
    }

    if (!await _fileSystem.fileExists(cleanPath)) {
      return LlamaServerValidationResult(
        status: LlamaServerValidationStatus.missing,
        executablePath: cleanPath,
        variantId: variantId,
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
          variantId: variantId,
          lastValidatedAtUtc: now,
          errorMessage: 'Il file eseguibile ha dimensione 0 byte.',
        );
      }
    } catch (e) {
      return LlamaServerValidationResult(
        status: LlamaServerValidationStatus.notExecutable,
        executablePath: cleanPath,
        variantId: variantId,
        lastValidatedAtUtc: now,
        errorMessage: 'Impossibile leggere il file eseguibile: $e',
      );
    }

    // Probe processuale 1: Invocazione di --version
    final versionResult = await _runProbe(
      cleanPath,
      ['--version'],
      vendorDirectories: vendorDirectories,
    );
    if (versionResult != null && versionResult.isSuccess) {
      final versionStr = _extractVersion(versionResult.output);
      final accel = _detectAcceleration(versionResult.output);
      return LlamaServerValidationResult(
        status: LlamaServerValidationStatus.valid,
        executablePath: cleanPath,
        variantId: variantId,
        detectedVersion: versionStr,
        lastValidatedAtUtc: now,
        acceleration: accel,
      );
    }

    // Probe processuale 2: Fallback ad invocazione di --help
    final helpResult = await _runProbe(
      cleanPath,
      ['--help'],
      vendorDirectories: vendorDirectories,
    );
    if (helpResult != null && helpResult.looksLikeLlamaServerHelp) {
      final versionStr = _extractVersion(helpResult.output) ?? 'unknown';
      final accel = _detectAcceleration(helpResult.output);
      return LlamaServerValidationResult(
        status: LlamaServerValidationStatus.valid,
        executablePath: cleanPath,
        variantId: variantId,
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
      variantId: variantId,
      lastValidatedAtUtc: now,
      errorMessage: 'Probe di avvio fallito: $errorOutput',
    );
  }

  Future<_ProbeRunOutput?> _runProbe(
    String executablePath,
    List<String> arguments, {
    List<String> vendorDirectories = const [],
  }) async {
    try {
      final parentDir = io.File(executablePath).parent.path;
      final resolvedEnv = _environmentResolver.resolve(
        executablePath: executablePath,
        workingDirectory: parentDir,
        vendorDirectories: vendorDirectories,
      );

      final process = await _processLauncher.start(
        ProcessLaunchRequest(
          executable: executablePath,
          arguments: arguments,
          workingDirectory: resolvedEnv.workingDirectory,
          environment: resolvedEnv.environmentOverrides,
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
