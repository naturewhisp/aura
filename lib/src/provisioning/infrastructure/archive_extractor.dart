import 'dart:io';
import 'package:archive/archive.dart';
import '../domain/provisioning_cancellation_token.dart';
import '../domain/provisioning_options.dart';
import 'provisioning_path_resolver.dart';

/// Contratto astratto per l'estrazione sicura di archivi compressi.
abstract class ArchiveExtractor {
  /// Estrae un archivio ZIP situato in [archiveFilePath] nella directory [targetDirectoryPath].
  /// Ritorna la dimensione totale estratta in byte.
  Future<int> extractZipArchive({
    required String archiveFilePath,
    required String targetDirectoryPath,
    required int maxExpectedBytes,
    ProvisioningCancellationToken? cancellationToken,
  });
}

/// Implementazione concreta basata su `package:archive` con protezione integrata Zip Slip e Zip Bomb limit.
final class ZipArchiveExtractor implements ArchiveExtractor {
  static const int maxArchiveEntries = 10000;
  static const int maxSingleFileBytes = 5 * 1024 * 1024 * 1024; // 5 GB
  static const double maxCompressionRatio = 100.0;

  static final RegExp _invalidCharsRegex = RegExp(r'[<>:"|?*\x00-\x1F]');
  static final RegExp _reservedWindowsNamesRegex = RegExp(
    r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\..*)?$',
    caseSensitive: false,
  );

  const ZipArchiveExtractor();

  @override
  Future<int> extractZipArchive({
    required String archiveFilePath,
    required String targetDirectoryPath,
    required int maxExpectedBytes,
    ProvisioningCancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();

    final archiveFile = File(archiveFilePath);
    if (!await archiveFile.exists()) {
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.extractionFailed,
        message: 'File di archivio non trovato per l\'estrazione.',
      );
    }

    final archiveSizeBytes = await archiveFile.length();
    final allowedMaxTotalBytes = maxExpectedBytes * 10 > 10 * 1024 * 1024 * 1024
        ? 10 * 1024 * 1024 * 1024
        : (maxExpectedBytes * 10 < 100 * 1024 * 1024
            ? 500 * 1024 * 1024
            : maxExpectedBytes * 10);

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

    if (archive.numberOfFiles() > maxArchiveEntries) {
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.sizeLimitExceeded,
        message:
            'Numero massimo di file presenti nell\'archivio ZIP superato (Zip Bomb protection).',
      );
    }

    int totalExtractedBytes = 0;

    for (final entry in archive) {
      cancellationToken?.throwIfCancelled();

      final rawName = entry.name.trim();
      if (rawName.isEmpty) continue;

      // Protezione anti-Zip Slip basata su segmenti esatti
      _validateZipEntrySegments(rawName);

      final normalizedEntryPath = rawName.replaceAll('/', r'\');
      final fullTargetPath = '$canonicalTargetDir\\$normalizedEntryPath';
      final canonicalEntryPath = ProvisioningPathResolver.canonicalizeRoot(
        entry.isFile ? File(fullTargetPath).parent.path : fullTargetPath,
      );

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
        final content = entry.content as List<int>;
        final fileLength = content.length;

        if (fileLength > maxSingleFileBytes) {
          throw const ProvisioningException(
            reason: ProvisioningFailureReason.sizeLimitExceeded,
            message: 'Singolo file estratto supera il limite massimo di 5 GB.',
          );
        }

        totalExtractedBytes += fileLength;

        if (totalExtractedBytes > allowedMaxTotalBytes) {
          throw const ProvisioningException(
            reason: ProvisioningFailureReason.sizeLimitExceeded,
            message:
                'Dimensione totale estratta supera il limite consentito (Zip Bomb protection).',
          );
        }

        if (archiveSizeBytes > 0 &&
            (totalExtractedBytes / archiveSizeBytes) > maxCompressionRatio) {
          throw const ProvisioningException(
            reason: ProvisioningFailureReason.sizeLimitExceeded,
            message:
                'Rapporto di compressione anomalo rilevato (Decompression Bomb protection).',
          );
        }

        try {
          final outFile = File(fullTargetPath);
          await outFile.parent.create(recursive: true);
          await outFile.writeAsBytes(content, flush: true);
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

  void _validateZipEntrySegments(String name) {
    if (name.contains('\x00')) {
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.unsafeArchiveEntry,
        message: 'Nome voce archivio contiene caratteri null-byte.',
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

    final segments = name.replaceAll('/', r'\').split(r'\');
    for (final segment in segments) {
      final s = segment.trim();
      if (s == '..') {
        throw const ProvisioningException(
          reason: ProvisioningFailureReason.unsafeArchiveEntry,
          message:
              'Segmento di path traversal ("..") rilevato nella voce di archivio ZIP.',
        );
      }
      if (s.isEmpty || s == '.') continue;

      if (_invalidCharsRegex.hasMatch(s)) {
        throw ProvisioningException(
          reason: ProvisioningFailureReason.unsafeArchiveEntry,
          message:
              'Segmento di archivio contiene caratteri non validi Windows: "$s".',
        );
      }

      if (s.startsWith('.') ||
          s.endsWith('.') ||
          s.startsWith(' ') ||
          s.endsWith(' ')) {
        throw ProvisioningException(
          reason: ProvisioningFailureReason.unsafeArchiveEntry,
          message: 'Segmento di archivio con spazi o punti ai margini: "$s".',
        );
      }

      if (_reservedWindowsNamesRegex.hasMatch(s)) {
        throw ProvisioningException(
          reason: ProvisioningFailureReason.unsafeArchiveEntry,
          message: 'Segmento di archivio usa un nome riservato Windows: "$s".',
        );
      }
    }
  }
}
