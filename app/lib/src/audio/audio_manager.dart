import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';
import 'sound_generator.dart';

/// Gestore del compartimento audio e degli effetti sonori del gioco.
///
/// Implementa un design Singleton per coordinare il loop del sottofondo (BGM)
/// e il pool di effetti sonori (SFX) riprodotti in risposta alle azioni dell'utente
/// o alle metriche dei pilastri di PANOPTICON.
class AudioManager {
  static final AudioManager _instance = AudioManager._internal();
  /// Costruttore Factory per recuperare l'istanza singleton di [AudioManager].
  factory AudioManager() => _instance;
  AudioManager._internal();

  bool _initialized = false;
  bool _audioEnabled = true;

  /// Specifica se le istanze di AudioPlayer sono state effettivamente istanziate.
  ///
  /// Su sistemi Windows viene effettuato un controllo prima dell'istanziazione
  /// a causa di incompatibilità note su thread nativi del pacchetto audioplayers.
  bool _playersCreated = false;

  // Riproduttori per la musica di sottofondo (BGM)
  late final AudioPlayer _bgmMainPlayer;
  late final AudioPlayer _bgmAmbientPlayer;
  late final AudioPlayer _bgmTensePlayer;
  late final AudioPlayer _bgmEpicPlayer;

  // Pool fisso di riproduttori per effetti sonori (SFX)
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

  // Stato corrente del livello di allerta di gioco
  int _currentAlert = 0;
  bool _isEpic = true;
  bool _isVictory = false;
  String? _currentBgmTrack;
  DateTime _trackStartTime = DateTime.now();

  // Future per tracciare le transizioni attive ed evitare race condition e sovrapposizioni audio.
  Future<void>? _activeTransition;

  /// Indica se il gestore audio è stato correttamente inizializzato.
  bool get isInitialized => _initialized;
  /// Indica se la riproduzione audio è abilitata.
  bool get audioEnabled => _audioEnabled;

  /// Restituisce i BPM effettivi della traccia in esecuzione
  double get currentBpm {
    if (!_initialized || !_audioEnabled || _currentBgmTrack == null) return 0.0;
    if (_currentBgmTrack == 'main' || _currentBgmTrack == 'epic') {
      return 120.0;
    }
    if (_currentBgmTrack == 'game') {
      if (_currentAlert >= 40) {
        return _currentAlert > 80 ? 144.0 : 120.0;
      } else {
        return 60.0;
      }
    }
    return 120.0;
  }

  /// Restituisce il timestamp di avvio della traccia attiva
  DateTime get trackStartTime => _trackStartTime;

