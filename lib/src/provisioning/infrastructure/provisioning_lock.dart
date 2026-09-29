import 'dart:async';
import 'dart:io';
import 'package:meta/meta.dart';
import '../domain/provisioning_options.dart';

/// Contratto astratto per il lock e la serializzazione delle operazioni di provisioning.
@immutable
abstract interface class ProvisioningLock {
  /// Esegue l'azione specificata serializzando l'accesso per la chiave fornita.
  Future<T> synchronized<T>(
    String key,
    Future<T> Function() action,
  );
}

/// Implementazione in-memory basata su accodamento asincrono deterministico per chiave.
final class InMemoryProvisioningLock implements ProvisioningLock {
  final Map<String, Future<dynamic>> _keyLocks;

  InMemoryProvisioningLock() : _keyLocks = {};

  @override
  Future<T> synchronized<T>(
    String key,
    Future<T> Function() action,
  ) async {
    final cleanKey = key.trim().toLowerCase();
    if (cleanKey.isEmpty) {
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.installationConflict,
        message: 'La chiave di lock non può essere vuota.',
      );
    }

    final previousLock = _keyLocks[cleanKey];
    final completer = Completer<void>();
    _keyLocks[cleanKey] = completer.future;

    if (previousLock != null) {
      try {
        await previousLock;
      } catch (_) {}
    }

    try {
      return await action();
    } finally {
      completer.complete();
      if (identical(_keyLocks[cleanKey], completer.future)) {
        _keyLocks.remove(cleanKey);
      }
    }
  }
}

/// Implementazione di file lock inter-processo atomico con fallback intra-processo e timeout controllato.
final class FileBasedProvisioningLock implements ProvisioningLock {
  final String _lockDirectory;
  final Duration acquisitionTimeout;
  final Duration retryInterval;
  final Duration maxWaitDuration;

  /// Registro statico delle chiavi correntemente acquisite all'interno dello stesso processo.
  /// Necessario su sistemi POSIX (macOS/Linux) dove i lock `fcntl` a livello kernel
  /// sono associati al processo (PID) e non al singolo file handle, rendendo necessaria
  /// la mutua esclusione cooperativa tra istanze concorrenti nello stesso runtime Dart.
  static final Set<String> _heldProcessKeys = {};

  FileBasedProvisioningLock({
    required String lockDirectory,
    this.acquisitionTimeout = const Duration(milliseconds: 100),
    this.retryInterval = const Duration(milliseconds: 50),
    this.maxWaitDuration = const Duration(seconds: 5),
  }) : _lockDirectory = lockDirectory;

  @override
  Future<T> synchronized<T>(
    String key,
    Future<T> Function() action,
  ) async {
    final sanitizedKey = key.replaceAll(RegExp(r'[^\w\.-]'), '_');
    if (sanitizedKey.isEmpty) {
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.installationConflict,
        message: 'La chiave di lock non può essere vuota.',
      );
    }

    final stopwatch = Stopwatch()..start();
    final processKey = '$_lockDirectory:$sanitizedKey';

    final lockDir = Directory(_lockDirectory);
    if (!await lockDir.exists()) {
      await lockDir.create(recursive: true);
    }

    final lockFilePath =
        '${lockDir.path}${Platform.pathSeparator}$sanitizedKey.lock';
    final lockFile = File(lockFilePath);

    RandomAccessFile? raf;
    var acquired = false;

    while (!acquired) {
      if (_heldProcessKeys.contains(processKey)) {
        if (stopwatch.elapsed >= maxWaitDuration) {
          throw ProvisioningException(
            reason: ProvisioningFailureReason.installationConflict,
            message:
                'Timeout durante l\'attesa del lock intra-processo per la risorsa "$key" su "$lockFilePath" entro ${maxWaitDuration.inMilliseconds}ms.',
          );
        }
        await Future.delayed(retryInterval);
        continue;
      }

      RandomAccessFile? candidateRaf;
      try {
        candidateRaf = await lockFile.open(mode: FileMode.write);
        await candidateRaf.lock(FileLock.exclusive).timeout(acquisitionTimeout);

        if (_heldProcessKeys.contains(processKey)) {
          try {
            await candidateRaf.unlock();
          } catch (_) {}
          try {
            await candidateRaf.close();
          } catch (_) {}

          if (stopwatch.elapsed >= maxWaitDuration) {
            throw ProvisioningException(
              reason: ProvisioningFailureReason.installationConflict,
              message:
                  'Timeout durante l\'acquisizione del lock per la risorsa "$key" su "$lockFilePath" entro ${maxWaitDuration.inMilliseconds}ms.',
            );
          }
          await Future.delayed(retryInterval);
          continue;
        }

        _heldProcessKeys.add(processKey);
        raf = candidateRaf;
        acquired = true;
      } catch (_) {
        if (candidateRaf != null) {
          try {
            await candidateRaf.close();
          } catch (_) {}
        }
        if (stopwatch.elapsed >= maxWaitDuration) {
          throw ProvisioningException(
            reason: ProvisioningFailureReason.installationConflict,
            message:
                'Impossibile acquisire il file lock inter-processo per "$key" su "$lockFilePath" entro il timeout di ${maxWaitDuration.inMilliseconds}ms.',
          );
        }
        await Future.delayed(retryInterval);
      }
    }

    try {
      return await action();
    } finally {
      _heldProcessKeys.remove(processKey);
      if (raf != null) {
        try {
          await raf.unlock();
        } catch (_) {}
        try {
          await raf.close();
        } catch (_) {}
      }
    }
  }
}
