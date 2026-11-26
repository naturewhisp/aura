import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:aura_core/aura_offline.dart';
import 'package:flutter/foundation.dart';

/// Riproduzione dei blocchi di voce, separata per poterla sostituire nei test.
abstract interface class VoicePlaybackBackend {
  /// Riproduce [wav] e completa quando l'audio è finito o è stato fermato.
  Future<void> play(Uint8List wav);

  /// Ferma la riproduzione in corso, se c'è.
  Future<void> stop();

  Future<void> dispose();
}

/// Riproduzione tramite `audioplayers`, con un file WAV temporaneo per blocco.
final class AudioplayersVoiceBackend implements VoicePlaybackBackend {
  AudioplayersVoiceBackend({Directory? tempDir})
      : _dir = tempDir ??
            Directory(
                '${Directory.systemTemp.path}${Platform.pathSeparator}aura_voice');

  final Directory _dir;
  final AudioPlayer _player = AudioPlayer(playerId: 'aura-voice');
  Completer<void>? _playing;
  StreamSubscription<void>? _done;
  int _next = 0;

  @override
  Future<void> play(Uint8List wav) async {
    await stop();
    if (!_dir.existsSync()) _dir.createSync(recursive: true);
    final file =
        File('${_dir.path}${Platform.pathSeparator}voce_${_next++ % 4}.wav');
    await file.writeAsBytes(wav, flush: true);
    final playing = Completer<void>();
    _playing = playing;
    _done = _player.onPlayerComplete.listen((_) {
      if (!playing.isCompleted) playing.complete();
    });
    await _player.play(DeviceFileSource(file.path));
    await playing.future;
    await _done?.cancel();
    _done = null;
  }

  @override
  Future<void> stop() async {
    final playing = _playing;
    _playing = null;
    if (playing != null && !playing.isCompleted) {
      await _player.stop();
      playing.complete();
    }
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _done?.cancel();
    await _player.dispose();
  }
}

/// Stato della voce, per le impostazioni e la diagnostica.
enum VoiceStatus {
  /// I file del motore non sono presenti o il motore non si è avviato.
  unavailable,

  /// Pronta, in silenzio.
  idle,

  /// Sta parlando.
  speaking,
}

/// File del motore vocale cercati accanto all'eseguibile o in una cartella di sviluppo.
@immutable
class VoiceAssetLocation {
  const VoiceAssetLocation(this.directory);

  /// Cartella `speech/` accanto all'eseguibile, oppure `AURA_SPEECH_DIR` se impostata.
  factory VoiceAssetLocation.resolve(
      {Map<String, String>? environment, String? executablePath}) {
    final env = environment ?? Platform.environment;
    final override = env['AURA_SPEECH_DIR'];
    if (override != null && override.trim().isNotEmpty) {
      return VoiceAssetLocation(override.trim());
    }
    final exe = File(executablePath ?? Platform.resolvedExecutable);
    return VoiceAssetLocation(
        '${exe.parent.path}${Platform.pathSeparator}speech');
  }

  final String directory;

  String _join(String name) => '$directory${Platform.pathSeparator}$name';

  KokoroEngineFiles filesFor(VoiceProfile profile) => KokoroEngineFiles(
        modelPath: _join('model.onnx'),
        voicePath: _join('voices${Platform.pathSeparator}${profile.voiceFile}'),
        onnxRuntimeLibraryPath:
            _join(Platform.isWindows ? 'onnxruntime.dll' : 'libonnxruntime.so'),
      );

  /// Vero se tutti i file necessari a [profile] esistono.
  bool isComplete(VoiceProfile profile) {
    final f = filesFor(profile);
    return [f.modelPath, f.voicePath, f.onnxRuntimeLibraryPath]
        .every((p) => File(p).existsSync());
  }
}

