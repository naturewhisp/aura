import 'package:meta/meta.dart';
import '../domain/runtime_dependency_models.dart';
import '../domain/runtime_manifest.dart';
import 'provisioning_file_system.dart';
import 'provisioning_path_resolver.dart';
import 'runtime_manifest_repository.dart';

/// Eccezione lanciata quando la risoluzione del runtime fallisce per corruzione o assenza di manifest.
@immutable
final class BundledRuntimeResolutionException implements Exception {
  final String message;
  final Object? cause;

  const BundledRuntimeResolutionException(this.message, [this.cause]);

  @override
  String toString() => 'BundledRuntimeResolutionException: $message';
}

/// Contratto per la risoluzione dinamica e portabile di una [LlamaServerConfiguration] in un [ResolvedLlamaRuntime].
abstract interface class BundledRuntimeResolver {
  Future<ResolvedLlamaRuntime?> resolve(
    LlamaServerConfiguration config, {
    String? customRoot,
  });
}

/// Implementazione predefinita basata su [RuntimeManifestRepository], [ProvisioningFileSystem] e [ProvisioningPathResolver].
final class DefaultBundledRuntimeResolver implements BundledRuntimeResolver {
  final RuntimeManifestRepository _manifestRepository;
  final ProvisioningFileSystem _fileSystem;
  final ProvisioningPathResolver _pathResolver;

  const DefaultBundledRuntimeResolver({
    required RuntimeManifestRepository manifestRepository,
    required ProvisioningFileSystem fileSystem,
    required ProvisioningPathResolver pathResolver,
  })  : _manifestRepository = manifestRepository,
        _fileSystem = fileSystem,
        _pathResolver = pathResolver;

  @override
  Future<ResolvedLlamaRuntime?> resolve(
    LlamaServerConfiguration config, {
    String? customRoot,
  }) async {
    if (config.source == RuntimeSource.external) {
      final rawPath = config.externalExecutablePath ?? config.executablePath;
      if (rawPath.trim().isEmpty) return null;

      final cleanPath = rawPath.replaceAll('/', r'\');
      if (!await _fileSystem.fileExists(cleanPath)) return null;

      final lastSlash = cleanPath.lastIndexOf(r'\');
      final workDir = lastSlash > 0 ? cleanPath.substring(0, lastSlash) : '.';

      return ResolvedLlamaRuntime(
        source: RuntimeSource.external,
        runtimeSetId: config.runtimeSetId,
        variantId: config.variantId,
        executablePath: cleanPath,
        workingDirectory: workDir,
        vendorDirectories: const [],
        declaredAcceleration: config.acceleration,
        effectiveAcceleration: config.acceleration,
      );
    }

    // Risoluzione dinamica per RuntimeSource.bundled
    final manifestResult = await _manifestRepository.readManifestResult(
      customRoot: customRoot,
    );

    if (manifestResult is RuntimeManifestMalformed) {
      throw BundledRuntimeResolutionException(
        'Impossibile risolvere il runtime bundled: manifest corrotto in "${manifestResult.manifestPath}".',
        manifestResult.cause,
      );
    }

    if (manifestResult is! RuntimeManifestFound) {
      return null;
    }

    final manifest = manifestResult.manifest;
    final manifestPath = manifestResult.manifestPath;
    final lastSlash = manifestPath.lastIndexOf(r'\');
    final manifestRoot = lastSlash > 0
        ? manifestPath.substring(0, lastSlash)
        : _pathResolver.bundledRoot;

    // Ricerca della variante richiesta o fallback alla prima conforme
    RuntimeVariantDescriptor? variant;
    if (config.variantId != null && config.variantId!.trim().isNotEmpty) {
      final targetId = config.variantId!.trim();
      for (final v in manifest.variants) {
        if (v.id == targetId) {
          variant = v;
          break;
        }
      }
    }

    if (variant == null && manifest.variants.isNotEmpty) {
      // Priorità canonica: cuda -> vulkan -> cpu
      final canonicalPriority = [
        'win-x64-cuda',
        'win-x64-vulkan',
        'win-x64-cpu-avx2'
      ];
      for (final id in canonicalPriority) {
        for (final v in manifest.variants) {
          if (v.id == id) {
            variant = v;
            break;
          }
        }
        if (variant != null) break;
      }
      variant ??= manifest.variants.first;
    }

    if (variant == null) return null;

    final relativeExe = variant.executable.replaceAll('/', r'\');
    final relativeWorkDir = variant.workingDirectory.replaceAll('/', r'\');

    final absExePath = '$manifestRoot\\$relativeExe';
    final absWorkDir = '$manifestRoot\\$relativeWorkDir';
    final absVendors = variant.vendorDirectories
        .map((v) => '$manifestRoot\\${v.replaceAll('/', r'\')}')
        .toList();

    if (!await _fileSystem.fileExists(absExePath)) return null;

    return ResolvedLlamaRuntime(
      source: RuntimeSource.bundled,
      runtimeSetId: manifest.runtimeSetId,
      variantId: variant.id,
      executablePath: absExePath,
      workingDirectory: absWorkDir,
      vendorDirectories: List.unmodifiable(absVendors),
      declaredAcceleration: variant.acceleration,
      effectiveAcceleration: variant.acceleration,
    );
  }
}
