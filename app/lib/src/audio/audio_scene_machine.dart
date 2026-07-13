import 'dart:async';
import 'package:flutter/foundation.dart';
import 'audio_scene.dart';
import 'bgm_player.dart';

/// Macchina a stati audio per la gestione delle transizioni e del crossfade delle BGM.
///
/// Implementa una logica basata su un token generazionale globale e una coda serializzata
/// che garantisce la corretta esecuzione asincrona dei comandi nativi, eliminando race condition
/// e cacofonia.
class AudioSceneMachine {
  /// Il backend di riproduzione audio attivo.
  final AudioPlaybackBackend backend;

  /// Mappa che associa ciascuna traccia al rispettivo percorso file WAV su disco.
  final Map<AudioTrackId, String?> trackPaths;

  AudioSceneState? _requestedScene;
  AudioSceneState? _currentScene;
  AudioTrackId? _currentTrack;
  bool _isTrackPlaying = false;
  bool _suspended = false;
  bool _disposed = false;

  // Unico generation token globale per la state machine
  int _generation = 0;

  // Coda asincrona serializzata per tutte le operazioni pubbliche
  Future<void> _queue = Future<void>.value();

  // Traccia del volume fisico corrente per ciascuna traccia per gestire transizioni interrotte.
  final Map<AudioTrackId, double> _currentVolumes = {
    AudioTrackId.main: 0.0,
    AudioTrackId.ambient: 0.0,
    AudioTrackId.tense: 0.0,
    AudioTrackId.epic: 0.0,
  };

  DateTime _trackStartTime = DateTime.now();

  /// Costruisce una macchina a stati [AudioSceneMachine].
  AudioSceneMachine({
    required this.backend,
    required this.trackPaths,
  });

  /// Restituisce la scena audio semanticamente richiesta.
  AudioSceneState? get requestedScene => _requestedScene;

  /// Restituisce la scena audio effettivamente completata.
  AudioSceneState? get currentScene => _currentScene;

  /// Restituisce la traccia fisica correntemente attiva.
  AudioTrackId? get currentTrack => _currentTrack;

  /// Indica se una traccia è fisicamente in riproduzione.
  bool get isTrackPlaying => _isTrackPlaying;

  /// Restituisce il timestamp di avvio della traccia attiva.
  DateTime get trackStartTime => _trackStartTime;

  /// Restituisce i BPM correnti ricavati dal profilo della scena completata.
  double get currentBpm {
    if (!_isTrackPlaying || _currentScene == null) return 0.0;
    return audioSceneProfiles[_currentScene]?.bpm ?? 0.0;
  }

  /// Restituisce il volume fisico memorizzato per una determinata traccia.
  double getVolumeFor(AudioTrackId track) => _currentVolumes[track] ?? 0.0;

  /// Accoda un'operazione asincrona assicurando che gli errori non rompano permanentemente la coda.
  Future<void> _enqueue(Future<void> Function() operation) {
    final result = _queue.then((_) => operation());
    _queue = result.catchError((Object error, StackTrace stackTrace) {
      debugPrint('[AUDIO] Queued operation failed: $error');
    });
    return result;
  }

  /// Richiede una transizione verso una nuova scena musicale.
  Future<void> transitionTo(AudioSceneState nextState, {bool force = false}) async {
    if (_disposed) return;

    if (!force && nextState == _requestedScene) {
      return;
    }

    _requestedScene = nextState;

    if (_suspended) {
      return;
    }

    final generation = ++_generation;
    await _enqueue(() => _executeTransition(nextState, generation));
  }

