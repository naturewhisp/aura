import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';
import 'sound_generator.dart';
import 'audio_scene.dart';
import 'bgm_player.dart';
import 'audio_scene_machine.dart';

/// Implementazione di [BgmPlayer] basata su [AudioPlayer] nativo del pacchetto `audioplayers`.
class AudioplayersBgmPlayer implements BgmPlayer {
  final AudioPlayer _player;

  /// Costruisce una traccia [AudioplayersBgmPlayer] avvolgendo un [AudioPlayer] nativo.
  AudioplayersBgmPlayer(this._player);

  @override
  Future<void> setSource(String path) async {
    await _player.setSource(DeviceFileSource(path));
  }

  @override
  Future<void> setVolume(double volume) async {
    await _player.setVolume(volume);
  }

  @override
  Future<void> setPlaybackRate(double rate) async {
    await _player.setPlaybackRate(rate);
  }

  @override
  Future<void> resume() async {
    await _player.resume();
  }

  @override
  Future<void> stop() async {
    await _player.stop();
  }

  @override
  Future<void> dispose() async {
    await _player.dispose();
  }
}

/// Implementazione concreta di [AudioPlaybackBackend] per la produzione.
class AudioplayersPlaybackBackend implements AudioPlaybackBackend {
  final Map<AudioTrackId, BgmPlayer> _players;

  /// Costruisce il backend mappando le tracce fisiche ai rispettivi player.
  AudioplayersPlaybackBackend(this._players);

  @override
  BgmPlayer playerFor(AudioTrackId track) {
    return _players[track]!;
  }
}

/// Gestore principale del comparto audio ed effetti sonori del gioco.
///
/// Implementa un design Singleton per coordinare il loop musicale ed incapsula
/// l'istanza della macchina a stati [AudioSceneMachine].
class AudioManager {
  static final AudioManager _instance = AudioManager._internal();

  /// Costruttore Factory per recuperare l'istanza singleton di [AudioManager].
  factory AudioManager() => _instance;
  AudioManager._internal();

  bool _initialized = false;
  bool _audioEnabled = true;
  bool _playersCreated = false;

  // Riproduttori per gli effetti sonori (SFX)
  late final AudioPlayer _sfxClickPlayer;
  late final AudioPlayer _sfxAlertPlayer;
  late final AudioPlayer _sfxGlitchPlayer;
  late final AudioPlayer _sfxChimePlayer;

  // Percorsi dei file audio WAV generati temporaneamente su disco
  String? _bgmMainPath;
  String? _bgmAmbientPath;
  String? _bgmTensePath;
  String? _bgmEpicPath;
  String? _sfxClickPath;
  String? _sfxAlertPath;
  String? _sfxGlitchPath;
  String? _sfxChimePath;

  // La macchina a stati audio interna
  late final AudioSceneMachine _machine;

  /// Restituisce l'istanza della macchina a stati audio (utile per iniettare mock nei test).
  @visibleForTesting
  AudioSceneMachine get machine => _machine;

  /// Indica se il gestore audio è stato correttamente inizializzato.
  bool get isInitialized => _initialized;

  /// Indica se la riproduzione audio è abilitata.
  bool get audioEnabled => _audioEnabled;

  /// Restituisce i BPM effettivi della traccia in esecuzione ricavati dal profilo attivo.
  double get currentBpm {
    if (!_initialized || !_audioEnabled) return 0.0;
    return _machine.currentBpm;
  }

  /// Restituisce il timestamp di avvio della traccia attiva.
  DateTime get trackStartTime => _machine.trackStartTime;

