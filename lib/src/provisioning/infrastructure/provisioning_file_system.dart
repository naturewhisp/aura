import 'dart:async';
import 'dart:io';
import 'provisioning_io_exception.dart';

/// Abilitatore astratto di I/O filesystem per isolamento architetturalmente completo e testabilità.
abstract class ProvisioningFileSystem {
  /// Ritorna true se il file esiste al percorso specificato.
  Future<bool> fileExists(String path);

  /// Ritorna true se la directory esiste al percorso specificato.
  Future<bool> directoryExists(String path);

  /// Legge il contenuto testuale di un file.
  Future<String> readAsString(String path);

  /// Legge i byte grezzi di un file.
  Future<List<int>> readAsBytes(String path);

  /// Apre uno stream di lettura a chunk per il file specificato (streaming I/O).
  Stream<List<int>> openRead(String path);

  /// Ritorna la dimensione in byte di un file.
  Future<int> getFileSize(String path);

  /// Ritorna l'elenco dei nomi di elementi figli in una directory.
  Future<List<String>> listDirectory(String path);

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

  /// Elimina rigorosamente una directory e il suo contenuto.
  Future<void> deleteDirectory(String path);

  /// Tenta l'eliminazione ricorsiva di una directory senza lanciare eccezioni.
  Future<bool> deleteDirectoryBestEffort(String path);

  /// Copia un file da sorgente a destinazione.
  Future<void> copyFile(String sourcePath, String targetPath);

  /// Copia ricorsivamente una directory da sorgente a destinazione.
  Future<void> copyDirectory(String sourcePath, String targetPath);

  /// Sposta una directory da sorgente a destinazione con fallback a copia ricorsiva.
  Future<void> moveDirectory(String sourcePath, String targetPath);

  /// Rinomina rigorosamente una directory nello stesso volume SENZA alcun fallback a copia ricorsiva.
  /// Lancia [ProvisioningIoException] se il rename atomico fallisce.
  Future<void> renameDirectoryWithoutFallback(
      String sourcePath, String targetPath);

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
  Stream<List<int>> openRead(String path) {
    try {
      return File(path).openRead();
    } catch (_) {
      throw const ProvisioningIoException(operation: 'openRead');
    }
  }

  @override
  Future<int> getFileSize(String path) async {
    try {
      final file = File(path);
      return await file.length();
    } catch (_) {
      throw const ProvisioningIoException(operation: 'getFileSize');
    }
  }

  @override
  Future<List<String>> listDirectory(String path) async {
    try {
      final dir = Directory(path);
      if (!await dir.exists()) return const [];
      final result = <String>[];
      await for (final entity in dir.list(recursive: false)) {
        final name = entity.path.substring(dir.path.length + 1);
        result.add(name);
      }
      return result;
    } catch (_) {
      throw const ProvisioningIoException(operation: 'listDirectory');
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
  Future<void> deleteDirectory(String path) async {
    try {
      final dir = Directory(path);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {
      throw const ProvisioningIoException(operation: 'deleteDirectory');
    }
  }

  @override
  Future<bool> deleteDirectoryBestEffort(String path) async {
    try {
      final dir = Directory(path);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
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
  Future<void> copyDirectory(String sourcePath, String targetPath) async {
    try {
      final sourceDir = Directory(sourcePath);
      final targetDir = Directory(targetPath);
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }
      await for (final entity in sourceDir.list(recursive: false)) {
        final relativeName = entity.path.substring(sourceDir.path.length + 1);
        final destPath = '${targetDir.path}\\$relativeName';

        if (entity is Directory) {
          await copyDirectory(entity.path, destPath);
        } else if (entity is File) {
          await entity.copy(destPath);
        }
      }
    } catch (_) {
      throw const ProvisioningIoException(operation: 'copyDirectory');
    }
  }

  @override
  Future<void> moveDirectory(String sourcePath, String targetPath) async {
    try {
      final sourceDir = Directory(sourcePath);
      final targetDir = Directory(targetPath);

      await targetDir.parent.create(recursive: true);

      try {
        await sourceDir.rename(targetDir.path);
      } catch (_) {
        await copyDirectory(sourcePath, targetPath);
        await deleteDirectoryBestEffort(sourcePath);
      }
    } catch (_) {
      throw const ProvisioningIoException(operation: 'moveDirectory');
    }
  }

  @override
  Future<void> renameDirectoryWithoutFallback(
      String sourcePath, String targetPath) async {
    try {
      final sourceDir = Directory(sourcePath);
      final targetDir = Directory(targetPath);
      await targetDir.parent.create(recursive: true);
      await sourceDir.rename(targetDir.path);
    } catch (_) {
      throw const ProvisioningIoException(
          operation: 'renameDirectoryWithoutFallback');
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