  Future<void> _executeTransition(AudioSceneState nextState, int generation) async {
    if (_disposed || generation != _generation) return;

    final targetProfile = audioSceneProfiles[nextState]!;
    final targetTrack = targetProfile.track;
    final targetPath = trackPaths[targetTrack];

    final previousScene = _currentScene;
    final previousTrack = _currentTrack;
    final previousProfile = previousScene != null ? audioSceneProfiles[previousScene] : null;

    try {
      if (previousTrack == targetTrack && previousTrack != null) {
        // transizione Same-Track: modula unicamente volume e playbackRate senza interrompere la traccia
        final player = backend.playerFor(targetTrack);
        
        await player.setPlaybackRate(targetProfile.playbackRate);
        if (generation != _generation) return;

        final double startVol = _currentVolumes[targetTrack] ?? previousProfile?.volume ?? 0.0;
        final double endVol = targetProfile.volume;
        final duration = targetProfile.transitionDuration;

        const steps = 8;
        final stepDuration = duration ~/ steps;

        for (int i = 1; i <= steps; i++) {
          if (generation != _generation) return; // Annullamento logico
          final double t = i / steps;
          final double vol = startVol + (endVol - startVol) * t;

          await player.setVolume(vol.clamp(0.0, 1.0).toDouble());
          _currentVolumes[targetTrack] = vol;

          await Future.delayed(stepDuration);
        }

        if (generation != _generation) return;

        await player.setVolume(endVol);
        _currentVolumes[targetTrack] = endVol;

        // Cleanup di tutte le altre tracce non target prima di completare la transizione
        await _silenceAndStopAllExcept(targetTrack, generation);
        if (generation != _generation) return;

        _currentScene = nextState;
        _currentTrack = targetTrack;
        _isTrackPlaying = true;
        return;
      }

      // transizione Crossfade per tracce fisiche differenti.
      _trackStartTime = DateTime.now();

      final BgmPlayer? fromPlayer = previousTrack != null ? backend.playerFor(previousTrack) : null;
      final BgmPlayer toPlayer = backend.playerFor(targetTrack);

      // 1. Silenzia ed arresta tutti gli altri player diversi da target e previous
      for (final trackId in AudioTrackId.values) {
        if (trackId != previousTrack && trackId != targetTrack) {
          final p = backend.playerFor(trackId);
          await p.stop();
          await p.setVolume(0.0);
          _currentVolumes[trackId] = 0.0;
        }
      }

      if (generation != _generation) return;

      // 2. Prepariamo e avviamo il toPlayer a volume 0.0
      if (targetPath != null) {
        await toPlayer.stop();
        await toPlayer.setSource(targetPath);
        await toPlayer.setPlaybackRate(targetProfile.playbackRate);
        await toPlayer.setVolume(0.0);
        _currentVolumes[targetTrack] = 0.0;
        await toPlayer.resume();
      }

      if (generation != _generation) return;

      // Breve pausa per attendere l'avvio nativo del thread
      await Future.delayed(const Duration(milliseconds: 150));
      if (generation != _generation) return;

      // 3. Eseguiamo il crossfade
      const steps = 8;
      final duration = targetProfile.transitionDuration;
      final stepDuration = duration ~/ steps;

      final double startFromVolume = previousTrack != null ? (_currentVolumes[previousTrack] ?? previousProfile?.volume ?? 0.0) : 0.0;
      final double endToVolume = targetProfile.volume;

      for (int i = 1; i <= steps; i++) {
        if (generation != _generation) return; // Annullamento logico
        final double t = i / steps;

        if (fromPlayer != null && previousTrack != null) {
          final double fromVol = startFromVolume * (1.0 - t);
          await fromPlayer.setVolume(fromVol.clamp(0.0, 1.0).toDouble());
          _currentVolumes[previousTrack] = fromVol;
        }

        final double toVol = endToVolume * t;
        await toPlayer.setVolume(toVol.clamp(0.0, 1.0).toDouble());
        _currentVolumes[targetTrack] = toVol;

        await Future.delayed(stepDuration);
      }

      if (generation != _generation) return;

      // 4. Stoppiamo e azzeriamo completamente il fromPlayer uscente
      if (fromPlayer != null && previousTrack != null) {
        await fromPlayer.stop();
        await fromPlayer.setVolume(0.0);
        _currentVolumes[previousTrack] = 0.0;
      }

      await toPlayer.setVolume(endToVolume);
      _currentVolumes[targetTrack] = endToVolume;

      // Cleanup finale di tutte le altre tracce non target prima di committare lo stato
      await _silenceAndStopAllExcept(targetTrack, generation);
      if (generation != _generation) return;

      _currentScene = nextState;
      _currentTrack = targetTrack;
      _isTrackPlaying = true;
    } catch (error) {
      if (generation == _generation) {
        _requestedScene = _currentScene; // Consente il retry
        await _restoreStableState(generation);
      }
      debugPrint('[AUDIO] Transition failed: $error');
    }
  }

