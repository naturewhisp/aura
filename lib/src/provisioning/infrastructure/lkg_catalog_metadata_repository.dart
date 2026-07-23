import 'dart:convert';
import '../domain/catalog_acquisition_models.dart';
import 'provisioning_file_system.dart';
import 'provisioning_lock.dart';
import 'provisioning_path_resolver.dart';

/// Contratto I/O per la lettura, scrittura ed isolamento per-namespace dei metadata LKG (Last Known Good) per l'anti-downgrade.
abstract class LkgCatalogMetadataRepository {
  /// Legge i metadata LKG attualmente salvati per uno specifico [catalogId]. Restituisce `null` se il file o il catalogId non esiste.
  Future<LkgCatalogMetadata?> readMetadata({required String catalogId});

  /// Legge tutti i metadata LKG attualmente salvati indicizzati per `catalogId`.
  Future<Map<String, LkgCatalogMetadata>> readAllMetadata();

  /// Salva in modo atomico ed isolato i metadata LKG [metadata] aggiornando il relativo `catalogId`.
  Future<void> writeMetadata(LkgCatalogMetadata metadata);

  /// Cancella tutti i metadata LKG memorizzati.
  Future<void> clearMetadata();
}

/// Implementazione concreta basata su [ProvisioningFileSystem] con scrittura atomica e sincronizzata per-namespace.
///
/// **Schema Persistence Notice:**
/// Il formato del file `lkg_catalog_metadata.json` utilizza `schema_version: '1.0'`, che rappresenta
/// la baseline del formato persistente per-namespace (mappa `catalogs`). Eventuali future evoluzioni
/// dello schema dovranno implementare la relativa logica di migrazione a partire dalla versione `1.0`.
final class JsonLkgCatalogMetadataRepository
    implements LkgCatalogMetadataRepository {
  static const String _lockKey = 'lkg_catalog_metadata';
  static const String _supportedSchemaVersion = '1.0';

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
  Future<LkgCatalogMetadata?> readMetadata({required String catalogId}) async {
    final all = await readAllMetadata();
    return all[catalogId];
  }

  @override
  Future<Map<String, LkgCatalogMetadata>> readAllMetadata() async {
    return _lock.synchronized(_lockKey, () async {
      final path = _pathResolver.lkgCatalogMetadataPath;
      if (!await _fileSystem.fileExists(path)) {
        return const <String, LkgCatalogMetadata>{};
      }
      try {
        final content = await _fileSystem.readAsString(path);
        if (content.trim().isEmpty) {
          return const <String, LkgCatalogMetadata>{};
        }
        final jsonMap = jsonDecode(content);
        if (jsonMap is! Map<String, dynamic>) {
          return const <String, LkgCatalogMetadata>{};
        }

        final result = <String, LkgCatalogMetadata>{};

        // Formato canonico per-namespace (schema_version: 1.0)
        if (jsonMap.containsKey('catalogs') && jsonMap['catalogs'] is Map) {
          final catalogsMap = jsonMap['catalogs'] as Map<String, dynamic>;
          for (final entry in catalogsMap.entries) {
            if (entry.value is Map<String, dynamic>) {
              try {
                final item = LkgCatalogMetadata.fromJson(
                    entry.value as Map<String, dynamic>);
                result[item.catalogId] = item;
              } catch (_) {}
            }
          }
          return Map<String, LkgCatalogMetadata>.unmodifiable(result);
        }

        return const <String, LkgCatalogMetadata>{};
      } catch (_) {
        return const <String, LkgCatalogMetadata>{};
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

      // Legge lo stato corrente e aggiorna/inserisce l'elemento per catalogId
      final currentMap = <String, LkgCatalogMetadata>{};

      if (await _fileSystem.fileExists(path)) {
        try {
          final content = await _fileSystem.readAsString(path);
          if (content.trim().isNotEmpty) {
            final decoded = jsonDecode(content);
            if (decoded is Map<String, dynamic> &&
                decoded.containsKey('catalogs') &&
                decoded['catalogs'] is Map) {
              final catMap = decoded['catalogs'] as Map<String, dynamic>;
              for (final entry in catMap.entries) {
                if (entry.value is Map<String, dynamic>) {
                  try {
                    final item = LkgCatalogMetadata.fromJson(
                        entry.value as Map<String, dynamic>);
                    currentMap[item.catalogId] = item;
                  } catch (_) {}
                }
              }
            }
          }
        } catch (_) {}
      }

      currentMap[metadata.catalogId] = metadata;

      final serializedMap = <String, dynamic>{
        'schema_version': _supportedSchemaVersion,
        'catalogs': currentMap.map((key, val) => MapEntry(key, val.toJson())),
      };

      final jsonContent =
          const JsonEncoder.withIndent('  ').convert(serializedMap);
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