  /// Inizializza il modulo audio, genera i file WAV procedurali su disco e alloca il pool dei player.
  Future<void> initialize(String appDataPath, {bool audioEnabled = true}) async {
    if (_initialized) return;
    _audioEnabled = audioEnabled;

    // Verifica se siamo in un ambiente di test per caricare il no-op player
    final isTest = Platform.environment.containsKey('FLUTTER_TEST') ||
                   Platform.environment.containsKey('DART_TEST');

    if (isTest) {
      final backend = NoOpAudioPlaybackBackend();
      _machine = AudioSceneMachine(
        backend: backend,
        trackPaths: const {},
      );
      _playersCreated = true;
      _initialized = true;
      return;
    }

    // Avviso specifico per la piattaforma Windows
    if (Platform.isWindows) {
      debugPrint(
        '[AUDIO] WARNING: Esecuzione di audioplayers su Windows. Avvisi di threading '
        '(shell.cc:1183) potrebbero apparire in console.',
      );
    }

    // Assicura che la directory temporanea per i file audio esista
    final audioDir = Directory('$appDataPath/audio');
    if (!audioDir.existsSync()) {
      audioDir.createSync(recursive: true);
    }

    // Genera proceduralmente tutti i suoni WAV necessari al gioco
    await SoundGenerator.generateAllSounds(audioDir.path);

    // Memorizza i percorsi dei file WAV generati
    _bgmMainPath = '${audioDir.path}/bgm_main.wav';
    _bgmAmbientPath = '${audioDir.path}/bgm_ambient.wav';
    _bgmTensePath = '${audioDir.path}/bgm_tense.wav';
    _bgmEpicPath = '${audioDir.path}/bgm_epic.wav';
    _sfxClickPath = '${audioDir.path}/sfx_click.wav';
    _sfxAlertPath = '${audioDir.path}/sfx_alert.wav';
    _sfxGlitchPath = '${audioDir.path}/sfx_glitch.wav';
    _sfxChimePath = '${audioDir.path}/sfx_chime.wav';

    // Crea i player di sottofondo nativi (sempre creati per prevenire stati incoerenti)
    final bgmMainPlayer = AudioPlayer();
    final bgmAmbientPlayer = AudioPlayer();
    final bgmTensePlayer = AudioPlayer();
    final bgmEpicPlayer = AudioPlayer();

    await bgmMainPlayer.setReleaseMode(ReleaseMode.loop);
    await bgmAmbientPlayer.setReleaseMode(ReleaseMode.loop);
    await bgmTensePlayer.setReleaseMode(ReleaseMode.loop);
    await bgmEpicPlayer.setReleaseMode(ReleaseMode.loop);

    // Crea il pool per gli effetti SFX
    _sfxClickPlayer = AudioPlayer();
    _sfxAlertPlayer = AudioPlayer();
    _sfxGlitchPlayer = AudioPlayer();
    _sfxChimePlayer = AudioPlayer();

    // Configura il backend e la macchina a stati
    final bgmPlayers = {
      AudioTrackId.main: AudioplayersBgmPlayer(bgmMainPlayer),
      AudioTrackId.ambient: AudioplayersBgmPlayer(bgmAmbientPlayer),
      AudioTrackId.tense: AudioplayersBgmPlayer(bgmTensePlayer),
      AudioTrackId.epic: AudioplayersBgmPlayer(bgmEpicPlayer),
    };

    final backend = AudioplayersPlaybackBackend(bgmPlayers);
    final trackPaths = {
      AudioTrackId.main: _bgmMainPath,
      AudioTrackId.ambient: _bgmAmbientPath,
      AudioTrackId.tense: _bgmTensePath,
      AudioTrackId.epic: _bgmEpicPath,
    };

    _machine = AudioSceneMachine(
      backend: backend,
      trackPaths: trackPaths,
    );

    _playersCreated = true;
    _initialized = true;

    // Se l'audio globale è inizialmente disabilitato, sospende la riproduzione fisica
    if (!_audioEnabled) {
      await _machine.suspendAudio();
    }
  }

  /// Abilita o disabilita dinamicamente l'audio globale.
  void setAudioEnabled(bool enabled) {
    if (!_playersCreated) return;
    if (_audioEnabled == enabled) return;
    _audioEnabled = enabled;

    if (!_audioEnabled) {
      _machine.suspendAudio();
    } else {
      _machine.resumeAudio();
    }
  }

  /// Avvia la transizione verso uno stato della scena musicale.
  Future<void> transitionTo(AudioSceneState nextState, {bool force = false}) async {
    if (!_initialized || !_audioEnabled) {
      // Memorizza comunque la richiesta nella macchina
      if (_initialized) {
        // Ignora il caricamento fisico ma traccia logicamente la richiesta
        _machine.transitionTo(nextState, force: force);
      }
      return;
    }
    await _machine.transitionTo(nextState, force: force);
  }

  /// Ferma la riproduzione musicale.
  Future<void> stopBgm() async {
    if (!_playersCreated) return;
    await _machine.stopBgm();
  }

  /// Esegue la riproduzione interna di un file SFX in modalità Fire-and-Forget.
  void _playSfx(AudioPlayer player, String? path, {double volume = 1.0}) {
    if (!_playersCreated || !_audioEnabled || path == null) return;
    player.stop().then((_) {
      player.play(DeviceFileSource(path)).then((_) {
        player.setVolume(volume);
      });
    }).catchError((e) {
      debugPrint("Errore durante la riproduzione dell'SFX: $e");
    });
  }

  /// Riproduce il suono di click della digitazione a schermo.
  void playClick() {
    if (!_playersCreated || Platform.environment.containsKey('FLUTTER_TEST')) return;
    _playSfx(_sfxClickPlayer, _sfxClickPath, volume: 0.25);
  }

  /// Riproduce il suono di allarme del sistema.
  void playAlert() {
    if (!_playersCreated || Platform.environment.containsKey('FLUTTER_TEST')) return;
    _playSfx(_sfxAlertPlayer, _sfxAlertPath);
  }

  /// Riproduce l'effetto sonoro di glitch e crash.
  void playGlitch() {
    if (!_playersCreated || Platform.environment.containsKey('FLUTTER_TEST')) return;
    _playSfx(_sfxGlitchPlayer, _sfxGlitchPath);
  }

  /// Riproduce l'effetto sonoro positivo all'aggiornamento dei pilastri cognitivi.
  void playChime() {
    if (!_playersCreated || Platform.environment.containsKey('FLUTTER_TEST')) return;
    _playSfx(_sfxChimePlayer, _sfxChimePath);
  }

  /// Rilascia tutte le risorse occupate dai player multimediali.
  Future<void> dispose() async {
    if (!_playersCreated) {
      _initialized = false;
      return;
    }
    try {
      await _machine.dispose();
      if (!Platform.environment.containsKey('FLUTTER_TEST')) {
        await _sfxClickPlayer.dispose();
        await _sfxAlertPlayer.dispose();
        await _sfxGlitchPlayer.dispose();
        await _sfxChimePlayer.dispose();
      }
    } catch (e) {
      debugPrint("Errore nel rilascio delle risorse audio: $e");
    }
    _playersCreated = false;
    _initialized = false;
  }
}
