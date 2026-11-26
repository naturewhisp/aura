import 'dart:math' as math;
import 'dart:typed_data';

import 'speech_engine.dart';
import 'voice_profile.dart';

/// Catena di effetti per la voce: passa-alto, passa-basso, compressore, eco, guadagno.
///
/// Riproduce in Dart la catena approvata all'ascolto nello spike (ffmpeg
/// `highpass`, `lowpass`, `acompressor`, `aecho`, `volume`), senza dipendenze
/// native. L'uscita viene limitata a [-1, 1].
abstract final class VoiceEffectChain {
  /// Applica [settings] ad [audio] e restituisce un nuovo audio.
  static SpeechAudio apply(SpeechAudio audio, VoiceEffectSettings settings) {
    if (audio.isEmpty) return audio;
    final sr = audio.sampleRate.toDouble();
    var x = Float64List.fromList(audio.samples);
    if (settings.highpassHz > 0 && settings.highpassHz < sr / 2) {
      _Biquad.highpass(settings.highpassHz, sr).process(x);
    }
    if (settings.lowpassHz > 0 && settings.lowpassHz < sr / 2) {
      _Biquad.lowpass(settings.lowpassHz, sr).process(x);
    }
    if (settings.compressorRatio > 1 && settings.compressorThresholdDb < 0) {
      _compress(
          x, sr, settings.compressorThresholdDb, settings.compressorRatio);
    }
    if (settings.echoDelaysMs.isNotEmpty) {
      x = _echo(x, sr, settings);
    }
    final out = Float32List(x.length);
    for (var i = 0; i < x.length; i++) {
      final v = x[i] * settings.outputGain;
      out[i] = v.isFinite ? v.clamp(-1.0, 1.0).toDouble() : 0;
    }
    return SpeechAudio(samples: out, sampleRate: audio.sampleRate);
  }

  /// Compressore feed-forward con rilevazione RMS e ginocchio morbido
  /// (attacco 20 ms, rilascio 250 ms, come i valori predefiniti di ffmpeg).
  static void _compress(
      Float64List x, double sr, double thresholdDb, double ratio) {
    final attack = math.exp(-1 / (0.020 * sr));
    final release = math.exp(-1 / (0.250 * sr));
    const kneeDb = 9.0;
    var env = 0.0;
    for (var i = 0; i < x.length; i++) {
      final p = x[i] * x[i];
      env = p > env
          ? attack * env + (1 - attack) * p
          : release * env + (1 - release) * p;
      final levelDb = 10 * math.log(env + 1e-12) / math.ln10;
      final over = levelDb - thresholdDb;
      double reductionDb;
      if (over <= -kneeDb / 2) {
        reductionDb = 0;
      } else if (over >= kneeDb / 2) {
        reductionDb = over * (1 - 1 / ratio);
      } else {
        final t = over + kneeDb / 2;
        reductionDb = (1 - 1 / ratio) * t * t / (2 * kneeDb);
      }
      x[i] *= math.pow(10, -reductionDb / 20);
    }
  }

  static Float64List _echo(Float64List x, double sr, VoiceEffectSettings s) {
    final delays = [for (final d in s.echoDelaysMs) (d * sr / 1000).round()];
    final tail = delays.fold<int>(0, math.max);
    final out = Float64List(x.length + tail);
    for (var i = 0; i < out.length; i++) {
      var v = i < x.length ? x[i] * s.echoInputGain : 0.0;
      for (var k = 0; k < delays.length; k++) {
        final j = i - delays[k];
        if (j >= 0 && j < x.length) v += x[j] * s.echoDecays[k];
      }
      out[i] = v * s.echoOutputGain;
    }
    return out;
  }
}

/// Filtro biquadratico (formule di R. Bristow-Johnson), Butterworth del secondo ordine.
final class _Biquad {
  _Biquad(this.b0, this.b1, this.b2, this.a1, this.a2);

  factory _Biquad.lowpass(double f, double sr) {
    final w = 2 * math.pi * f / sr,
        c = math.cos(w),
        alpha = math.sin(w) / (2 * math.sqrt1_2);
    final a0 = 1 + alpha;
    return _Biquad((1 - c) / 2 / a0, (1 - c) / a0, (1 - c) / 2 / a0,
        -2 * c / a0, (1 - alpha) / a0);
  }

  factory _Biquad.highpass(double f, double sr) {
    final w = 2 * math.pi * f / sr,
        c = math.cos(w),
        alpha = math.sin(w) / (2 * math.sqrt1_2);
    final a0 = 1 + alpha;
    return _Biquad((1 + c) / 2 / a0, -(1 + c) / a0, (1 + c) / 2 / a0,
        -2 * c / a0, (1 - alpha) / a0);
  }

  final double b0, b1, b2, a1, a2;

  void process(Float64List x) {
    var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0;
    for (var i = 0; i < x.length; i++) {
      final x0 = x[i];
      final y0 = b0 * x0 + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
      x2 = x1;
      x1 = x0;
      y2 = y1;
      y1 = y0;
      x[i] = y0;
    }
  }
}
