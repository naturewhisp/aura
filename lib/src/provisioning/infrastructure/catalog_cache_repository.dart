import 'dart:convert';
import '../domain/catalog_acquisition_models.dart';
import 'provisioning_file_system.dart';
import 'provisioning_lock.dart';
import 'provisioning_path_resolver.dart';

/// Risultato tipizzato della lettura della cache di catalogo locale.
sealed class CatalogCacheReadResult {
  const CatalogCacheReadResult();

  CachedCatalogRecord? get record => switch (this) {
        CatalogCacheLoaded(:final record) => record,
        CatalogCacheRecoveredFromBackup(:final record) => record,
        _ => null,
      };

  CatalogEnvelope? get envelope => record?.envelope;
}

final class CatalogCacheAbsent extends CatalogCacheReadResult {
  const CatalogCacheAbsent();
}

final class CatalogCacheLoaded extends CatalogCacheReadResult {
  @override
  final CachedCatalogRecord record;
  const CatalogCacheLoaded(this.record);
}

final class CatalogCacheRecoveredFromBackup extends CatalogCacheReadResult {
  @override
  final CachedCatalogRecord record;
  const CatalogCacheRecoveredFromBackup(this.record);
}

final class CatalogCacheCorrupted extends CatalogCacheReadResult {
  final String details;
  const CatalogCacheCorrupted(this.details);
}

final class CatalogCacheIoFailure extends CatalogCacheReadResult {
  final Object cause;
  const CatalogCacheIoFailure(this.cause);
}

/// Contratto astratto I/O per la lettura, scrittura e pulizia dell'envelope o record di catalogo in cache.
abstract class CatalogCacheRepository {
  /// Legge il record di cache salvato localmente restituendo un [CatalogCacheReadResult] tipizzato.
  Future<CatalogCacheReadResult> readCache();

  /// Legge l'envelope di catalogo salvata localmente nella cache.
  Future<CatalogEnvelope?> readEnvelope();

  /// Salva in modo atomico il record di cache [record] nella cache locale.
  Future<void> writeRecord(CachedCatalogRecord record);

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
  Future<CatalogCacheReadResult> readCache() async {
    return _lock.synchronized(_lockKey, () async {
      return _internalReadCache();
    });
  }

  @override
  Future<CatalogEnvelope?> readEnvelope() async {
    final result = await readCache();
    return result.envelope;
  }

  @override
  Future<void> writeRecord(CachedCatalogRecord record) async {
    await _lock.synchronized(_lockKey, () async {
      final cacheFilePath = _pathResolver.catalogCacheEnvelopePath;

      final parentDir = _pathResolver.cacheDirectory;
      if (!await _fileSystem.directoryExists(parentDir)) {
        await _fileSystem.createDirectory(parentDir);
      }

      final jsonContent =
          const JsonEncoder.withIndent('  ').convert(record.toJson());

      await _fileSystem.writeStringRecoverably(cacheFilePath, jsonContent);
    });
  }

  @override
  Future<void> writeEnvelope(CatalogEnvelope envelope) async {
    final record = CachedCatalogRecord(
      envelope: envelope,
      fetchedAtUtc: DateTime.now().toUtc(),
    );
    await writeRecord(record);
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

  Future<CatalogCacheReadResult> _internalReadCache() async {
    final cacheFilePath = _pathResolver.catalogCacheEnvelopePath;
    final backupFilePath = '$cacheFilePath.bak';

    if (!await _fileSystem.fileExists(cacheFilePath)) {
      if (await _fileSystem.fileExists(backupFilePath)) {
        return _tryRecoverFromBackup(backupFilePath, cacheFilePath);
      }
      return const CatalogCacheAbsent();
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

      final record = _parseRecordOrEnvelope(jsonMap);
      return CatalogCacheLoaded(record);
    } catch (e) {
      final backupResult =
          await _tryRecoverFromBackup(backupFilePath, cacheFilePath);
      if (backupResult is CatalogCacheRecoveredFromBackup) {
        return backupResult;
      }
      return CatalogCacheCorrupted('File cache primario corrotto: $e');
    }
  }

  Future<CatalogCacheReadResult> _tryRecoverFromBackup(
    String backupFilePath,
    String cacheFilePath,
  ) async {
    if (!await _fileSystem.fileExists(backupFilePath)) {
      return const CatalogCacheAbsent();
    }

    try {
      final content = await _fileSystem.readAsString(backupFilePath);
      if (content.trim().isEmpty) {
        return const CatalogCacheCorrupted('File backup vuoto.');
      }
      final jsonMap = jsonDecode(content);
      if (jsonMap is! Map<String, dynamic>) {
        return const CatalogCacheCorrupted('JSON di backup non valido.');
      }

      final record = _parseRecordOrEnvelope(jsonMap);

      // Ripristino dal backup al file primario preservando il file .bak
      try {
        await _fileSystem.restoreFromBackup(cacheFilePath, backupFilePath);
      } catch (_) {}

      return CatalogCacheRecoveredFromBackup(record);
    } catch (e) {
      return CatalogCacheCorrupted('Ripristino da backup fallito: $e');
    }
  }

  CachedCatalogRecord _parseRecordOrEnvelope(Map<String, dynamic> jsonMap) {
    if (jsonMap.containsKey('envelope')) {
      return CachedCatalogRecord.fromJson(jsonMap);
    } else {
      final envelope = CatalogEnvelope.fromJson(jsonMap);
      return CachedCatalogRecord(
        envelope: envelope,
        fetchedAtUtc: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
    }
  }
}
