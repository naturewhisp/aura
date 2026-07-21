import 'dart:io';
import '../domain/provisioning_options.dart';
import 'provisioning_path_resolver.dart';

/// Gestisce un lock sul filesystem per prevenire esecuzioni di provisioning concorrenti.
final class FileSystemLock {
  static final Set<String> _activeLockPathsInProcess = {};

  final ProvisioningPathResolver _pathResolver;
  RandomAccessFile? _lockFileAccess;
  File? _lockFile;

  FileSystemLock({
    required ProvisioningPathResolver pathResolver,
  }) : _pathResolver = pathResolver;

  /// Acquisisce un lock esclusivo sul file `provisioning.lock`.
  /// Se il lock è già acquisito da un altro processo o thread, lancia una [ProvisioningException].
  Future<void> acquire() async {
    if (_lockFileAccess != null) {
      return; // Già acquisito da questa istanza
    }

    final lockFilePath = '${_pathResolver.stagingDirectory}\\provisioning.lock';
    final canonicalKey = lockFilePath.toLowerCase();

    if (_activeLockPathsInProcess.contains(canonicalKey)) {
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.installationConflict,
        message:
            'Un\'altra operazione di provisioning è attualmente in corso sul sistema.',
      );
    }

    final stagingDir = Directory(_pathResolver.stagingDirectory);
    if (!await stagingDir.exists()) {
      await stagingDir.create(recursive: true);
    }

    final candidateFile = File(lockFilePath);

    try {
      final access = await candidateFile.open(mode: FileMode.write);
      await access.lock(FileLock.exclusive);
      _activeLockPathsInProcess.add(canonicalKey);
      _lockFile = candidateFile;
      _lockFileAccess = access;
    } catch (_) {
      _activeLockPathsInProcess.remove(canonicalKey);
      _lockFile = null;
      _lockFileAccess = null;
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.installationConflict,
        message:
            'Un\'altra operazione di provisioning è attualmente in corso sul sistema.',
      );
    }
  }

  /// Rilascia il lock esclusivo ed elimina il file di lock appartenente a questa istanza.
  Future<void> release() async {
    final lockFilePath = '${_pathResolver.stagingDirectory}\\provisioning.lock';
    _activeLockPathsInProcess.remove(lockFilePath.toLowerCase());

    final access = _lockFileAccess;
    _lockFileAccess = null;

    if (access != null) {
      try {
        await access.unlock();
      } catch (_) {}
      try {
        await access.close();
      } catch (_) {}
    }

    final file = _lockFile;
    _lockFile = null;

    if (file != null) {
      try {
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    }
  }

  /// Esegue un'azione asincrona protetta da lock esclusivo con rilascio automatico nel blocco [finally].
  Future<T> withLock<T>(Future<T> Function() action) async {
    await acquire();
    try {
      return await action();
    } finally {
      await release();
    }
  }
}
