import 'dart:convert';
import 'package:meta/meta.dart';
import '../domain/runtime_manifest.dart';
import 'provisioning_file_system.dart';
import 'provisioning_path_resolver.dart';

/// Esito esplicito e tipizzato della ricerca e lettura del manifest multi-variante.
@immutable
sealed class RuntimeManifestReadResult {
  const RuntimeManifestReadResult();
}

/// Manifest trovato e parsato con successo.
@immutable
final class RuntimeManifestFound extends RuntimeManifestReadResult {
  final RuntimeManifest manifest;
  final String manifestPath;

  const RuntimeManifestFound({
    required this.manifest,
    required this.manifestPath,
  });
}

/// File manifest non trovato su disco nei percorsi abilitati.
@immutable
final class RuntimeManifestMissing extends RuntimeManifestReadResult {
  const RuntimeManifestMissing();
}

/// File manifest presente su disco ma corrotto, illeggibile o non conforme agli invarianti.
@immutable
final class RuntimeManifestMalformed extends RuntimeManifestReadResult {
  final String manifestPath;
  final String errorMessage;
  final Object? cause;

  const RuntimeManifestMalformed({
    required this.manifestPath,
    required this.errorMessage,
    this.cause,
  });
}

/// Repository per la lettura ed il caricamento del manifest multi-variante `runtime-manifest.json`.
abstract interface class RuntimeManifestRepository {
  /// Restituisce l'esito esplicito (Found, Missing, Malformed) della ricerca del manifest.
  Future<RuntimeManifestReadResult> readManifestResult({String? customRoot});

  /// Metodo helper backward-compatible che restituisce [RuntimeManifest] se Found, altrimenti `null`.
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
  Future<RuntimeManifestReadResult> readManifestResult(
      {String? customRoot}) async {
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
            final manifest = RuntimeManifest.fromJson(decoded);
            return RuntimeManifestFound(
              manifest: manifest,
              manifestPath: candidatePath,
            );
          } else {
            return RuntimeManifestMalformed(
              manifestPath: candidatePath,
              errorMessage:
                  'JSON radice non è un oggetto Map<String, dynamic>.',
            );
          }
        } catch (e) {
          return RuntimeManifestMalformed(
            manifestPath: candidatePath,
            errorMessage: e.toString(),
            cause: e,
          );
        }
      }
    }

    return const RuntimeManifestMissing();
  }

  @override
  Future<RuntimeManifest?> readManifest({String? customRoot}) async {
    final result = await readManifestResult(customRoot: customRoot);
    if (result is RuntimeManifestFound) {
      return result.manifest;
    }
    return null;
  }
}
