import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';
import 'audio_manifest.dart';

/// Risultato della validazione binaria di un file WAV rispetto ai metadati del manifest.
@immutable
final class WavValidationResult {
  final bool isValid;
  final String sha256;
  final int sizeBytes;
  final int sampleRate;
  final int channels;
  final int bitsPerSample;
  final int calculatedDurationMs;
  final AudioAssetFailureCode? failureCode;
  final String? failureMessage;

  const WavValidationResult.success({
    required this.sha256,
    required this.sizeBytes,
    required this.sampleRate,
    required this.channels,
    required this.bitsPerSample,
    required this.calculatedDurationMs,
  })  : isValid = true,
        failureCode = null,
        failureMessage = null;

  const WavValidationResult.failure({
    required this.failureCode,
    required this.failureMessage,
    this.sha256 = '',
    this.sizeBytes = 0,
    this.sampleRate = 0,
    this.channels = 0,
    this.bitsPerSample = 0,
    this.calculatedDurationMs = 0,
  }) : isValid = false;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WavValidationResult &&
          runtimeType == other.runtimeType &&
          isValid == other.isValid &&
          sha256 == other.sha256 &&
          sizeBytes == other.sizeBytes &&
          sampleRate == other.sampleRate &&
          channels == other.channels &&
          bitsPerSample == other.bitsPerSample &&
          calculatedDurationMs == other.calculatedDurationMs &&
          failureCode == other.failureCode &&
          failureMessage == other.failureMessage;

  @override
  int get hashCode => Object.hash(
        isValid,
        sha256,
        sizeBytes,
        sampleRate,
        channels,
        bitsPerSample,
        calculatedDurationMs,
        failureCode,
        failureMessage,
      );
}

/// Verificatore di formato binario RIFF/WAVE ed integrità hash SHA-256.
final class WavHeaderVerifier {
  const WavHeaderVerifier();

  /// Calcola l'impronta SHA-256 dei byte forniti.
  String computeSha256(List<int> bytes) {
    return sha256.convert(bytes).toString().toLowerCase();
  }

  /// Valida la conformità binaria ed informatica dei byte di un file WAV rispetto ad un [AudioTrackDescriptor].
  WavValidationResult verify(List<int> bytes, AudioTrackDescriptor descriptor) {
    final computedHash = computeSha256(bytes);

    if (bytes.length != descriptor.sizeBytes) {
      return WavValidationResult.failure(
        failureCode: AudioAssetFailureCode.sizeMismatch,
        failureMessage:
            'Dimensione file non corrispondente. Attesi: ${descriptor.sizeBytes} byte, Rilevati: ${bytes.length} byte.',
        sha256: computedHash,
        sizeBytes: bytes.length,
      );
    }

    if (computedHash != descriptor.sha256.toLowerCase()) {
      return WavValidationResult.failure(
        failureCode: AudioAssetFailureCode.checksumMismatch,
        failureMessage:
            'Hash SHA-256 non corrispondente. Atteso: ${descriptor.sha256}, Rilevato: $computedHash.',
        sha256: computedHash,
        sizeBytes: bytes.length,
      );
    }

    return inspectWavHeader(bytes);
  }

  /// Scansiona l'header RIFF/WAVE e naviga i subchunk per estrarre e verificare il formato PCM.
  WavValidationResult inspectWavHeader(List<int> bytes) {
    if (bytes.length < 12) {
      return const WavValidationResult.failure(
        failureCode: AudioAssetFailureCode.invalidRiffHeader,
        failureMessage:
            'File troppo piccolo per contenere un header RIFF/WAVE valido.',
      );
    }

    final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    final bd = ByteData.sublistView(data);

    // 1. Verifica magic header "RIFF"
    if (data[0] != 0x52 || // R
        data[1] != 0x49 || // I
        data[2] != 0x46 || // F
        data[3] != 0x46) {
      // F
      return const WavValidationResult.failure(
        failureCode: AudioAssetFailureCode.invalidRiffHeader,
        failureMessage: 'Header RIFF non trovato nei primi 4 byte.',
      );
    }

    // 2. Verifica tipo di formato "WAVE"
    if (data[8] != 0x57 || // W
        data[9] != 0x41 || // A
        data[10] != 0x56 || // V
        data[11] != 0x45) {
      // E
      return const WavValidationResult.failure(
        failureCode: AudioAssetFailureCode.invalidRiffHeader,
        failureMessage: 'Tipo di formato WAVE non trovato nei byte 8-11.',
      );
    }

    int offset = 12;
    int? audioFormat;
    int? numChannels;
    int? sampleRate;
    int? bitsPerSample;
    int? dataSizeBytes;

    // 3. Scansione dinamica dei subchunk
    while (offset + 8 <= data.length) {
      final chunkId = String.fromCharCodes(data.sublist(offset, offset + 4));
      final chunkSize = bd.getUint32(offset + 4, Endian.little);
      offset += 8;

      if (offset + chunkSize > data.length) {
        return const WavValidationResult.failure(
          failureCode: AudioAssetFailureCode.invalidRiffHeader,
          failureMessage:
              'Chunk size dichiarato supera i limiti fisici del buffer.',
        );
      }

      if (chunkId == 'fmt ') {
        if (chunkSize < 16) {
          return const WavValidationResult.failure(
            failureCode: AudioAssetFailureCode.invalidRiffHeader,
            failureMessage: 'Chunk "fmt " corrotto o troppo corto.',
          );
        }
        audioFormat = bd.getUint16(offset, Endian.little);
        numChannels = bd.getUint16(offset + 2, Endian.little);
        sampleRate = bd.getUint32(offset + 4, Endian.little);
        bitsPerSample = bd.getUint16(offset + 14, Endian.little);
      } else if (chunkId == 'data') {
        dataSizeBytes = chunkSize;
      }

      // Avanzamento offset con padding byte in caso di dimensione dispari
      final padding = (chunkSize % 2 != 0) ? 1 : 0;
      offset += chunkSize + padding;
    }

    if (audioFormat == null ||
        numChannels == null ||
        sampleRate == null ||
        bitsPerSample == null) {
      return const WavValidationResult.failure(
        failureCode: AudioAssetFailureCode.invalidRiffHeader,
        failureMessage: 'Chunk "fmt " mancante o incomprensibile.',
      );
    }

    if (audioFormat != 1) {
      return WavValidationResult.failure(
        failureCode: AudioAssetFailureCode.unsupportedEncoding,
        failureMessage:
            'Formato audio $audioFormat non supportato (richiesto PCM uncompressed == 1).',
      );
    }

    if (dataSizeBytes == null) {
      return const WavValidationResult.failure(
        failureCode: AudioAssetFailureCode.invalidRiffHeader,
        failureMessage: 'Chunk "data" mancante nel file WAV.',
      );
    }

    final bytesPerSample = (bitsPerSample ~/ 8) * numChannels;
    final calculatedDurationMs = bytesPerSample > 0 && sampleRate > 0
        ? (dataSizeBytes * 1000) ~/ (sampleRate * bytesPerSample)
        : 0;

    return WavValidationResult.success(
      sha256: computeSha256(bytes),
      sizeBytes: bytes.length,
      sampleRate: sampleRate,
      channels: numChannels,
      bitsPerSample: bitsPerSample,
      calculatedDurationMs: calculatedDurationMs,
    );
  }
}
