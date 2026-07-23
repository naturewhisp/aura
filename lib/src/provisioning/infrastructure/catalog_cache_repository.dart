import 'dart:convert';
import '../domain/catalog_acquisition_models.dart';
import 'provisioning_file_system.dart';
import 'provisioning_lock.dart';
import 'provisioning_path_resolver.dart';

/// Contratto astratto I/O per la lettura, scrittura e pulizia dell'envelope di catalogo in cache.
abstract class CatalogCacheRepository {
  /// Legge l'envelope di catalogo salvata localmente nella cache.
  /// Restituisce `null` se la cache non esiste, è vuota o è corrotta oltre la capacità di ripristino.
  Future<CatalogEnvelope?> readEnvelope();

  /// Salva in modo atomico l'envelope di catalogo [envelope] nella cache locale.
  Future<void> writeEnvelope(CatalogEnvelope envelope);

  /// Cancella l'envelope di catalogo e l'eventuale backup dalla cache locale.
  Future<void> clearCache();
}

/// Implementazione concreta basata su [ProvisioningFileSystem] con atomic write `.tmp` e backup `.bak`.
final class JsonCatalogCacheRepository implements CatalogCacheRepository {
  static const String _lockKey = 'catalog_cache';

  final ProvisioningPathResolver _pathResolver;
  final ProvisioningFileSystem _fileSystem;
  final ProvisioningLock _lock;

  JsonCatalogCacheRepository({
    required ProvisioningPathResolver pathResolver,
    required ProvisioningLock lock,
    ProvisioningFileSystem fileSystem = const LocalProvisioningFileSystem(),
  })  : _pathResolver = pathResolver,
        _fileSystem = fileSystem,
        _lock = lock;

  @override
  Future<CatalogEnvelope?> readEnvelope() async {
    return _lock.synchronized(_lockKey, () async {
      return _internalReadEnvelope();
    });
  }

  @override
  Future<void> writeEnvelope(CatalogEnvelope envelope) async {
    await _lock.synchronized(_lockKey, () async {
      final cacheFilePath = _pathResolver.catalogCacheEnvelopePath;

      final parentDir = _pathResolver.cacheDirectory;
      if (!await _fileSystem.directoryExists(parentDir)) {
        await _fileSystem.createDirectory(parentDir);
      }

      final jsonContent =
          const JsonEncoder.withIndent('  ').convert(envelope.toJson());

      await _fileSystem.writeStringRecoverably(cacheFilePath, jsonContent);
    });
  }

  @override
  Future<void> clearCache() async {
    await _lock.synchronized(_lockKey, () async {
      final cacheFilePath = _pathResolver.catalogCacheEnvelopePath;
      final backupFilePath = '$cacheFilePath.bak';
      await _fileSystem.deleteFileBestEffort(cacheFilePath);
      await _fileSystem.deleteFileBestEffort(backupFilePath);
    });
  }

  Future<CatalogEnvelope?> _internalReadEnvelope() async {
    final cacheFilePath = _pathResolver.catalogCacheEnvelopePath;
    final backupFilePath = '$cacheFilePath.bak';

    if (!await _fileSystem.fileExists(cacheFilePath)) {
      if (await _fileSystem.fileExists(backupFilePath)) {
        return _tryRecoverFromBackup(backupFilePath, cacheFilePath);
      }
      return null;
    }

    try {
      final content = await _fileSystem.readAsString(cacheFilePath);
      if (content.trim().isEmpty) {
        return _tryRecoverFromBackup(backupFilePath, cacheFilePath);
      }
      final jsonMap = jsonDecode(content);
      if (jsonMap is! Map<String, dynamic>) {
        return _tryRecoverFromBackup(backupFilePath, cacheFilePath);
      }
      return CatalogEnvelope.fromJson(jsonMap);
    } catch (_) {
      return _tryRecoverFromBackup(backupFilePath, cacheFilePath);
    }
  }

  Future<CatalogEnvelope?> _tryRecoverFromBackup(
    String backupFilePath,
    String cacheFilePath,
  ) async {
    if (!await _fileSystem.fileExists(backupFilePath)) {
      return null;
    }

    try {
      final content = await _fileSystem.readAsString(backupFilePath);
      if (content.trim().isEmpty) {
        return null;
      }
      final jsonMap = jsonDecode(content);
      if (jsonMap is! Map<String, dynamic>) {
        return null;
      }
      final envelope = CatalogEnvelope.fromJson(jsonMap);

      // Ripristino dal backup al file primario preservando il file .bak
      try {
        await _fileSystem.restoreFromBackup(cacheFilePath, backupFilePath);
      } catch (_) {}

      return envelope;
    } catch (_) {
      return null;
    }
  }
}
