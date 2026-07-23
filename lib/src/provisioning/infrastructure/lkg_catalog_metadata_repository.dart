import 'dart:convert';
import '../domain/catalog_acquisition_models.dart';
import 'provisioning_file_system.dart';
import 'provisioning_lock.dart';
import 'provisioning_path_resolver.dart';

/// Contratto I/O per la lettura, scrittura ed isolamento dei metadata LKG (Last Known Good) per l'anti-downgrade.
abstract class LkgCatalogMetadataRepository {
  /// Legge i metadata LKG attualmente salvati. Restituisce `null` se il file non esiste o è corrotto.
  Future<LkgCatalogMetadata?> readMetadata();

  /// Salva in modo atomico ed isolato i metadata LKG [metadata].
  Future<void> writeMetadata(LkgCatalogMetadata metadata);

  /// Cancella i metadata LKG memorizzati.
  Future<void> clearMetadata();
}

/// Implementazione concreta basata su [ProvisioningFileSystem] con scrittura atomica e sincronizzata.
final class JsonLkgCatalogMetadataRepository
    implements LkgCatalogMetadataRepository {
  static const String _lockKey = 'lkg_catalog_metadata';

  final ProvisioningPathResolver _pathResolver;
  final ProvisioningFileSystem _fileSystem;
  final ProvisioningLock _lock;

  JsonLkgCatalogMetadataRepository({
    required ProvisioningPathResolver pathResolver,
    required ProvisioningLock lock,
    ProvisioningFileSystem fileSystem = const LocalProvisioningFileSystem(),
  })  : _pathResolver = pathResolver,
        _fileSystem = fileSystem,
        _lock = lock;

  @override
  Future<LkgCatalogMetadata?> readMetadata() async {
    return _lock.synchronized(_lockKey, () async {
      final path = _pathResolver.lkgCatalogMetadataPath;
      if (!await _fileSystem.fileExists(path)) {
        return null;
      }
      try {
        final content = await _fileSystem.readAsString(path);
        if (content.trim().isEmpty) {
          return null;
        }
        final jsonMap = jsonDecode(content);
        if (jsonMap is! Map<String, dynamic>) {
          return null;
        }
        return LkgCatalogMetadata.fromJson(jsonMap);
      } catch (_) {
        return null;
      }
    });
  }

  @override
  Future<void> writeMetadata(LkgCatalogMetadata metadata) async {
    await _lock.synchronized(_lockKey, () async {
      final path = _pathResolver.lkgCatalogMetadataPath;
      final parentDir = _pathResolver.cacheDirectory;
      if (!await _fileSystem.directoryExists(parentDir)) {
        await _fileSystem.createDirectory(parentDir);
      }
      final jsonContent =
          const JsonEncoder.withIndent('  ').convert(metadata.toJson());
      await _fileSystem.writeStringRecoverably(path, jsonContent);
    });
  }

  @override
  Future<void> clearMetadata() async {
    await _lock.synchronized(_lockKey, () async {
      final path = _pathResolver.lkgCatalogMetadataPath;
      await _fileSystem.deleteFileBestEffort(path);
    });
  }
}
