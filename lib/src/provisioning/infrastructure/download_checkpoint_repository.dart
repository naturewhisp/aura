import 'dart:convert';
import '../domain/download_checkpoint.dart';
import 'provisioning_file_system.dart';
import 'provisioning_lock.dart';
import 'provisioning_path_resolver.dart';

/// Contratto I/O per la persistenza ed il recupero atomico dei checkpoint di download.
abstract class DownloadCheckpointRepository {
  /// Legge il checkpoint memorizzato per una specifica operazione. Restituisce `null` se il checkpoint non esiste o e corrotto.
  Future<DownloadCheckpoint?> readCheckpoint(String operationId);

  /// Salva in modo atomico e sincronizzato il checkpoint [checkpoint].
  Future<void> saveCheckpoint(DownloadCheckpoint checkpoint);

  /// Cancella il checkpoint memorizzato per un'operazione.
  Future<void> deleteCheckpoint(String operationId);
}

/// Implementazione concreta basata su file JSON in `stagingDirectory`.
final class JsonDownloadCheckpointRepository
    implements DownloadCheckpointRepository {
  static const String _lockKeyPrefix = 'download_checkpoint_';

  final ProvisioningPathResolver _pathResolver;
  final ProvisioningFileSystem _fileSystem;
  final ProvisioningLock _lock;

  JsonDownloadCheckpointRepository({
    required ProvisioningPathResolver pathResolver,
    required ProvisioningLock lock,
    ProvisioningFileSystem fileSystem = const LocalProvisioningFileSystem(),
  })  : _pathResolver = pathResolver,
        _fileSystem = fileSystem,
        _lock = lock;

  @override
  Future<DownloadCheckpoint?> readCheckpoint(String operationId) async {
    final lockKey = '$_lockKeyPrefix$operationId';
    return _lock.synchronized(lockKey, () async {
      final path = _pathResolver.stagingCheckpointPath(operationId);
      if (!await _fileSystem.fileExists(path)) {
        return null;
      }
      try {
        final content = await _fileSystem.readAsString(path);
        if (content.trim().isEmpty) return null;
        final jsonMap = jsonDecode(content);
        if (jsonMap is! Map<String, dynamic>) return null;
        return DownloadCheckpoint.fromJson(jsonMap);
      } catch (_) {
        return null;
      }
    });
  }

  @override
  Future<void> saveCheckpoint(DownloadCheckpoint checkpoint) async {
    final lockKey = '$_lockKeyPrefix${checkpoint.operationId}';
    await _lock.synchronized(lockKey, () async {
      final path = _pathResolver.stagingCheckpointPath(checkpoint.operationId);
      final parentDir = _pathResolver.stagingDirectory;
      if (!await _fileSystem.directoryExists(parentDir)) {
        await _fileSystem.createDirectory(parentDir);
      }
      final jsonContent =
          const JsonEncoder.withIndent('  ').convert(checkpoint.toJson());
      await _fileSystem.writeStringRecoverably(path, jsonContent);
    });
  }

  @override
  Future<void> deleteCheckpoint(String operationId) async {
    final lockKey = '$_lockKeyPrefix$operationId';
    await _lock.synchronized(lockKey, () async {
      final path = _pathResolver.stagingCheckpointPath(operationId);
      await _fileSystem.deleteFileBestEffort(path);
    });
  }
}
