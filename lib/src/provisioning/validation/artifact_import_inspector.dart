import 'dart:typed_data';

import '../domain/catalog_manifest.dart';
import '../infrastructure/provisioning_file_system.dart';

/// Risultato dell'ispezione preliminare di idoneità di un file GGUF locale per l'importazione.
final class LocalGgufInspectionResult {
  final String filePath;
  final bool isGgufHeaderValid;
  final int? ggufVersion;
  final int sizeBytes;
  final List<CatalogArtifact> candidateArtifacts;

  const LocalGgufInspectionResult({
    required this.filePath,
    required this.isGgufHeaderValid,
    this.ggufVersion,
    required this.sizeBytes,
    required this.candidateArtifacts,
  });

  bool get isEligibleForImport =>
      isGgufHeaderValid && candidateArtifacts.isNotEmpty;
}

/// Ispeziona l'intestazione fisica di file GGUF locali e seleziona i candidati di catalogo per dimensione.
final class ArtifactImportInspector {
  static const List<int> ggufMagicBytes = <int>[
    0x47,
    0x47,
    0x55,
    0x46
  ]; // 'G', 'G', 'U', 'F'

  final ProvisioningFileSystem _fileSystem;

  const ArtifactImportInspector({
    required ProvisioningFileSystem fileSystem,
  }) : _fileSystem = fileSystem;

  /// Ispeziona i primi byte ed il formato del file locale specificato in [filePath]
  /// e seleziona preliminarmente gli artefatti compatibili dal [manifest] per `sizeBytes`.
  Future<LocalGgufInspectionResult> inspectLocalFile({
    required String filePath,
    required CatalogManifest manifest,
  }) async {
    final cleanPath = filePath.trim();
    if (!await _fileSystem.fileExists(cleanPath)) {
      return LocalGgufInspectionResult(
        filePath: cleanPath,
        isGgufHeaderValid: false,
        sizeBytes: 0,
        candidateArtifacts: const [],
      );
    }

    final fileSize = await _fileSystem.getFileSize(cleanPath);
    if (fileSize < 8) {
      return LocalGgufInspectionResult(
        filePath: cleanPath,
        isGgufHeaderValid: false,
        sizeBytes: fileSize,
        candidateArtifacts: const [],
      );
    }

    // Lettura dei primi 8 byte per magic header e versione uint32 (little-endian)
    final headerBytes = await _readHeaderBytes(cleanPath, 8);
    if (headerBytes.length < 8) {
      return LocalGgufInspectionResult(
        filePath: cleanPath,
        isGgufHeaderValid: false,
        sizeBytes: fileSize,
        candidateArtifacts: const [],
      );
    }

    final isMagicValid = headerBytes[0] == ggufMagicBytes[0] &&
        headerBytes[1] == ggufMagicBytes[1] &&
        headerBytes[2] == ggufMagicBytes[2] &&
        headerBytes[3] == ggufMagicBytes[3];

    int? version;
    if (isMagicValid) {
      final byteData = ByteData.sublistView(Uint8List.fromList(headerBytes));
      version = byteData.getUint32(4, Endian.little);
    }

    // Filtraggio dei candidati di catalogo esclusivamente per sizeBytes (senza SHA-256 anticipato)
    final candidates = manifest.artifacts
        .where((a) =>
            a.sizeBytes == fileSize && a.architecture.toLowerCase() == 'gguf')
        .toList();

    return LocalGgufInspectionResult(
      filePath: cleanPath,
      isGgufHeaderValid: isMagicValid,
      ggufVersion: version,
      sizeBytes: fileSize,
      candidateArtifacts: candidates,
    );
  }

  Future<List<int>> _readHeaderBytes(String filePath, int count) async {
    final stream = _fileSystem.openRead(filePath);
    final bytes = <int>[];
    await for (final chunk in stream) {
      bytes.addAll(chunk);
      if (bytes.length >= count) break;
    }
    return bytes.take(count).toList();
  }
}
