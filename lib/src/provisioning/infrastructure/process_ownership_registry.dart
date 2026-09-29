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

/// Superficie di gestione persistente per la tracciabilità e la bonifica atomica dei processi managed AURA.
@immutable
final class ProcessOwnershipRegistry {
  final ProvisioningPathResolver _pathResolver;
  final ProvisioningLock _lock;
  final ProcessExistenceChecker? _customChecker;
  final ProcessTerminator? _customTerminator;
  final ProcessCommandRunner _commandRunner;
  final bool _isWindows;

  ProcessOwnershipRegistry({
    required ProvisioningPathResolver pathResolver,
    ProvisioningLock? lock,
    ProcessExistenceChecker? processChecker,
    ProcessTerminator? processTerminator,
    ProcessCommandRunner? commandRunner,
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
        _isWindows = isWindows ?? Platform.isWindows;

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

  /// Verifica se il PID e attivo ed il percorso dell'eseguibile corrisponde all'hash registrato.
  Future<bool> _isProcessAliveAndMatching(ProcessOwnershipRecord record) async {
    if (_customChecker != null) {
      return _customChecker!(record);
    }

    if (!_isWindows) {
      try {
        // 1. Controllo non distruttivo dell'esistenza del processo via kill -0
        final killRes = await _commandRunner.run(
          'kill',
          ['-0', '${record.pid}'],
          timeout: const Duration(seconds: 2),
        );
        if (killRes.exitCode != 0) {
          return false;
        }

        // 2. Ispezione della riga di comando del processo via ps
        final psRes = await _commandRunner.run(
          'ps',
          ['-p', '${record.pid}', '-o', 'command='],
          timeout: const Duration(seconds: 2),
        );
        if (psRes.exitCode != 0) {
          return false;
        }

        final commandOutput = (psRes.stdout as String).trim();
        if (commandOutput.isEmpty) {
          return false;
        }

        // Il primo token della riga di comando corrisponde al binario/eseguibile
        final exePath = commandOutput.split(RegExp(r'\s+')).first;
        final currentHash = ProcessOwnershipRecord.hashPath(exePath);
        return currentHash == record.executablePathHash;
      } catch (_) {
        return false;
      }
    }

    try {
      // 1. Controllo ultra-veloce dell'esistenza del PID tramite tasklist
      final tasklistRes = await _commandRunner.run(
        'tasklist',
        [
          '/FI',
          'PID eq ${record.pid}',
          '/FO',
          'CSV',
          '/NH',
        ],
        timeout: const Duration(seconds: 2),
      );

      if (tasklistRes.exitCode != 0) return false;
      final stdoutText = (tasklistRes.stdout as String).trim();
      if (stdoutText.isEmpty ||
          stdoutText.contains('INFO:') ||
          !stdoutText.contains('"${record.pid}"')) {
        return false;
      }

      // 2. Se attivo, verifichiamo il percorso dell'eseguibile via wmic
      final exeRes = await _commandRunner.run(
        'wmic',
        [
          'process',
          'where',
          'ProcessId=${record.pid}',
          'get',
          'ExecutablePath',
        ],
        timeout: const Duration(seconds: 2),
      );

      if (exeRes.exitCode != 0) return false;
      final lines = (exeRes.stdout as String)
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty && l.toLowerCase() != 'executablepath')
          .toList();

      if (lines.isEmpty) return false;
      final exePath = lines.first;
      final currentHash = ProcessOwnershipRecord.hashPath(exePath);
      return currentHash == record.executablePathHash;
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