  /// Inizializza il modulo audio, genera i file WAV procedurali su disco e alloca il pool dei player.
  Future<void> initialize(String appDataPath, {bool audioEnabled = true}) async {
    if (_initialized) return;
    _audioEnabled = audioEnabled;

    if (!audioEnabled) {
      _playersCreated = false;
      _initialized = true;
      return;
    }

    // Avviso specifico per la piattaforma Windows
    if (Platform.isWindows) {
      debugPrint(
        '[AUDIO] WARNING: Esecuzione di audioplayers su Windows. Avvisi di threading '
        '(shell.cc:1183) potrebbero apparire in console. La migrazione a just_audio '
        'è pianificata per la versione successiva.',
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

    // Crea i player di sottofondo
    _bgmMainPlayer = AudioPlayer();
    _bgmAmbientPlayer = AudioPlayer();
    _bgmTensePlayer = AudioPlayer();
    _bgmEpicPlayer = AudioPlayer();

    // Crea il pool riutilizzabile per gli effetti SFX
    _sfxClickPlayer = AudioPlayer();
    _sfxAlertPlayer = AudioPlayer();
    _sfxGlitchPlayer = AudioPlayer();
    _sfxChimePlayer = AudioPlayer();

    // Imposta la riproduzione in loop per la BGM
    await _bgmMainPlayer.setReleaseMode(ReleaseMode.loop);
    await _bgmAmbientPlayer.setReleaseMode(ReleaseMode.loop);
    await _bgmTensePlayer.setReleaseMode(ReleaseMode.loop);
    await _bgmEpicPlayer.setReleaseMode(ReleaseMode.loop);

    _playersCreated = true;
    _initialized = true;
  }

  /// Abilita o disabilita dinamicamente l'audio globale.
  void setAudioEnabled(bool enabled) {
    if (!_playersCreated) return;
    if (_audioEnabled == enabled) return;
    _audioEnabled = enabled;
    if (!_audioEnabled) {
      // Ferma immediatamente tutte le riproduzioni attive
      stopBgm();
    } else {
      // Riprende la musica di sottofondo
      startBgm();
    }
  }

  /// Avvia la riproduzione delle tracce musicali di sottofondo.
  /// Ferma i player inutilizzati in base al tipo di soundscape per risparmiare risorse.
  Future<void> startBgm({bool? isEpic, bool? isVictory}) async {
    // Se c'è una transizione in corso, attendiamo che finisca per evitare conflitti sui canali audio.
    if (_activeTransition != null) {
      try {
        await _activeTransition;
      } catch (_) {}
    }

    final transition = _startBgmInternal(isEpic: isEpic, isVictory: isVictory);
    _activeTransition = transition;
    try {
      await transition;
    } finally {
      if (_activeTransition == transition) {
        _activeTransition = null;
      }
    }
  }

  Future<void> _startBgmInternal({bool? isEpic, bool? isVictory}) async {
    if (!_playersCreated || !_audioEnabled) return;

    final bool targetEpic = isEpic ?? _isEpic;
    final bool targetVictory = isVictory ?? _isVictory;

    final String targetTrack;
    if (targetEpic) {
      targetTrack = targetVictory ? 'epic' : 'main';
    } else {
      targetTrack = 'game';
    }

    if (_currentBgmTrack == targetTrack) {
      // La traccia desiderata è già attiva, non c'è bisogno di riavviarla.
      // Aggiorniamo comunque lo stato interno.
      if (isEpic != null) {
        _isEpic = isEpic;
      }
      if (isVictory != null) {
        _isVictory = isVictory;
      }
      return;
    }

    if (isEpic != null) {
      _isEpic = isEpic;
    }
    if (isVictory != null) {
      _isVictory = isVictory;
    }
    _currentBgmTrack = targetTrack;
    _trackStartTime = DateTime.now();

    try {
      if (_isEpic) {
        // Ferma le altre tracce per liberare risorse su thread nativi
        await _bgmAmbientPlayer.stop();
        await _bgmTensePlayer.stop();

        if (_isVictory) {
          await _bgmMainPlayer.stop();
          if (_bgmEpicPath != null) {
            await _bgmEpicPlayer.stop();
            await _bgmEpicPlayer.setSource(DeviceFileSource(_bgmEpicPath!));
            await _bgmEpicPlayer.setReleaseMode(ReleaseMode.loop);
            await _bgmEpicPlayer.resume();
          }
        } else {
          await _bgmEpicPlayer.stop();
          if (_bgmMainPath != null) {
            await _bgmMainPlayer.stop();
            await _bgmMainPlayer.setSource(DeviceFileSource(_bgmMainPath!));
            await _bgmMainPlayer.setReleaseMode(ReleaseMode.loop);
            await _bgmMainPlayer.resume();
          }
        }
      } else {
        // Ferma le tracce Epic e Main per liberare risorse su thread nativi
        await _bgmEpicPlayer.stop();
        await _bgmMainPlayer.stop();

        if (_bgmAmbientPath != null) {
          await _bgmAmbientPlayer.stop();
          await _bgmAmbientPlayer.setSource(DeviceFileSource(_bgmAmbientPath!));
          await _bgmAmbientPlayer.setReleaseMode(ReleaseMode.loop);
          await _bgmAmbientPlayer.resume();
        }
        if (_bgmTensePath != null) {
          await _bgmTensePlayer.stop();
          await _bgmTensePlayer.setSource(DeviceFileSource(_bgmTensePath!));
          await _bgmTensePlayer.setReleaseMode(ReleaseMode.loop);
          await _bgmTensePlayer.resume();
        }
      }
      // Attendi che il thread audio nativo si sia avviato per evitare che sovrascriva i volumi impostati
      await Future.delayed(const Duration(milliseconds: 250));
      // Applica immediatamente il mix in base all'allerta corrente
      await updateAlertLevel(_currentAlert, force: true);
    } catch (e) {
      debugPrint("Errore all'avvio della BGM: $e");
    }
  }

  /// Ferma la riproduzione delle tracce musicali di sottofondo.
  Future<void> stopBgm() async {
    if (!_playersCreated) return;
    _currentBgmTrack = null;
    try {
      await _bgmAmbientPlayer.stop();
      await _bgmTensePlayer.stop();
      await _bgmMainPlayer.stop();
      await _bgmEpicPlayer.stop();
    } catch (e) {
      debugPrint("Errore nell'arresto della BGM: $e");
    }
  }

  /// Aggiorna il mix delle tracce audio BGM in tempo reale basandosi sull'allerta di PANOPTICON.
  ///
  /// Le formule di mixing applicate sono:
  /// * isEpic: solo la traccia epica del menù principale / vittoria (volume 0.6), altre silenziate (volume 0.0).
  /// * Standard (isEpic = false):
  ///   * Allerta < 40: solo basso ambient (volume 0.6), arpeggiatore tense silenziato (volume 0.0).
  ///   * Allerta 40-80: dissolvenza incrociata (l'ambient sfuma a 0.4, il tense sale a 0.6).
  ///   * Allerta > 80: arpeggiatore tense al massimo (1.0), basso ambient al minimo (0.1) e accelerazione a 1.2x.
  Future<void> updateAlertLevel(int alert, {bool force = false, bool? isEpic, bool? isVictory}) async {
    if (!_initialized) return;
    bool isEpicChanged = false;
    if (isEpic != null && isEpic != _isEpic) {
      _isEpic = isEpic;
      isEpicChanged = true;
    }
    bool isVictoryChanged = false;
    if (isVictory != null && isVictory != _isVictory) {
      _isVictory = isVictory;
      isVictoryChanged = true;
    }
    // Evita il ritorno anticipato se lo stato isEpic o isVictory è cambiato, per garantire la corretta transizione delle tracce audio.
    if (_currentAlert == alert && !isEpicChanged && !isVictoryChanged && !force) return;
    _currentAlert = alert;

    if (!_playersCreated || !_audioEnabled) return;

    if (isEpicChanged || isVictoryChanged) {
      // Se lo stato isEpic o isVictory è cambiato, riavviamo la BGM con la modalità corretta per accertarci che parta/si fermi
      await startBgm(isVictory: _isVictory);
      return;
    }

    double ambientVol = 0.0;
    double tenseVol = 0.0;
    double mainVol = 0.0;
    double epicVol = 0.0;
    double tenseRate = 1.0;

    if (_isEpic) {
      ambientVol = 0.0;
      tenseVol = 0.0;
      if (_isVictory) {
        mainVol = 0.0;
        epicVol = 0.6;
      } else {
        mainVol = 0.6;
        epicVol = 0.0;
      }
    } else {
      mainVol = 0.0;
      epicVol = 0.0;
      if (alert < 40) {
        ambientVol = 0.6;
        tenseVol = 0.0;
        tenseRate = 1.0;
      } else if (alert <= 80) {
        ambientVol = 0.4;
        tenseVol = 0.6;
        tenseRate = 1.0;
      } else {
        ambientVol = 0.1;
        tenseVol = 1.0;
        tenseRate = 1.2;
      }
    }

    try {
      await _bgmAmbientPlayer.setVolume(ambientVol);
      await _bgmTensePlayer.setVolume(tenseVol);
      await _bgmTensePlayer.setPlaybackRate(tenseRate);
      await _bgmMainPlayer.setVolume(mainVol);
      await _bgmEpicPlayer.setVolume(epicVol);
    } catch (e) {
      debugPrint("Errore nel mixing degli stem audio: $e");
    }
  }

  /// Esegue la riproduzione interna di un file SFX in modalità Fire-and-Forget per prevenire micro-freeze dell'UI thread.
  void _playSfx(AudioPlayer player, String? path, {double volume = 1.0}) {
    if (!_playersCreated || !_audioEnabled || path == null) return;
    player.stop().then((_) {
      player.setVolume(volume);
      player.play(DeviceFileSource(path));
    }).catchError((e) {
      debugPrint("Errore durante la riproduzione dell'SFX: $e");
    });
  }

  /// Riproduce il suono di click della digitazione a schermo.
  void playClick() {
    if (!_playersCreated) return;
    _playSfx(_sfxClickPlayer, _sfxClickPath, volume: 0.25);
  }

  /// Riproduce il suono di allarme del sistema.
  void playAlert() {
    if (!_playersCreated) return;
    _playSfx(_sfxAlertPlayer, _sfxAlertPath);
  }

  /// Riproduce l'effetto sonoro di glitch e crash.
  void playGlitch() {
    if (!_playersCreated) return;
    _playSfx(_sfxGlitchPlayer, _sfxGlitchPath);
  }

  /// Riproduce l'effetto sonoro positivo all'aggiornamento dei pilastri cognitivi.
  void playChime() {
    if (!_playersCreated) return;
    _playSfx(_sfxChimePlayer, _sfxChimePath);
  }

  /// Rilascia tutte le risorse occupate dai player multimediali.
  Future<void> dispose() async {
    if (!_playersCreated) {
      _initialized = false;
      return;
    }
    try {
      await _bgmMainPlayer.dispose();
      await _bgmAmbientPlayer.dispose();
      await _bgmTensePlayer.dispose();
      await _bgmEpicPlayer.dispose();
      await _sfxClickPlayer.dispose();
      await _sfxAlertPlayer.dispose();
      await _sfxGlitchPlayer.dispose();
      await _sfxChimePlayer.dispose();
    } catch (e) {
      debugPrint("Errore nel rilascio delle risorse audio: $e");
    }
    _playersCreated = false;
    _initialized = false;
  }
}
