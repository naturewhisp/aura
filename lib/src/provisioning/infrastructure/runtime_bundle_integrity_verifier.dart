import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';
import '../domain/runtime_manifest.dart';
import 'provisioning_file_system.dart';

/// DTO contenente l'esito della verifica d'integrità fisica dei file della variante di runtime.
@immutable
final class RuntimeVariantIntegrityResult {
  final bool isValid;
  final String variantId;
  final String rootPath;
  final List<String> missingFiles;
  final List<String> corruptedFiles;
  final String? errorMessage;

  const RuntimeVariantIntegrityResult({
    required this.isValid,
    required this.variantId,
    required this.rootPath,
    this.missingFiles = const [],
    this.corruptedFiles = const [],
    this.errorMessage,
  });
}

/// Verificatore dell'integrità fisica e crittografica (SHA-256) dei file di una variante di runtime nativo.
abstract interface class RuntimeBundleIntegrityVerifier {
  Future<RuntimeVariantIntegrityResult> verifyVariant({
    required RuntimeVariantDescriptor variant,
    required String runtimeRootPath,
  });
}

/// Implementazione predefinita del verificatore d'integrità della variante di runtime.
final class DefaultRuntimeBundleIntegrityVerifier
    implements RuntimeBundleIntegrityVerifier {
  final ProvisioningFileSystem _fileSystem;

  const DefaultRuntimeBundleIntegrityVerifier({
    required ProvisioningFileSystem fileSystem,
  }) : _fileSystem = fileSystem;

  @override
  Future<RuntimeVariantIntegrityResult> verifyVariant({
    required RuntimeVariantDescriptor variant,
    required String runtimeRootPath,
  }) async {
    final missing = <String>[];
    final corrupted = <String>[];

    for (final entry in variant.files) {
      final absoluteFilePath =
          '$runtimeRootPath\\${entry.path.replaceAll('/', '\\')}';

      if (!await _fileSystem.fileExists(absoluteFilePath)) {
        missing.add(entry.path);
        continue;
      }

      try {
        final bytes = await _fileSystem.readAsBytes(absoluteFilePath);
        if (bytes.length != entry.sizeBytes) {
          corrupted.add(
            '${entry.path} (dimensione errata: ${bytes.length} B vs ${entry.sizeBytes} B)',
          );
          continue;
        }

        final digest = sha256.convert(bytes);
        final calculatedHash = digest.toString().toLowerCase();
        if (calculatedHash != entry.sha256.toLowerCase()) {
          corrupted.add(
            '${entry.path} (hash SHA-256 non corrispondente: $calculatedHash vs ${entry.sha256})',
          );
        }
      } catch (e) {
        corrupted.add('${entry.path} (errore di lettura: $e)');
      }
    }

    final isValid = missing.isEmpty && corrupted.isEmpty;
    String? errorMsg;
    if (!isValid) {
      final parts = <String>[];
      if (missing.isNotEmpty) parts.add('File mancanti: ${missing.join(', ')}');
      if (corrupted.isNotEmpty) {
        parts.add('File corrotti/non corrispondenti: ${corrupted.join(', ')}');
      }
      errorMsg = parts.join(' | ');
    }

    return RuntimeVariantIntegrityResult(
      isValid: isValid,
      variantId: variant.id,
      rootPath: runtimeRootPath,
      missingFiles: List.unmodifiable(missing),
      corruptedFiles: List.unmodifiable(corrupted),
      errorMessage: errorMsg,
    );
  }
}
