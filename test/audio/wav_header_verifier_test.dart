import 'dart:typed_data';
import 'package:aura_core/aura_core.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

List<int> buildTestWavBuffer({
  required int sampleRate,
  required int channels,
  required int bitsPerSample,
  required int numSamples,
  int audioFormat = 1,
  bool includePaddingByte = false,
}) {
  final builder = BytesBuilder();

  final bytesPerSample = (bitsPerSample ~/ 8) * channels;
  var subChunk2Size = numSamples * bytesPerSample;

  builder.add('RIFF'.codeUnits);
  final chunkSize = 36 + subChunk2Size + (includePaddingByte ? 1 : 0);
  builder.add([
    chunkSize & 0xFF,
    (chunkSize >> 8) & 0xFF,
    (chunkSize >> 16) & 0xFF,
    (chunkSize >> 24) & 0xFF,
  ]);
  builder.add('WAVE'.codeUnits);

  // Subchunk fmt
  builder.add('fmt '.codeUnits);
  builder.add([16, 0, 0, 0]); // size 16
  builder.add([audioFormat & 0xFF, (audioFormat >> 8) & 0xFF]);
  builder.add([channels & 0xFF, (channels >> 8) & 0xFF]);
  builder.add([
    sampleRate & 0xFF,
    (sampleRate >> 8) & 0xFF,
    (sampleRate >> 16) & 0xFF,
    (sampleRate >> 24) & 0xFF,
  ]);
  final byteRate = sampleRate * bytesPerSample;
  builder.add([
    byteRate & 0xFF,
    (byteRate >> 8) & 0xFF,
    (byteRate >> 16) & 0xFF,
    (byteRate >> 24) & 0xFF,
  ]);
  final blockAlign = bytesPerSample;
  builder.add([blockAlign & 0xFF, (blockAlign >> 8) & 0xFF]);
  builder.add([bitsPerSample & 0xFF, (bitsPerSample >> 8) & 0xFF]);

  // Subchunk data
  builder.add('data'.codeUnits);
  builder.add([
    subChunk2Size & 0xFF,
    (subChunk2Size >> 8) & 0xFF,
    (subChunk2Size >> 16) & 0xFF,
    (subChunk2Size >> 24) & 0xFF,
  ]);

  for (var i = 0; i < numSamples; i++) {
    for (var ch = 0; ch < channels; ch++) {
      builder.add([0x00, 0x00]);
    }
  }

  if (includePaddingByte) {
    builder.add([0x00]);
  }

  return builder.toBytes();
}

void main() {
  group('WavHeaderVerifier Unit Tests', () {
    const verifier = WavHeaderVerifier();

    test('valida con successo un buffer RIFF/WAVE conforme', () {
      final bytes = buildTestWavBuffer(
        sampleRate: 44100,
        channels: 2,
        bitsPerSample: 16,
        numSamples: 44100, // 1 secondo
      );

      final result = verifier.inspectWavHeader(bytes);

      expect(result.isValid, isTrue);
      expect(result.sampleRate, equals(44100));
      expect(result.channels, equals(2));
      expect(result.bitsPerSample, equals(16));
      expect(result.calculatedDurationMs, equals(1000));
    });

    test('rifiuta file con header RIFF non valido', () {
      final badBytes = [0x46, 0x41, 0x4B, 0x45, 0, 0, 0, 0, 0, 0, 0, 0];
      final result = verifier.inspectWavHeader(badBytes);

      expect(result.isValid, isFalse);
      expect(
          result.failureCode, equals(AudioAssetFailureCode.invalidRiffHeader));
    });

    test('rifiuta codifica non PCM (audioFormat != 1)', () {
      final bytes = buildTestWavBuffer(
        sampleRate: 22050,
        channels: 1,
        bitsPerSample: 16,
        numSamples: 100,
        audioFormat: 3, // IEEE float (non PCM lineare 1)
      );

      final result = verifier.inspectWavHeader(bytes);

      expect(result.isValid, isFalse);
      expect(result.failureCode,
          equals(AudioAssetFailureCode.unsupportedEncoding));
    });

    test('rifiuta file con checksum SHA-256 o dimensione non corrispondente',
        () {
      final bytes = buildTestWavBuffer(
        sampleRate: 22050,
        channels: 1,
        bitsPerSample: 16,
        numSamples: 2205, // 100ms
      );

      final realHash = sha256.convert(bytes).toString().toLowerCase();

      final descriptor = AudioTrackDescriptor(
        id: 'sfx.test',
        kind: AudioTrackKind.sfx,
        role: AudioTrackRole.click,
        filename: 'sfx_test.wav',
        sizeBytes: bytes.length,
        sha256:
            '0000000000000000000000000000000000000000000000000000000000000000',
        codec: 'pcm',
        sampleRate: 22050,
        channels: 1,
        bitsPerSample: 16,
        durationMs: 100,
        loop: false,
        required: true,
      );

      final result = verifier.verify(bytes, descriptor);

      expect(result.isValid, isFalse);
      expect(
          result.failureCode, equals(AudioAssetFailureCode.checksumMismatch));

      final validDescriptor = AudioTrackDescriptor(
        id: 'sfx.test',
        kind: AudioTrackKind.sfx,
        role: AudioTrackRole.click,
        filename: 'sfx_test.wav',
        sizeBytes: bytes.length,
        sha256: realHash,
        codec: 'pcm',
        sampleRate: 22050,
        channels: 1,
        bitsPerSample: 16,
        durationMs: 100,
        loop: false,
        required: true,
      );

      final validResult = verifier.verify(bytes, validDescriptor);
      expect(validResult.isValid, isTrue);
    });
  });
}
