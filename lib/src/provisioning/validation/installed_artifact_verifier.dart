import 'dart:async';
import '../domain/installation_record.dart';
import '../infrastructure/provisioning_file_system.dart';
import '../infrastructure/provisioning_path_resolver.dart';
import '../infrastructure/sha256_verifier.dart';

/// Contratto per la verifica dell'integrità fisica e crittografica di un artefatto installato.
///
/// Nota Architetturale (InstalledArtifactVerifier v1):
/// - Per payload a file singolo (es. modelli GGUF uncompressed con `entryFileName` non nullo):
///   esegue la verifica crittografica e dimensionale completa (`sizeBytes` e `sha256`).
/// - Per archivi multiline/runtime estratti in directory:
///   esegue la verifica strutturale e di presenza. La gestione del manifest dei file estratti
///   è demandata alle tranche successive di acquisition/download.
abstract interface class InstalledArtifactVerifier {
  /// Verifica che l'artefatto descritto esista fisicamente su disco e ne attesta la dimensione ed il checksum SHA-256.
  Future<bool> verifyPhysicalIntegrity(
    InstalledArtifactDescriptor descriptor, {
    required ProvisioningPathResolver pathResolver,
  });
}

/// Implementazione concreta per la verifica di artefatti locali basata su [ProvisioningFileSystem] e [Sha256Verifier].
final class LocalInstalledArtifactVerifier
    implements InstalledArtifactVerifier {
  final ProvisioningFileSystem _fileSystem;
  final Sha256Verifier _sha256Verifier;

  const LocalInstalledArtifactVerifier({
    ProvisioningFileSystem fileSystem = const LocalProvisioningFileSystem(),
    Sha256Verifier sha256Verifier = const DefaultSha256Verifier(),
  })  : _fileSystem = fileSystem,
        _sha256Verifier = sha256Verifier;

  @override
  Future<bool> verifyPhysicalIntegrity(
    InstalledArtifactDescriptor descriptor, {
    required ProvisioningPathResolver pathResolver,
  }) async {
    final absolutePath = pathResolver
        .resolveAppManagedRelativePath(descriptor.relativeInstallPath);

    final isDirectory = await _fileSystem.directoryExists(absolutePath);
    final isFile = await _fileSystem.fileExists(absolutePath);

    if (!isDirectory && !isFile) {
      return false;
    }

    // Se l'installazione specifica un file di payload principale (es. per modelli GGUF)
    String? targetFilePath;
    if (isDirectory &&
        descriptor.entryFileName != null &&
        descriptor.entryFileName!.trim().isNotEmpty) {
      try {
        targetFilePath = pathResolver.resolveEntryFilePath(
          relativeInstallPath: descriptor.relativeInstallPath,
          entryFileName: descriptor.entryFileName!,
        );
      } catch (_) {
        return false;
      }
    } else if (isFile) {
      targetFilePath = absolutePath;
    }

    if (targetFilePath != null) {
      if (!await _fileSystem.fileExists(targetFilePath)) {
        return false;
      }

      final actualSize = await _fileSystem.getFileSize(targetFilePath);
      if (actualSize != descriptor.sizeBytes) {
        return false;
      }

      if (descriptor.sha256.trim().isNotEmpty) {
        try {
          await _sha256Verifier.verifySha256(
            filePath: targetFilePath,
            expectedSha256: descriptor.sha256,
            fileSystem: _fileSystem,
          );
        } catch (_) {
          return false;
        }
      }
      return true;
    }

    if (isDirectory) {
      // Per una directory di runtime estratta senza entry file dedicato, attesta la presenza di elementi
      final list = await _fileSystem.listDirectory(absolutePath);
      return list.isNotEmpty;
    }

    return false;
  }
}
