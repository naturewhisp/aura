import 'dart:io';
import 'package:archive/archive.dart';
import '../domain/provisioning_options.dart';
import 'provisioning_path_resolver.dart';

/// Contratto astratto per l'estrazione sicura di archivi compressi.
abstract class ArchiveExtractor {
  /// Estrae un archivio ZIP situato in [archiveFilePath] nella directory [targetDirectoryPath].
  /// Ritorna la dimensione totale estratta in byte.
  Future<int> extractZipArchive({
    required String archiveFilePath,
    required String targetDirectoryPath,
  });
}

/// Implementazione concreta basata su `package:archive` con protezione integrata Zip Slip.
final class ZipArchiveExtractor implements ArchiveExtractor {
  const ZipArchiveExtractor();

  @override
  Future<int> extractZipArchive({
    required String archiveFilePath,
    required String targetDirectoryPath,
  }) async {
    final archiveFile = File(archiveFilePath);
    if (!await archiveFile.exists()) {
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.extractionFailed,
        message: 'File di archivio non trovato per l\'estrazione.',
      );
    }

    final targetDir = Directory(targetDirectoryPath);
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    final canonicalTargetDir =
        ProvisioningPathResolver.canonicalizeRoot(targetDirectoryPath);

    List<int> bytes;
    try {
      bytes = await archiveFile.readAsBytes();
    } catch (_) {
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.extractionFailed,
        message: 'Impossibile leggere i byte dell\'archivio ZIP.',
      );
    }

    Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.extractionFailed,
        message: 'Formato archivio ZIP corrotto o non supportato.',
      );
    }

    int totalExtractedBytes = 0;

    for (final entry in archive) {
      final rawName = entry.name.trim();
      if (rawName.isEmpty) continue;

      // Protezione anti-Zip Slip (Path Traversal)
      _validateZipEntryName(rawName, canonicalTargetDir);

      final normalizedEntryPath = rawName.replaceAll('/', r'\');
      final fullTargetPath = '$canonicalTargetDir\\$normalizedEntryPath';
      final canonicalEntryPath = ProvisioningPathResolver.canonicalizeRoot(
        entry.isFile ? File(fullTargetPath).parent.path : fullTargetPath,
      );

      // Verifica che il percorso canonico di destinazione risieda rigorosamente nella target directory
      final canonicalTargetDirWithSep = canonicalTargetDir.endsWith(r'\')
          ? canonicalTargetDir.toLowerCase()
          : '${canonicalTargetDir.toLowerCase()}\\';

      if (!canonicalEntryPath
              .toLowerCase()
              .startsWith(canonicalTargetDirWithSep) &&
          canonicalEntryPath.toLowerCase() !=
              canonicalTargetDir.toLowerCase()) {
        throw ProvisioningException(
          reason: ProvisioningFailureReason.unsafeArchiveEntry,
          message:
              'Voce di archivio non sicura: tenta l\'uscita dalla directory di destinazione ($rawName).',
        );
      }

      if (entry.isFile) {
        try {
          final outFile = File(fullTargetPath);
          await outFile.parent.create(recursive: true);
          final content = entry.content as List<int>;
          await outFile.writeAsBytes(content, flush: true);
          totalExtractedBytes += content.length;
        } catch (_) {
          throw const ProvisioningException(
            reason: ProvisioningFailureReason.extractionFailed,
            message: 'Scrittura del file estratto dall\'archivio fallita.',
          );
        }
      } else {
        await Directory(fullTargetPath).create(recursive: true);
      }
    }

    return totalExtractedBytes;
  }

  void _validateZipEntryName(String name, String targetDir) {
    if (name.contains('\x00')) {
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.unsafeArchiveEntry,
        message: 'Nome voce archivio contiene caratteri null-byte.',
      );
    }

    if (name.contains('..')) {
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.unsafeArchiveEntry,
        message: 'Path traversal ("..") rilevato nella voce di archivio ZIP.',
      );
    }

    if (name.startsWith('/') ||
        name.startsWith(r'\') ||
        RegExp(r'^[a-zA-Z]:').hasMatch(name)) {
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.unsafeArchiveEntry,
        message: 'Percorso assoluto rilevato nella voce di archivio ZIP.',
      );
    }
  }
}
