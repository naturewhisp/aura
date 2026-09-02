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

  @visibleForTesting
  set isTrackPlayingForTesting(bool value) => _isTrackPlaying = value;

  @visibleForTesting
  set currentTrackForTesting(AudioTrackId? value) => _currentTrack = value;

  /// Accoda un'operazione asincrona assicurando che gli errori non rompano permanentemente la coda.
  Future<void> _enqueue(Future<void> Function() operation) {
    final result = _queue.then((_) => operation());
    _queue = result.catchError((Object error, StackTrace stackTrace) {
      debugPrint('[AUDIO] Queued operation failed: $error');
    });
    return result;
  }

  /// Richiede una transizione verso una nuova scena musicale.
  Future<void> transitionTo(AudioSceneState nextState,
      {bool force = false}) async {
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

  Future<void> _executeTransition(
      AudioSceneState nextState, int generation) async {
    if (_disposed || generation != _generation) return;

    final targetProfile = audioSceneProfiles[nextState]!;
    final targetTrack = targetProfile.track;
    final targetPath = trackPaths[targetTrack];

    final previousScene = _currentScene;
    final previousTrack = _currentTrack;
    final previousTrackStartTime = _trackStartTime;
    final previousWasPlaying = _isTrackPlaying;
    bool previousTrackWasStopped = false;

    final previousProfile =
        previousScene != null ? audioSceneProfiles[previousScene] : null;

    try {
      if (previousTrack == targetTrack && previousTrack != null) {
        // transizione Same-Track: modula unicamente volume e playbackRate senza interrompere la traccia
        final player = backend.playerFor(targetTrack);

        await player.setPlaybackRate(targetProfile.playbackRate);
        if (await _abortIfObsolete(
          generation: generation,
          previousScene: previousScene,
          previousTrack: previousTrack,
          previousTrackStartTime: previousTrackStartTime,
          previousWasPlaying: previousWasPlaying,
          previousTrackWasStopped: previousTrackWasStopped,
        )) {
          return;
        }

        final double startVol = _currentVolumes[targetTrack] ??
            (_applyDucking(previousProfile?.volume ?? 0.0));
        final double endVol = _applyDucking(targetProfile.volume);
        final duration = targetProfile.transitionDuration;

        final wasAlreadyPlaying =
            _isTrackPlaying && _currentTrack == targetTrack;
        DateTime? candidateTrackStartTime;

        if (!wasAlreadyPlaying) {
          await player.resume();
          if (await _abortIfObsolete(
            generation: generation,
            previousScene: previousScene,
            previousTrack: previousTrack,
            previousTrackStartTime: previousTrackStartTime,
            previousWasPlaying: previousWasPlaying,
            previousTrackWasStopped: previousTrackWasStopped,
          )) {
            return;
          }
          candidateTrackStartTime = DateTime.now();
        }

        const steps = 8;
        final stepDuration = duration ~/ steps;

        for (int i = 1; i <= steps; i++) {
          final double t = i / steps;
          final double vol = startVol + (endVol - startVol) * t;

          await player.setVolume(vol.clamp(0.0, 1.0).toDouble());
          _currentVolumes[targetTrack] = vol;

          if (await _abortIfObsolete(
            generation: generation,
            previousScene: previousScene,
            previousTrack: previousTrack,
            previousTrackStartTime: previousTrackStartTime,
            previousWasPlaying: previousWasPlaying,
            previousTrackWasStopped: previousTrackWasStopped,
          )) {
            return;
          }

          await Future.delayed(stepDuration);

          if (await _abortIfObsolete(
            generation: generation,
            previousScene: previousScene,
            previousTrack: previousTrack,
            previousTrackStartTime: previousTrackStartTime,
            previousWasPlaying: previousWasPlaying,
            previousTrackWasStopped: previousTrackWasStopped,
          )) {
            return;
          }
        }

        if (await _abortIfObsolete(
          generation: generation,
          previousScene: previousScene,
          previousTrack: previousTrack,
          previousTrackStartTime: previousTrackStartTime,
          previousWasPlaying: previousWasPlaying,
          previousTrackWasStopped: previousTrackWasStopped,
        )) {
          return;
        }

        await _finalizeTransition(
          targetScene: nextState,
          targetTrack: targetTrack,
          targetVolume: endVol,
          candidateStartTime: candidateTrackStartTime,
          previousTrack: previousTrack,
          onPreviousTrackStopped: () {
            previousTrackWasStopped = true;
          },
        );
        return;
      }

      // transizione Crossfade per tracce fisiche differenti.
      final BgmPlayer? fromPlayer =
          previousTrack != null ? backend.playerFor(previousTrack) : null;
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

      if (await _abortIfObsolete(
        generation: generation,
        previousScene: previousScene,
        previousTrack: previousTrack,
        previousTrackStartTime: previousTrackStartTime,
        previousWasPlaying: previousWasPlaying,
        previousTrackWasStopped: previousTrackWasStopped,
      )) {
        return;
      }

      // 2. Prepariamo e avviamo il toPlayer a volume 0.0
      DateTime? candidateTrackStartTime;
      if (targetPath != null) {
        await toPlayer.stop();
        await toPlayer.setSource(targetPath);
        await toPlayer.setPlaybackRate(targetProfile.playbackRate);
        await toPlayer.setVolume(0.0);
        _currentVolumes[targetTrack] = 0.0;
        await toPlayer.resume();
        if (await _abortIfObsolete(
          generation: generation,
          previousScene: previousScene,
          previousTrack: previousTrack,
          previousTrackStartTime: previousTrackStartTime,
          previousWasPlaying: previousWasPlaying,
          previousTrackWasStopped: previousTrackWasStopped,
        )) {
          return;
        }
        candidateTrackStartTime = DateTime.now();
      }

      if (await _abortIfObsolete(
        generation: generation,
        previousScene: previousScene,
        previousTrack: previousTrack,
        previousTrackStartTime: previousTrackStartTime,
        previousWasPlaying: previousWasPlaying,
        previousTrackWasStopped: previousTrackWasStopped,
      )) {
        return;
      }

      // Breve pausa per attendere l'avvio nativo del thread
      await Future.delayed(const Duration(milliseconds: 150));
      if (await _abortIfObsolete(
        generation: generation,
        previousScene: previousScene,
        previousTrack: previousTrack,
        previousTrackStartTime: previousTrackStartTime,
        previousWasPlaying: previousWasPlaying,
        previousTrackWasStopped: previousTrackWasStopped,
      )) {
        return;
      }

      // 3. Eseguiamo il crossfade
      const steps = 8;
      final duration = targetProfile.transitionDuration;
      final stepDuration = duration ~/ steps;

      final double startFromVolume = previousTrack != null
          ? (_currentVolumes[previousTrack] ??
              (_applyDucking(previousProfile?.volume ?? 0.0)))
          : 0.0;
      final double endToVolume = _applyDucking(targetProfile.volume);

      for (int i = 1; i <= steps; i++) {
        final double t = i / steps;

        if (fromPlayer != null && previousTrack != null) {
          final double fromVol = startFromVolume * (1.0 - t);
          await fromPlayer.setVolume(fromVol.clamp(0.0, 1.0).toDouble());
          _currentVolumes[previousTrack] = fromVol;
        }

        final double toVol = endToVolume * t;
        await toPlayer.setVolume(toVol.clamp(0.0, 1.0).toDouble());
        _currentVolumes[targetTrack] = toVol;

        if (await _abortIfObsolete(
          generation: generation,
          previousScene: previousScene,
          previousTrack: previousTrack,
          previousTrackStartTime: previousTrackStartTime,
          previousWasPlaying: previousWasPlaying,
          previousTrackWasStopped: previousTrackWasStopped,
        )) {
          return;
        }

        await Future.delayed(stepDuration);

        if (await _abortIfObsolete(
          generation: generation,
          previousScene: previousScene,
          previousTrack: previousTrack,
          previousTrackStartTime: previousTrackStartTime,
          previousWasPlaying: previousWasPlaying,
          previousTrackWasStopped: previousTrackWasStopped,
        )) {
          return;
        }
      }

      if (await _abortIfObsolete(
        generation: generation,
        previousScene: previousScene,
        previousTrack: previousTrack,
        previousTrackStartTime: previousTrackStartTime,
        previousWasPlaying: previousWasPlaying,
        previousTrackWasStopped: previousTrackWasStopped,
      )) {
        return;
      }

      await _finalizeTransition(
        targetScene: nextState,
        targetTrack: targetTrack,
        targetVolume: endToVolume,
        candidateStartTime: candidateTrackStartTime,
        previousTrack: previousTrack,
        onPreviousTrackStopped: () {
          previousTrackWasStopped = true;
        },
      );
    } catch (error) {
      final isLatestRequest = generation == _generation;
      if (isLatestRequest) {
        _requestedScene = previousScene;
      }
      await _restoreStableStateNonCancellable(
        stableScene: previousScene,
        stableTrack: previousTrack,
        stableTrackStartTime: previousTrackStartTime,
        stableTrackWasPlaying: previousWasPlaying,
        stableTrackWasStopped: previousTrackWasStopped,
      );
      debugPrint('[AUDIO] Transition failed: $error');
    }
  }

  Future<bool> _abortIfObsolete({
    required int generation,
    required AudioSceneState? previousScene,
    required AudioTrackId? previousTrack,
    required DateTime previousTrackStartTime,
    required bool previousWasPlaying,
    required bool previousTrackWasStopped,
  }) async {
    if (generation == _generation) {
      return false;
    }

    await _restoreStableStateNonCancellable(
      stableScene: previousScene,
      stableTrack: previousTrack,
      stableTrackStartTime: previousTrackStartTime,
      stableTrackWasPlaying: previousWasPlaying,
      stableTrackWasStopped: previousTrackWasStopped,
    );

    return true;
  }

  Future<void> _finalizeTransition({
    required AudioSceneState targetScene,
    required AudioTrackId targetTrack,
    required double targetVolume,
    required DateTime? candidateStartTime,
    required AudioTrackId? previousTrack,
    required void Function() onPreviousTrackStopped,
  }) async {
    if (_disposed) return;

    if (_suspended) {
      await _finalizeSuspendedState(
        previousTrack: previousTrack,
        onPreviousTrackStopped: onPreviousTrackStopped,
      );
      return;
    }

    if (previousTrack != null && previousTrack != targetTrack) {
      final fromPlayer = backend.playerFor(previousTrack);
      await fromPlayer.stop();
      onPreviousTrackStopped();

      if (_disposed) return;
      if (_suspended) {
        await _finalizeSuspendedState();
        return;
      }

      await fromPlayer.setVolume(0.0);
      if (_disposed) return;
      if (_suspended) {
        await _finalizeSuspendedState();
        return;
      }
      _currentVolumes[previousTrack] = 0.0;
    }

    if (_disposed) return;
    if (_suspended) {
      await _finalizeSuspendedState();
      return;
    }

    await _silenceAndStopAllExceptNonCancellable(targetTrack);

    if (_disposed) return;
    if (_suspended) {
      await _finalizeSuspendedState();
      return;
    }

    final player = backend.playerFor(targetTrack);
    await player.setVolume(targetVolume);

    if (_disposed) return;
    if (_suspended) {
      await _finalizeSuspendedState();
      return;
    }

    _currentVolumes[targetTrack] = targetVolume;
    _currentScene = targetScene;
    _currentTrack = targetTrack;
    _isTrackPlaying = true;

    if (candidateStartTime != null) {
      _trackStartTime = candidateStartTime;
    }
  }

  Future<void> _finalizeSuspendedState({
    AudioTrackId? previousTrack,
    void Function()? onPreviousTrackStopped,
  }) async {
    await _bestEffortStopAllNonCancellable(
      onTrackStopped: (track) {
        if (track == previousTrack) {
          onPreviousTrackStopped?.call();
        }
      },
    );
    if (_disposed) return;

    _currentTrack = null;
    _isTrackPlaying = false;
  }

  Future<void> _silenceAndStopAllExceptNonCancellable(
      AudioTrackId targetTrack) async {
    for (final track in AudioTrackId.values) {
      if (track == targetTrack) continue;
      final player = backend.playerFor(track);
      try {
        await player.stop();
        await player.setVolume(0.0);
        _currentVolumes[track] = 0.0;
      } catch (e) {
        debugPrint('[AUDIO] Silence and stop failed for non-target $track: $e');
      }
    }
  }

  Future<void> _restoreStableStateNonCancellable({
    required AudioSceneState? stableScene,
    required AudioTrackId? stableTrack,
    required DateTime stableTrackStartTime,
    required bool stableTrackWasPlaying,
    required bool stableTrackWasStopped,
  }) async {
    if (_disposed || _suspended) {
      await _bestEffortStopAllNonCancellable();
      if (!_disposed) {
        _currentTrack = null;
        _isTrackPlaying = false;
      }
      return;
    }

    final effectiveStableTrack = stableTrack ??
        (stableScene != null ? audioSceneProfiles[stableScene]!.track : null);

    if (stableScene == null || effectiveStableTrack == null) {
      await _bestEffortStopAllNonCancellable();
      if (_disposed) return;

      _currentScene = null;
      _currentTrack = null;
      _isTrackPlaying = false;
      return;
    }

    try {
      final profile = audioSceneProfiles[stableScene]!;
      final player = backend.playerFor(effectiveStableTrack);

      await player.setPlaybackRate(profile.playbackRate);
      if (_disposed) {
        await _bestEffortStopAllNonCancellable();
        return;
      }
      if (_suspended) {
        await _finalizeSuspendedState();
        return;
      }

      final targetVolume = _applyDucking(profile.volume);
      await player.setVolume(targetVolume);
      if (_disposed) {
        await _bestEffortStopAllNonCancellable();
        return;
      }
      if (_suspended) {
        await _finalizeSuspendedState();
        return;
      }

      final requiresRestart = !stableTrackWasPlaying ||
          stableTrackWasStopped ||
          stableTrack == null;

      if (requiresRestart) {
        await player.resume();
      }

      if (_disposed) {
        await _bestEffortStopAllNonCancellable();
        return;
      }
      if (_suspended) {
        await _finalizeSuspendedState();
        return;
      }

      await _silenceAndStopAllExceptNonCancellable(effectiveStableTrack);
      if (_disposed) {
        await _bestEffortStopAllNonCancellable();
        return;
      }
      if (_suspended) {
        await _finalizeSuspendedState();
        return;
      }

      _currentVolumes[effectiveStableTrack] = targetVolume;
      _currentScene = stableScene;
      _currentTrack = effectiveStableTrack;
      _isTrackPlaying = true;
      _trackStartTime = requiresRestart ? DateTime.now() : stableTrackStartTime;
    } catch (e) {
      await _bestEffortStopAllNonCancellable();
      if (_disposed) return;

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

    await _bestEffortStopAllNonCancellable();
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

  bool _ducked = false;

  /// Restituisce se l'audio è attenuato in background.
  bool get isDucked => _ducked;

  double _applyDucking(double volume) => _ducked ? (volume * 0.25) : volume;

  /// Applica o rimuove l'attenuazione (ducking) del volume.
  Future<void> setDucked(bool ducked) async {
    if (_disposed) return;
    _ducked = ducked;
    await _enqueue(() async {
      if (_disposed || _currentTrack == null) return;
      final player = backend.playerFor(_currentTrack!);
      final profile = audioSceneProfiles[_currentScene];
      final baseVol = profile?.volume ?? 1.0;
      final targetVol = _applyDucking(baseVol);
      await player.setVolume(targetVol);
      _currentVolumes[_currentTrack!] = targetVol;
    });
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

    await _bestEffortStopAllNonCancellable();
  }

  Future<void> _bestEffortStopAllNonCancellable({
    void Function(AudioTrackId)? onTrackStopped,
  }) async {
    for (final trackId in AudioTrackId.values) {
      final p = backend.playerFor(trackId);
      try {
        await p.stop();
        onTrackStopped?.call(trackId);
        await p.setVolume(0.0);
        _currentVolumes[trackId] = 0.0;
      } catch (error) {
        debugPrint('[AUDIO] Emergency stop failed for $trackId: $error');
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
        debugPrint(
            "Errore nel rilascio delle risorse della traccia $trackId: $e");
      }
    }
  }
}
