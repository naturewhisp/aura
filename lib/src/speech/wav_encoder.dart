import 'dart:typed_data';

import 'speech_engine.dart';

/// Codifica un [SpeechAudio] come file WAV PCM a 16 bit, mono.
Uint8List encodePcm16Wav(SpeechAudio audio) {
  final n = audio.samples.length;
  final data = ByteData(44 + n * 2);
  void ascii(int offset, String s) {
    for (var i = 0; i < 4; i++) {
      data.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  data.setUint32(4, 36 + n * 2, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, audio.sampleRate, Endian.little);
  data.setUint32(28, audio.sampleRate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  data.setUint32(40, n * 2, Endian.little);
  for (var i = 0; i < n; i++) {
    final s = audio.samples[i];
    final v = s.isNaN ? 0.0 : s.clamp(-1.0, 1.0).toDouble();
    data.setInt16(44 + i * 2, (v * 32767).round(), Endian.little);
  }
  return data.buffer.asUint8List();
}