  /// Silenzia e spegne tutti i player tranne quello specificato come target.
  Future<void> _silenceAndStopAllExcept(AudioTrackId targetTrack, int generation) async {
    for (final track in AudioTrackId.values) {
      if (track == targetTrack) continue;
      if (generation != _generation) return;

      final player = backend.playerFor(track);
      await player.setVolume(0.0);
      await player.stop();
      _currentVolumes[track] = 0.0;
    }
  }

  /// Ripristina uno stato audio stabile in caso di errore in transizione.
  Future<void> _restoreStableState(int generation) async {
    final stableScene = _currentScene;
    final stableTrack = _currentTrack;

    if (stableScene == null || stableTrack == null) {
      await _bestEffortStopAll(generation);
      _isTrackPlaying = false;
      return;
    }

    try {
      final profile = audioSceneProfiles[stableScene]!;
      final player = backend.playerFor(stableTrack);

      await player.setPlaybackRate(profile.playbackRate);
      await player.setVolume(profile.volume);
      _currentVolumes[stableTrack] = profile.volume;

      await _silenceAndStopAllExcept(stableTrack, generation);
      _isTrackPlaying = true;
    } catch (e) {
      // In caso di errore anche nel recovery, spegniamo tutto e azzeriamo
      await _bestEffortStopAll(generation);
      _currentTrack = null;
      _isTrackPlaying = false;
      debugPrint('[AUDIO] Recovery failed, silencing all: $e');
    }
  }

  /// Disabilita e sospende fisicamente l'audio dei player, incrementando il token.
  Future<void> suspendAudio() async {
    if (_disposed) return;
    _suspended = true;

    final generation = ++_generation;
    await _enqueue(() => _executeSuspend(generation));
  }

  Future<void> _executeSuspend(int generation) async {
    if (_disposed || generation != _generation) return;
    _isTrackPlaying = false;
    _currentTrack = null;

    await _bestEffortStopAll(generation);
  }

  /// Ripristina la riproduzione audio forzando l'avvio dello stato richiesto.
  Future<void> resumeAudio() async {
    if (_disposed) return;
    _suspended = false;

    final generation = ++_generation;
    await _enqueue(() => _executeResume(generation));
  }

  Future<void> _executeResume(int generation) async {
    if (_disposed || generation != _generation || _suspended) return;

    final target = _requestedScene;
    if (target != null) {
      await _executeTransition(target, generation);
    }
  }

  /// Ferma tutti i player fisicamente e resetta lo stato logico completato.
  Future<void> stopBgm() async {
    if (_disposed) return;
    _requestedScene = null;

    final generation = ++_generation;
    await _enqueue(() => _executeStopBgm(generation));
  }

  Future<void> _executeStopBgm(int generation) async {
    if (_disposed || generation != _generation) return;
    _currentScene = null;
    _currentTrack = null;
    _isTrackPlaying = false;

    await _bestEffortStopAll(generation);
  }

  Future<void> _bestEffortStopAll(int generation) async {
    for (final trackId in AudioTrackId.values) {
      if (generation != _generation) return;
      final p = backend.playerFor(trackId);
      try {
        await p.stop();
        await p.setVolume(0.0);
        _currentVolumes[trackId] = 0.0;
      } catch (e) {
        debugPrint("Errore nell'arresto di emergenza della traccia $trackId: $e");
      }
    }
  }

  /// Rilascia le risorse hardware di tutti i player rendendo la macchina terminale.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _suspended = true;
    _requestedScene = null;
    _currentScene = null;
    _currentTrack = null;
    _isTrackPlaying = false;

    final generation = ++_generation;
    await _enqueue(() => _executeDispose(generation));
  }

  Future<void> _executeDispose(int generation) async {
    for (final trackId in AudioTrackId.values) {
      final p = backend.playerFor(trackId);
      try {
        await p.dispose();
      } catch (e) {
        debugPrint("Errore nel rilascio delle risorse della traccia $trackId: $e");
      }
    }
  }
}
