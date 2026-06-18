import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';
import 'sound_generator.dart';

class AudioManager {
  static final AudioManager _instance = AudioManager._internal();
  factory AudioManager() => _instance;
  AudioManager._internal();

  bool _initialized = false;
  bool _audioEnabled = true;

  // BGM Players
  late final AudioPlayer _bgmAmbientPlayer;
  late final AudioPlayer _bgmTensePlayer;

  // SFX Players — fixed pool, one per sound type, reused across calls.
  // This avoids creating/disposing AudioPlayer instances on every SFX call,
  // which causes native threading crashes on Windows (audioplayers_windows
  // sends events from a non-platform thread during rapid create/dispose).
  late final AudioPlayer _sfxClickPlayer;
  late final AudioPlayer _sfxAlertPlayer;
  late final AudioPlayer _sfxGlitchPlayer;
  late final AudioPlayer _sfxChimePlayer;

  // Paths
  String? _bgmAmbientPath;
  String? _bgmTensePath;
  String? _sfxClickPath;
  String? _sfxAlertPath;
  String? _sfxGlitchPath;
  String? _sfxChimePath;

  // Current levels
  int _currentAlert = 0;

  bool get isInitialized => _initialized;
  bool get audioEnabled => _audioEnabled;

  Future<void> initialize(String appDataPath, {bool audioEnabled = true}) async {
    if (_initialized) return;
    _audioEnabled = audioEnabled;

    // Ensure directory exists
    final audioDir = Directory('$appDataPath/audio');
    if (!audioDir.existsSync()) {
      audioDir.createSync(recursive: true);
    }

    // Generate sounds
    await SoundGenerator.generateAllSounds(audioDir.path);

    // Save paths
    _bgmAmbientPath = '${audioDir.path}/bgm_ambient.wav';
    _bgmTensePath = '${audioDir.path}/bgm_tense.wav';
    _sfxClickPath = '${audioDir.path}/sfx_click.wav';
    _sfxAlertPath = '${audioDir.path}/sfx_alert.wav';
    _sfxGlitchPath = '${audioDir.path}/sfx_glitch.wav';
    _sfxChimePath = '${audioDir.path}/sfx_chime.wav';

    // Initialize BGM players
    _bgmAmbientPlayer = AudioPlayer();
    _bgmTensePlayer = AudioPlayer();

    // Initialize SFX pool — each player is reused, not disposed after play.
    _sfxClickPlayer = AudioPlayer();
    _sfxAlertPlayer = AudioPlayer();
    _sfxGlitchPlayer = AudioPlayer();
    _sfxChimePlayer = AudioPlayer();

    // Set loops for BGM only
    await _bgmAmbientPlayer.setReleaseMode(ReleaseMode.loop);
    await _bgmTensePlayer.setReleaseMode(ReleaseMode.loop);

    // SFX play once and stop (default ReleaseMode.stop is correct)

    _initialized = true;
  }

  void setAudioEnabled(bool enabled) {
    if (_audioEnabled == enabled) return;
    _audioEnabled = enabled;
    if (!_audioEnabled) {
      // Stop everything
      stopBgm();
    } else {
      // Resume/Start BGM if it was supposed to play
      startBgm();
    }
  }

  Future<void> startBgm() async {
    if (!_initialized || !_audioEnabled) return;

    try {
      // Start both bgm players
      if (_bgmAmbientPath != null) {
        await _bgmAmbientPlayer.play(DeviceFileSource(_bgmAmbientPath!));
      }
      if (_bgmTensePath != null) {
        await _bgmTensePlayer.play(DeviceFileSource(_bgmTensePath!));
      }
      // Apply current levels mixing
      await updateAlertLevel(_currentAlert, force: true);
    } catch (e) {
      // Ignore or log
      debugPrint("Error starting BGM: $e");
    }
  }

  Future<void> stopBgm() async {
    if (!_initialized) return;
    try {
      await _bgmAmbientPlayer.stop();
      await _bgmTensePlayer.stop();
    } catch (e) {
      debugPrint("Error stopping BGM: $e");
    }
  }

  Future<void> updateAlertLevel(int alert, {bool force = false}) async {
    if (!_initialized) return;
    if (_currentAlert == alert && !force) return;
    _currentAlert = alert;

    if (!_audioEnabled) return;

    // Mix mixing logic based on alert level:
    // * Allerta < 40: solo basso ambient (volume 0.6), arpeggiatore tense inattivo (volume 0.0).
    // * Allerta 40-80: dissolvenza incrociata (l'ambient sfuma a 0.4, il tense sale a 0.6).
    // * Allerta > 80: arpeggiatore tense al massimo (1.0), basso ambient al minimo (0.1), playback rate del tense accelerato a 1.2x.
    double ambientVol = 0.6;
    double tenseVol = 0.0;
    double tenseRate = 1.0;

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

    try {
      await _bgmAmbientPlayer.setVolume(ambientVol);
      await _bgmTensePlayer.setVolume(tenseVol);
      await _bgmTensePlayer.setPlaybackRate(tenseRate);
    } catch (e) {
      debugPrint("Error mixing stems: $e");
    }
  }

  // SFX — reuse dedicated pool players. Calling stop() before play()
  // ensures the player is in a clean state if the previous SFX hasn't
  // finished yet. This is safe and avoids overlapping the same sound.
  Future<void> _playSfx(AudioPlayer player, String? path, {double volume = 1.0}) async {
    if (!_initialized || !_audioEnabled || path == null) return;
    try {
      await player.stop();
      await player.setVolume(volume);
      await player.play(DeviceFileSource(path));
    } catch (e) {
      debugPrint("Error playing SFX: $e");
    }
  }

  void playClick() => _playSfx(_sfxClickPlayer, _sfxClickPath, volume: 0.25);
  void playAlert() => _playSfx(_sfxAlertPlayer, _sfxAlertPath);
  void playGlitch() => _playSfx(_sfxGlitchPlayer, _sfxGlitchPath);
  void playChime() => _playSfx(_sfxChimePlayer, _sfxChimePath);

  Future<void> dispose() async {
    if (!_initialized) return;
    try {
      await _bgmAmbientPlayer.dispose();
      await _bgmTensePlayer.dispose();
      await _sfxClickPlayer.dispose();
      await _sfxAlertPlayer.dispose();
      await _sfxGlitchPlayer.dispose();
      await _sfxChimePlayer.dispose();
    } catch (e) {
      debugPrint("Error disposing audio players: $e");
    }
    _initialized = false;
  }
}
