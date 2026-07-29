import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';

import 'process_ownership_record.dart';
import 'provisioning_lock.dart';
import 'provisioning_path_resolver.dart';

typedef ProcessExistenceChecker = Future<bool> Function(
    ProcessOwnershipRecord record);
typedef ProcessTerminator = Future<bool> Function(int pid);

/// Superficie di gestione persistente per la tracciabilità e la bonifica atomica dei processi managed AURA.
@immutable
final class ProcessOwnershipRegistry {
  final ProvisioningPathResolver _pathResolver;
  final ProvisioningLock _lock;
  final ProcessExistenceChecker? _customChecker;
  final ProcessTerminator? _customTerminator;

  ProcessOwnershipRegistry({
    required ProvisioningPathResolver pathResolver,
    ProvisioningLock? lock,
    ProcessExistenceChecker? processChecker,
    ProcessTerminator? processTerminator,
  })  : _pathResolver = pathResolver,
        _lock = lock ??
            FileBasedProvisioningLock(
              lockDirectory:
                  _join(pathResolver.appManagedRoot, r'runtime\processes'),
            ),
        _customChecker = processChecker,
        _customTerminator = processTerminator;

  /// Directory dei file di registro processi.
  String get processesDirectory =>
      _join(_pathResolver.appManagedRoot, r'runtime\processes');

  static String _join(String p1, String p2) =>
      p1.endsWith(r'\') || p1.endsWith('/')
          ? '$p1$p2'
          : '$p1${Platform.pathSeparator}$p2';

  /// Percorso del file JSON di registro per un dato ruolo.
  String recordPathForRole(String role) {
    final cleanRole = role.trim().toLowerCase();
    return _join(processesDirectory, '$cleanRole.json');
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

    if (!Platform.isWindows) {
      try {
        return Process.killPid(record.pid, ProcessSignal.sigkill);
      } catch (_) {
        return false;
      }
    }

    try {
      // 1. Controllo ultra-veloce dell'esistenza del PID tramite tasklist
      final tasklistRes = await Process.run('tasklist', [
        '/FI',
        'PID eq ${record.pid}',
        '/FO',
        'CSV',
        '/NH',
      ]).timeout(const Duration(seconds: 2));

      if (tasklistRes.exitCode != 0) return false;
      final stdoutText = (tasklistRes.stdout as String).trim();
      if (stdoutText.isEmpty ||
          stdoutText.contains('INFO:') ||
          !stdoutText.contains('"${record.pid}"')) {
        return false;
      }

      // 2. Se attivo, verifichiamo il percorso dell'eseguibile
      final exeRes = await Process.run('wmic', [
        'process',
        'where',
        'ProcessId=${record.pid}',
        'get',
        'ExecutablePath',
      ]).timeout(const Duration(seconds: 2));

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

    if (Platform.isWindows) {
      try {
        final result = await Process.run('taskkill', ['/F', '/PID', '$pid']);
        return result.exitCode == 0;
      } catch (_) {
        return false;
      }
    } else {
      return Process.killPid(pid, ProcessSignal.sigkill);
    }
  }
}