/// Fa parlare l'IA: pianifica, sintetizza, applica gli effetti e riproduce le battute.
///
/// Ogni nuova battuta interrompe la precedente. La sintesi del blocco successivo
/// procede mentre il precedente suona. Qualsiasi errore della voce la rende muta
/// senza toccare il resto del gioco.
class VoiceService {
  VoiceService({
    required SpeechEngine engine,
    required VoicePlaybackBackend playback,
    required VoiceProfile profile,
    required bool Function() isAllowed,
    required Future<void> Function(bool ducked) setDucked,
    bool assetsAvailable = true,
    SpeechTextPlanner? planner,
  })  : _engine = engine,
        _playback = playback,
        _profile = profile,
        _isAllowed = isAllowed,
        _setDucked = setDucked,
        _planner = planner ?? SpeechTextPlanner(),
        status = ValueNotifier(
            assetsAvailable ? VoiceStatus.idle : VoiceStatus.unavailable);

  final SpeechEngine _engine;
  final VoicePlaybackBackend _playback;
  final VoiceProfile _profile;
  final bool Function() _isAllowed;
  final Future<void> Function(bool ducked) _setDucked;
  final SpeechTextPlanner _planner;

  /// Stato corrente della voce.
  final ValueNotifier<VoiceStatus> status;

  int _generation = 0;
  bool _ducked = false;
  bool _disposed = false;
  Future<void>? _disposing;

  bool get isAvailable => status.value != VoiceStatus.unavailable;

  /// Pronuncia [displayText], il testo mostrato a schermo della battuta.
  ///
  /// Completa quando la battuta è finita, interrotta o scartata; non lancia mai.
  Future<void> speak(String displayText, {ActorCue? cue}) async {
    final generation = ++_generation;
    await _playback.stop();
    if (_disposed || !isAvailable || !_isAllowed()) return;
    try {
      await _engine.initialize();
    } on SpeechEngineException catch (e) {
      debugPrint('[VOICE] Voce non disponibile (${e.code.name}): ${e.message}');
      status.value = VoiceStatus.unavailable;
      return;
    }
    if (generation != _generation) return;

    final chunks = _planner.plan(displayText);
    if (chunks.isEmpty) return;
    final direction = VoiceDirector.direct(_profile, cue);
    // Non lancia mai: un errore o un'interruzione restituiscono null, così una sintesi
    // anticipata rimasta senza ascoltatori non produce errori asincroni non gestiti.
    Future<Uint8List?> render(int i) async {
      try {
        final audio =
            await _engine.synthesize(chunks[i].phonemes, direction.request);
        if (generation != _generation) return null;
        final shaped = VoiceEffectChain.apply(audio, direction.effects);
        final pauseSamples = i == chunks.length - 1
            ? 0
            : direction.pause.inMicroseconds * shaped.sampleRate ~/ 1000000;
        final padded = Float32List(shaped.samples.length + pauseSamples)
          ..setAll(0, shaped.samples);
        return encodePcm16Wav(
            SpeechAudio(samples: padded, sampleRate: shaped.sampleRate));
      } on SpeechEngineException catch (e) {
        debugPrint('[VOICE] Sintesi interrotta (${e.code.name}): ${e.message}');
        return null;
      } catch (_) {
        debugPrint('[VOICE] Sintesi della voce non riuscita.');
        return null;
      }
    }

    try {
      var next = render(0);
      for (var i = 0; i < chunks.length; i++) {
        final wav = await next;
        if (wav == null || generation != _generation || !_isAllowed()) break;
        if (i + 1 < chunks.length) next = render(i + 1);
        status.value = VoiceStatus.speaking;
        await _duck(true);
        await _playback.play(wav);
        if (generation != _generation) break;
      }
    } catch (_) {
      debugPrint('[VOICE] Riproduzione della voce non riuscita.');
    } finally {
      if (generation == _generation) {
        await _duck(false);
        if (isAvailable) status.value = VoiceStatus.idle;
      }
    }
  }

  /// Interrompe la battuta in corso.
  Future<void> stop() async {
    _generation++;
    await _playback.stop();
    await _duck(false);
    if (isAvailable && !_disposed) status.value = VoiceStatus.idle;
  }

  Future<void> _duck(bool ducked) async {
    if (_ducked == ducked) return;
    _ducked = ducked;
    await _setDucked(ducked);
  }

  /// Rilascia motore e riproduzione. Idempotente e single-flight.
  Future<void> dispose() => _disposing ??= _dispose();

  Future<void> _dispose() async {
    await stop();
    _disposed = true;
    try {
      await _playback.dispose();
    } catch (_) {}
    try {
      await _engine.dispose();
    } catch (_) {}
    status.dispose();
  }
}
