import 'dart:io';
import 'provisioning_io_exception.dart';

/// Abilitatore astratto di I/O filesystem per isolamento architetturale e testabilità.
abstract class ProvisioningFileSystem {
  /// Ritorna true se il file esiste al percorso specificato.
  Future<bool> fileExists(String path);

  /// Ritorna true se la directory esiste al percorso specificato.
  Future<bool> directoryExists(String path);

  /// Legge il contenuto testuale di un file.
  Future<String> readAsString(String path);

  /// Legge i byte grezzi di un file.
  Future<List<int>> readAsBytes(String path);

  /// Scrive il contenuto in modo sicuro garantendo il ripristino da backup (temp file -> backup -> sostituzione).
  Future<void> writeStringRecoverably(
    String path,
    String content, {
    bool preserveExistingBackup = false,
  });

  /// Ripristina il file di destinazione dal backup senza distruggere il file di backup stesso e ne verifica l'integrità.
  Future<void> restoreFromBackup(String targetPath, String backupPath);

  /// Elimina rigorosamente un file. Lancia [ProvisioningIoException] in caso di errore I/O.
  Future<void> deleteFile(String path);

  /// Tenta l'eliminazione del file senza lanciare eccezioni. Ritorna true se eliminato.
  Future<bool> deleteFileBestEffort(String path);

  /// Copia un file da sorgente a destinazione.
  Future<void> copyFile(String sourcePath, String targetPath);

  /// Crea una directory e le sue parent.
  Future<void> createDirectory(String path);
}

/// Implementazione concreta basata su file I/O nativi di dart:io.
final class LocalProvisioningFileSystem implements ProvisioningFileSystem {
  const LocalProvisioningFileSystem();

  @override
  Future<bool> fileExists(String path) async {
    return File(path).exists();
  }

  @override
  Future<bool> directoryExists(String path) async {
    return Directory(path).exists();
  }

  @override
  Future<String> readAsString(String path) async {
    try {
      return await File(path).readAsString();
    } catch (_) {
      throw const ProvisioningIoException(operation: 'readAsString');
    }
  }

  @override
  Future<List<int>> readAsBytes(String path) async {
    try {
      return await File(path).readAsBytes();
    } catch (_) {
      throw const ProvisioningIoException(operation: 'readAsBytes');
    }
  }

  @override
  Future<void> createDirectory(String path) async {
    try {
      final dir = Directory(path);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    } catch (_) {
      throw const ProvisioningIoException(operation: 'createDirectory');
    }
  }

  @override
  Future<void> deleteFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      throw const ProvisioningIoException(operation: 'deleteFile');
    }
  }

  @override
  Future<bool> deleteFileBestEffort(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> copyFile(String sourcePath, String targetPath) async {
    try {
      final source = File(sourcePath);
      final target = File(targetPath);
      await target.parent.create(recursive: true);
      await source.copy(target.path);
    } catch (_) {
      throw const ProvisioningIoException(operation: 'copyFile');
    }
  }

  @override
  Future<void> restoreFromBackup(String targetPath, String backupPath) async {
    try {
      final backup = File(backupPath);
      if (!await backup.exists()) {
        throw const ProvisioningIoException(
            operation: 'restoreFromBackup_missing');
      }

      final content = await backup.readAsString();
      if (content.trim().isEmpty) {
        throw const ProvisioningIoException(
            operation: 'restoreFromBackup_empty');
      }

      await writeStringRecoverably(
        targetPath,
        content,
        preserveExistingBackup: true,
      );

      // Verifica di integrità post-ripristino
      final verifiedContent = await File(targetPath).readAsString();
      if (verifiedContent.trim().isEmpty) {
        throw const ProvisioningIoException(
            operation: 'restoreFromBackup_verificationFailed');
      }
    } on ProvisioningIoException {
      rethrow;
    } catch (_) {
      throw const ProvisioningIoException(
          operation: 'restoreFromBackup_failed');
    }
  }

  @override
  Future<void> writeStringRecoverably(
    String path,
    String content, {
    bool preserveExistingBackup = false,
  }) async {
    final targetFile = File(path);
    final parentDir = targetFile.parent;
    if (!await parentDir.exists()) {
      await parentDir.create(recursive: true);
    }

    final tempFilePath = '$path.tmp_${DateTime.now().microsecondsSinceEpoch}';
    final tempFile = File(tempFilePath);
    final backupFilePath = '$path.bak';
    final backupFile = File(backupFilePath);

    try {
      await tempFile.writeAsString(content, flush: true);

      if (await targetFile.exists()) {
        if (!preserveExistingBackup) {
          if (await backupFile.exists()) {
            await backupFile.delete();
          }
          await targetFile.copy(backupFile.path);
        }
        await targetFile.delete();
      }

      await tempFile.rename(targetFile.path);
    } catch (_) {
      if (await tempFile.exists()) {
        try {
          await tempFile.delete();
        } catch (_) {}
      }
      throw const ProvisioningIoException(operation: 'writeStringRecoverably');
    }
  }
}
