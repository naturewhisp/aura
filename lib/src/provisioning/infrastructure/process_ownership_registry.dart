import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';

import 'process_ownership_record.dart';
import 'provisioning_lock.dart';
import 'provisioning_path_resolver.dart';

typedef ProcessExistenceChecker = Future<bool> Function(
    ProcessOwnershipRecord record);
typedef ProcessTerminator = Future<bool> Function(int pid);

/// Astrazione per l'esecuzione di comandi di sistema per l'ispezione dei processi.
abstract interface class ProcessCommandRunner {
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    Duration? timeout,
  });
}

/// Implementazione standard di [ProcessCommandRunner] basata su [Process.run].
final class StandardProcessCommandRunner implements ProcessCommandRunner {
  const StandardProcessCommandRunner();

  @override
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    Duration? timeout,
  }) async {
    final future = Process.run(executable, arguments);
    if (timeout != null) {
      return future.timeout(timeout);
    }
    return future;
  }
}

/// Astrazione per la risoluzione dell'identità/percorso dell'eseguibile dato un PID.
abstract interface class ProcessExecutablePathResolver {
  Future<String?> resolveExecutablePath(int pid);
}

/// Implementazione standard di [ProcessExecutablePathResolver] basata su comandi di sistema.
final class StandardProcessExecutablePathResolver
    implements ProcessExecutablePathResolver {
  final ProcessCommandRunner _commandRunner;
  final bool _isWindows;

  StandardProcessExecutablePathResolver({
    ProcessCommandRunner commandRunner = const StandardProcessCommandRunner(),
    bool? isWindows,
  })  : _commandRunner = commandRunner,
        _isWindows = isWindows ?? Platform.isWindows;

  @override
  Future<String?> resolveExecutablePath(int pid) async {
    if (_isWindows) {
      return _resolveWindows(pid);
    } else {
      return _resolvePosix(pid);
    }
  }

  Future<String?> _resolveWindows(int pid) async {
    try {
      final exeRes = await _commandRunner.run(
        'wmic',
        [
          'process',
          'where',
          'ProcessId=$pid',
          'get',
          'ExecutablePath',
        ],
        timeout: const Duration(seconds: 2),
      );

      if (exeRes.exitCode != 0) return null;
      final lines = (exeRes.stdout as String)
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty && l.toLowerCase() != 'executablepath')
          .toList();

      if (lines.isEmpty) return null;
      final first = lines.first;
      if (first.toLowerCase().startsWith('executablepath=')) {
        return first.substring('executablepath='.length).trim();
      }
      return first;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _resolvePosix(int pid) async {
    // 1. Tentativo primario: lsof -a -p <pid> -d txt -Fn (macOS / BSD)
    // -Fn fornisce output machine-readable privo di ambiguità anche con spazi nel path.
    try {
      final lsofRes = await _commandRunner.run(
        'lsof',
        ['-a', '-p', '$pid', '-d', 'txt', '-Fn'],
        timeout: const Duration(seconds: 2),
      );
      if (lsofRes.exitCode == 0) {
        final stdoutText = lsofRes.stdout as String;
        for (final line in stdoutText.split('\n')) {
          final trimmed = line.trim();
          if (trimmed.startsWith('n/')) {
            return trimmed.substring(1);
          }
        }
      }
    } catch (_) {}

    // 2. Fallback: ps -p <pid> -o command=
    // Isola l'eseguibile gestendo i percorsi contenenti spazi che terminano prima dei flag d'avvio (es. ' -').
    try {
      final psRes = await _commandRunner.run(
        'ps',
        ['-p', '$pid', '-o', 'command='],
        timeout: const Duration(seconds: 2),
      );
      if (psRes.exitCode == 0) {
        final commandOutput = (psRes.stdout as String).trim();
        if (commandOutput.isNotEmpty) {
          final flagIndex = commandOutput.indexOf(' -');
          if (flagIndex != -1) {
            return commandOutput.substring(0, flagIndex).trim();
          }
          return commandOutput;
        }
      }
    } catch (_) {}

    return null;
  }
}

/// Superficie di gestione persistente per la tracciabilità e la bonifica atomica dei processi managed AURA.
@immutable
final class ProcessOwnershipRegistry {
  final ProvisioningPathResolver _pathResolver;
  final ProvisioningLock _lock;
  final ProcessExistenceChecker? _customChecker;
  final ProcessTerminator? _customTerminator;
  final ProcessCommandRunner _commandRunner;
  final ProcessExecutablePathResolver _executablePathResolver;
  final bool _isWindows;

  ProcessOwnershipRegistry({
    required ProvisioningPathResolver pathResolver,
    ProvisioningLock? lock,
    ProcessExistenceChecker? processChecker,
    ProcessTerminator? processTerminator,
    ProcessCommandRunner? commandRunner,
    ProcessExecutablePathResolver? executablePathResolver,
    bool? isWindows,
  })  : _pathResolver = pathResolver,
        _lock = lock ??
            FileBasedProvisioningLock(
              lockDirectory: pathResolver.join(
                pathResolver.appManagedRoot,
                pathResolver.join('runtime', 'processes'),
              ),
            ),
        _customChecker = processChecker,
        _customTerminator = processTerminator,
        _commandRunner = commandRunner ?? const StandardProcessCommandRunner(),
        _isWindows = isWindows ?? Platform.isWindows,
        _executablePathResolver = executablePathResolver ??
            StandardProcessExecutablePathResolver(
              commandRunner:
                  commandRunner ?? const StandardProcessCommandRunner(),
              isWindows: isWindows ?? Platform.isWindows,
            );

  /// Directory dei file di registro processi.
  String get processesDirectory => _pathResolver.join(
        _pathResolver.appManagedRoot,
        _pathResolver.join('runtime', 'processes'),
      );

  /// Percorso del file JSON di registro per un dato ruolo.
  String recordPathForRole(String role) {
    final cleanRole = role.trim().toLowerCase();
    return _pathResolver.join(processesDirectory, '$cleanRole.json');
  }

  /// Acquisisce il lock inter-processo di bootstrap per la sincronizzazione del ciclo di vita.
  Future<T> withBootstrapLock<T>(Future<T> Function() action) async {
    return _lock.synchronized('bootstrap', action);
  }

  /// Legge il record di ownership per un determinato ruolo se esistente e valido.
  Future<ProcessOwnershipRecord?> getRecord(String role) async {
    final path = recordPathForRole(role);
    final file = File(path);
    if (!await file.exists()) {
      return null;
    }

    try {
      final content = await file.readAsString();
      if (content.trim().isEmpty) return null;
      final json = jsonDecode(content) as Map<String, dynamic>;
      return ProcessOwnershipRecord.fromJson(json);
    } catch (_) {
      // In caso di file corrotto o parziale, restituisce null consentendo lo stale cleanup
      return null;
    }
  }

  /// Registra atomicamente il processo per il ruolo specificato.
  Future<void> registerRecord(ProcessOwnershipRecord record) async {
    await withBootstrapLock(() async {
      final dir = Directory(processesDirectory);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final targetPath = recordPathForRole(record.role);
      final tempPath =
          '$targetPath.tmp.${DateTime.now().microsecondsSinceEpoch}';

      final tempFile = File(tempPath);
      final jsonString =
          const JsonEncoder.withIndent('  ').convert(record.toJson());
      await tempFile.writeAsString(jsonString, flush: true);

      final targetFile = File(targetPath);
      if (await targetFile.exists()) {
        await targetFile.delete();
      }
      await tempFile.rename(targetPath);
    });
  }

  /// Rimuove il record di ownership per un determinato ruolo.
  Future<void> unregisterRecord(String role) async {
    await withBootstrapLock(() async {
      await _deleteRecordFile(role);
    });
  }

  Future<void> _deleteRecordFile(String role) async {
    final path = recordPathForRole(role);
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Restituisce la lista di tutti i record di ownership attivi sul disco.
  Future<List<ProcessOwnershipRecord>> listRecords() async {
    final dir = Directory(processesDirectory);
    if (!await dir.exists()) return [];

    final records = <ProcessOwnershipRecord>[];
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.json')) {
        try {
          final content = await entity.readAsString();
          if (content.trim().isNotEmpty) {
            final json = jsonDecode(content) as Map<String, dynamic>;
            records.add(ProcessOwnershipRecord.fromJson(json));
          }
        } catch (_) {}
      }
    }
    return records;
  }

  /// Esegue la bonifica deterministica dei processi stale di AURA prima di un nuovo bootstrap.
  /// Riconosce e termina unicamente i processi attivi il cui PID ed il cui eseguibile corrispondono
  /// all'ownership record registrato da AURA.
  Future<List<ProcessOwnershipRecord>> cleanupStaleProcesses({
    String? currentOwnerInstanceId,
  }) async {
    return withBootstrapLock(() async {
      final records = await listRecords();
      final cleaned = <ProcessOwnershipRecord>[];

      for (final record in records) {
        // Se il record appartiene alla sessione corrente attiva, non pulirlo
        if (currentOwnerInstanceId != null &&
            record.ownerInstanceId == currentOwnerInstanceId) {
          continue;
        }

        final isAliveAndMatching = await _isProcessAliveAndMatching(record);

        if (isAliveAndMatching) {
          final killed = await _terminateProcess(record.pid);
          if (killed) {
            cleaned.add(record);
          }
        } else {
          // Processo non piu attivo o non corrispondente, puliamo solo il record stale
          cleaned.add(record);
        }

        // Rimuoviamo il file JSON del record obsoleto
        await _deleteRecordFile(record.role);
      }

      return cleaned;
    });
  }

  /// Verifica se il PID è attivo ed il percorso dell'eseguibile corrisponde all'hash registrato.
  Future<bool> _isProcessAliveAndMatching(ProcessOwnershipRecord record) async {
    if (_customChecker != null) {
      return _customChecker!(record);
    }

    // 1. Controllo non distruttivo dell'esistenza del processo
    final isAlive = await _isProcessAlive(record.pid);
    if (!isAlive) return false;

    // 2. Risoluzione dell'eseguibile e confronto SHA-256 platform-aware
    final exePath =
        await _executablePathResolver.resolveExecutablePath(record.pid);
    if (exePath == null || exePath.isEmpty) return false;

    final currentHash =
        ProcessOwnershipRecord.hashPath(exePath, isWindows: _isWindows);
    return currentHash == record.executablePathHash;
  }

  /// Verifica la liveness del PID in modo non distruttivo sulla piattaforma corrente.
  Future<bool> _isProcessAlive(int pid) async {
    if (!_isWindows) {
      try {
        final killRes = await _commandRunner.run(
          'kill',
          ['-0', '$pid'],
          timeout: const Duration(seconds: 2),
        );
        return killRes.exitCode == 0;
      } catch (_) {
        return false;
      }
    }

    try {
      final tasklistRes = await _commandRunner.run(
        'tasklist',
        [
          '/FI',
          'PID eq $pid',
          '/FO',
          'CSV',
          '/NH',
        ],
        timeout: const Duration(seconds: 2),
      );

      if (tasklistRes.exitCode != 0) return false;
      final stdoutText = (tasklistRes.stdout as String).trim();
      return stdoutText.isNotEmpty &&
          !stdoutText.contains('INFO:') &&
          stdoutText.contains('"$pid"');
    } catch (_) {
      return false;
    }
  }

  /// Termina in modo forzato un processo dato il PID.
  Future<bool> _terminateProcess(int pid) async {
    if (_customTerminator != null) {
      return _customTerminator!(pid);
    }

    if (_isWindows) {
      try {
        final result = await _commandRunner.run(
          'taskkill',
          ['/F', '/PID', '$pid'],
        );
        return result.exitCode == 0;
      } catch (_) {
        return false;
      }
    } else {
      try {
        final result = await _commandRunner.run(
          'kill',
          ['-9', '$pid'],
        );
        if (result.exitCode == 0) return true;
      } catch (_) {}

      try {
        return Process.killPid(pid, ProcessSignal.sigkill);
      } catch (_) {
        return false;
      }
    }
  }
}
