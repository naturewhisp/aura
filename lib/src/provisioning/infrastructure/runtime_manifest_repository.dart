import 'dart:convert';
import '../domain/runtime_manifest.dart';
import 'provisioning_file_system.dart';
import 'provisioning_path_resolver.dart';

/// Repository per la lettura ed il caricamento del manifest multi-variante `runtime-manifest.json`.
abstract interface class RuntimeManifestRepository {
  Future<RuntimeManifest?> readManifest({String? customRoot});
}

/// Implementazione predefinita basata su [ProvisioningFileSystem] e [ProvisioningPathResolver].
final class DefaultRuntimeManifestRepository
    implements RuntimeManifestRepository {
  final ProvisioningFileSystem _fileSystem;
  final ProvisioningPathResolver _pathResolver;

  const DefaultRuntimeManifestRepository({
    required ProvisioningFileSystem fileSystem,
    required ProvisioningPathResolver pathResolver,
  })  : _fileSystem = fileSystem,
        _pathResolver = pathResolver;

  @override
  Future<RuntimeManifest?> readManifest({String? customRoot}) async {
    final searchRoots = [
      if (customRoot != null && customRoot.trim().isNotEmpty) customRoot.trim(),
      '${_pathResolver.bundledRoot}\\runtime',
      '${_pathResolver.appManagedRoot}\\runtime',
      _pathResolver.bundledRoot,
      _pathResolver.appManagedRoot,
    ];

    for (final root in searchRoots) {
      final candidatePath = '$root\\runtime-manifest.json';
      if (await _fileSystem.fileExists(candidatePath)) {
        try {
          final content = await _fileSystem.readAsString(candidatePath);
          final decoded = jsonDecode(content);
          if (decoded is Map<String, dynamic>) {
            return RuntimeManifest.fromJson(decoded);
          }
        } catch (_) {}
      }
    }

    return null;
  }
}
