import 'dart:async';
import 'package:flutter/foundation.dart';
import 'audio_scene.dart';
import 'bgm_player.dart';

/// Macchina a stati audio per la gestione delle transizioni e del crossfade delle BGM.
///
/// Questa classe è interamente istanziabile e disaccoppiata da flutter e audioplayers,
/// permettendo un isolamento perfetto durante l'esecuzione dei test unitari deterministici.
class AudioSceneMachine {
  /// Il backend di riproduzione audio attivo.
  final AudioPlaybackBackend backend;

  /// Mappa che associa ciascuna traccia al rispettivo percorso file WAV su disco.
  final Map<AudioTrackId, String?> trackPaths;

  AudioSceneState? _requestedScene;
  AudioSceneState? _currentScene;
  AudioTrackId? _currentTrack;
  bool _isTrackPlaying = false;
  int _transitionGeneration = 0;
  DateTime _trackStartTime = DateTime.now();

  // Future per serializzare le transizioni asincrone attive sul thread nativo.
  Future<void>? _activeTransition;

  // Traccia del volume fisico corrente per ciascuna traccia per gestire transizioni interrotte.
  final Map<AudioTrackId, double> _currentVolumes = {
    AudioTrackId.main: 0.0,
    AudioTrackId.ambient: 0.0,
    AudioTrackId.tense: 0.0,
    AudioTrackId.epic: 0.0,
  };

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
    if (_currentScene == null) return 0.0;
    return audioSceneProfiles[_currentScene]?.bpm ?? 0.0;
  }

  /// Restituisce il volume fisico memorizzato per una determinata traccia.
  double getVolumeFor(AudioTrackId track) => _currentVolumes[track] ?? 0.0;

  /// Richiede una transizione verso una nuova scena musicale.
  ///
  /// Se la richiesta è identica alla scena precedentemente richiesta, la chiamata
  /// viene ignorata (idempotenza). Le transizioni concorrenti vengono serializzate
  /// a basso livello, ma i fade obsoleti vengono annullati logicamente tramite un token generazionale.
  Future<void> transitionTo(AudioSceneState nextState, {bool force = false}) async {
    if (!force && nextState == _requestedScene) {
      return;
    }

    _requestedScene = nextState;
    final generation = ++_transitionGeneration;

    // Serializzazione delle chiamate asincrone natali.
    if (_activeTransition != null) {
      try {
        await _activeTransition;
      } catch (_) {}
    }

    // Se nel frattempo è stata emessa una nuova richiesta, annulliamo questa transizione.
    if (generation != _transitionGeneration) {
      return;
    }

    final transition = _executeTransition(nextState, generation);
    _activeTransition = transition;
    try {
      await transition;
    } finally {
      if (_activeTransition == transition) {
        _activeTransition = null;
      }
    }
  }

  Future<void> _executeTransition(AudioSceneState nextState, int generation) async {
    final targetProfile = audioSceneProfiles[nextState]!;
    final targetTrack = targetProfile.track;
    final targetPath = trackPaths[targetTrack];

    // Salva lo stato precedente
    final previousScene = _currentScene;
    final previousTrack = _currentTrack;
    final previousProfile = previousScene != null ? audioSceneProfiles[previousScene] : null;

    if (previousTrack == targetTrack && previousTrack != null) {
      // transizione Same-Track: modula unicamente il volume senza interrompere la traccia.
      final player = backend.playerFor(targetTrack);
      
      // Volume di partenza reale basato sull'effettivo volume fisico del player
      final double startVol = _currentVolumes[targetTrack] ?? previousProfile?.volume ?? 0.0;
      final double endVol = targetProfile.volume;
      final duration = targetProfile.transitionDuration;

      _currentScene = nextState;

      // Eseguiamo la rampa di volume dello stesso player
      const steps = 8;
      final stepDuration = duration ~/ steps;

      for (int i = 1; i <= steps; i++) {
        if (generation != _transitionGeneration) return; // Annullamento logico
        final double t = i / steps;
        final double vol = startVol + (endVol - startVol) * t;
        
        await player.setVolume(vol.clamp(0.0, 1.0));
        _currentVolumes[targetTrack] = vol;
        
        await Future.delayed(stepDuration);
      }

      if (generation != _transitionGeneration) return;
      await player.setVolume(endVol);
      _currentVolumes[targetTrack] = endVol;
      _isTrackPlaying = true;
      return;
    }

    // transizione Crossfade per tracce fisiche differenti.
    _trackStartTime = DateTime.now();

    final BgmPlayer? fromPlayer = previousTrack != null ? backend.playerFor(previousTrack) : null;
    final BgmPlayer toPlayer = backend.playerFor(targetTrack);

    try {
      // 1. Ferma fisicamente e silenzia tutte le altre tracce diverse da target e previous
      for (final trackId in AudioTrackId.values) {
        if (trackId != previousTrack && trackId != targetTrack) {
          final p = backend.playerFor(trackId);
          await p.stop();
          await p.setVolume(0.0);
          _currentVolumes[trackId] = 0.0;
        }
      }

      if (generation != _transitionGeneration) return;

      // 2. Prepariamo e avviamo il toPlayer a volume 0.0
      if (targetPath != null) {
        await toPlayer.stop();
        await toPlayer.setSource(targetPath);
        await toPlayer.setPlaybackRate(targetProfile.playbackRate);
        await toPlayer.setVolume(0.0);
        _currentVolumes[targetTrack] = 0.0;
        await toPlayer.resume();
      }

      if (generation != _transitionGeneration) return;

      // Breve pausa per attendere l'avvio nativo del thread
      await Future.delayed(const Duration(milliseconds: 150));

      if (generation != _transitionGeneration) return;

      // 3. Eseguiamo il crossfade
      const steps = 8;
      final duration = targetProfile.transitionDuration;
      final stepDuration = duration ~/ steps;

      // Volume di partenza del player uscente reale
      final double startFromVolume = previousTrack != null ? (_currentVolumes[previousTrack] ?? previousProfile?.volume ?? 0.0) : 0.0;
      final double endToVolume = targetProfile.volume;

      for (int i = 1; i <= steps; i++) {
        if (generation != _transitionGeneration) return; // Annullamento logico
        final double t = i / steps;

        if (fromPlayer != null && previousTrack != null) {
          final double fromVol = startFromVolume * (1.0 - t);
          await fromPlayer.setVolume(fromVol.clamp(0.0, 1.0));
          _currentVolumes[previousTrack] = fromVol;
        }

        final double toVol = endToVolume * t;
        await toPlayer.setVolume(toVol.clamp(0.0, 1.0));
        _currentVolumes[targetTrack] = toVol;

        await Future.delayed(stepDuration);
      }

      if (generation != _transitionGeneration) return;

      // 4. Stoppiamo e azzeriamo completamente il fromPlayer uscente
      if (fromPlayer != null && previousTrack != null) {
        await fromPlayer.stop();
        await fromPlayer.setVolume(0.0);
        _currentVolumes[previousTrack] = 0.0;
      }

      // Impostiamo il volume target finale per toPlayer
      await toPlayer.setVolume(endToVolume);
      _currentVolumes[targetTrack] = endToVolume;

      // Transizione completata con successo: aggiorniamo lo stato
      _currentScene = nextState;
      _currentTrack = targetTrack;
      _isTrackPlaying = true;
    } catch (e) {
      debugPrint("Errore durante l'esecuzione del crossfade: $e");
    }
  }

  /// Disabilita e sospende fisicamente l'audio dei player, incrementando il token generazionale.
  ///
  /// Conserva intatta la scena richiesta semanticamente in [_requestedScene] per il ripristino.
  Future<void> suspendAudio() async {
    _transitionGeneration++;
    _isTrackPlaying = false;
    _currentTrack = null;
    
    // Ferma tutti i player a livello hardware
    for (final trackId in AudioTrackId.values) {
      final p = backend.playerFor(trackId);
      try {
        await p.stop();
        await p.setVolume(0.0);
        _currentVolumes[trackId] = 0.0;
      } catch (e) {
        debugPrint("Errore nella sospensione della traccia $trackId: $e");
      }
    }
  }

  /// Ripristina la riproduzione audio forzando l'avvio dello stato richiesto [_requestedScene].
  Future<void> resumeAudio() async {
    final target = _requestedScene;
    if (target != null) {
      await transitionTo(target, force: true);
    }
  }

  /// Ferma tutti i player fisicamente e resetta lo stato logico completato.
  Future<void> stopBgm() async {
    _transitionGeneration++;
    _currentScene = null;
    _currentTrack = null;
    _isTrackPlaying = false;

    for (final trackId in AudioTrackId.values) {
      final p = backend.playerFor(trackId);
      try {
        await p.stop();
        await p.setVolume(0.0);
        _currentVolumes[trackId] = 0.0;
      } catch (e) {
        debugPrint("Errore nell'arresto della traccia $trackId: $e");
      }
    }
  }

  /// Rilascia le risorse hardware di tutti i player.
  Future<void> dispose() async {
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
