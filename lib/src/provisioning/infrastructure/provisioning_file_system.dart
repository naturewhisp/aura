import 'dart:io';
import '../domain/provisioning_options.dart';

/// Abilitatore astratto di I/O filesystem per isolamento architetturale e testabilità.
abstract class ProvisioningFileSystem {
  /// Ritorna true se il file esiste al percorso specificato.
  Future<bool> fileExists(String path);

  /// Ritorna true se la directory esiste al percorso specificato.
  Future<bool> directoryExists(String path);

  /// Legge il contenuto testuale di un file.
  Future<String> readAsString(String path);

  /// Scrive il contenuto in modo atomico (temp file -> backup .bak -> sostituzione finale).
  Future<void> writeStringAtomic(String path, String content);

  /// Elimina il file al percorso specificato.
  Future<void> deleteFile(String path);

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
      throw ProvisioningException(
        reason: ProvisioningFailureReason.installationRecordReadFailed,
        message: 'Impossibile leggere il file al percorso: "$path".',
      );
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
      throw ProvisioningException(
        reason: ProvisioningFailureReason.atomicMoveFailed,
        message: 'Impossibile creare la directory al percorso: "$path".',
      );
    }
  }

  @override
  Future<void> deleteFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  @override
  Future<void> copyFile(String sourcePath, String targetPath) async {
    try {
      final source = File(sourcePath);
      final target = File(targetPath);
      await target.parent.create(recursive: true);
      await source.copy(target.path);
    } catch (_) {
      throw ProvisioningException(
        reason: ProvisioningFailureReason.atomicMoveFailed,
        message: 'Copia del file fallita da "$sourcePath" a "$targetPath".',
      );
    }
  }

  @override
  Future<void> writeStringAtomic(String path, String content) async {
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
        // Se il file di destinazione esiste già, crea/aggiorna il backup .bak
        if (await backupFile.exists()) {
          await backupFile.delete();
        }
        await targetFile.copy(backupFile.path);
        await targetFile.delete();
      }

      await tempFile.rename(targetFile.path);
    } catch (_) {
      if (await tempFile.exists()) {
        try {
          await tempFile.delete();
        } catch (_) {}
      }
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.installationRecordWriteFailed,
        message: 'Scrittura atomica del file sul filesystem fallita.',
      );
    }
  }
}
