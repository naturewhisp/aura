import 'package:meta/meta.dart';

/// Identificatori univoci per le tracce fisiche WAV utilizzate in A.U.R.A.
enum AudioTrackId {
  /// Il tema principale chiptune incalzante ed epico.
  main,
  /// La traccia rilassante, atmosferica e analogica.
  ambient,
  /// La traccia rapida per stati di allerta e tensione.
  tense,
  /// La traccia epica e trionfale della sequenza finale.
  epic,
}

/// Stati semantici della macchina a stati audio.
enum AudioSceneState {
  /// Stato iniziale di boot.
  boot,
  /// Schermata del menu principale, impostazioni e replay.
  menu,
  /// Partita in corso con allerta controllata (bassa).
  gameAmbient,
  /// Partita in corso con tensione elevata (allerta >= 40 o deception attiva).
  gameTense,
  /// PANOPTICON vicino al cedimento (soglie numeriche di vittoria pronte, ma non ancora vinte).
  breakthrough,
  /// Sequenza finale di vittoria.
  victory,
  /// Lockout e sequenza di sconfitta.
  defeat,
}

/// Profilo configurativo e dichiarativo associato a ciascun [AudioSceneState].
@immutable
class AudioSceneProfile {
  /// La traccia fisica BGM dominante associata allo stato.
  final AudioTrackId track;

  /// Il volume target stabile per la riproduzione (tra 0.0 e 1.0).
  final double volume;

  /// Il playback rate della traccia (ad esempio 1.2 per accelerare).
  final double playbackRate;

  /// I BPM nominali associati a questa scena musicale (utilizzati per animazioni UI).
  final double bpm;

  /// La durata della transizione di crossfade o di rampa di volume verso questo stato.
  final Duration transitionDuration;

  /// Costruttore costante per definire il profilo di una scena audio.
  const AudioSceneProfile({
    required this.track,
    required this.volume,
    this.playbackRate = 1.0,
    required this.bpm,
    this.transitionDuration = const Duration(milliseconds: 400),
  });
}

/// Mappa dichiarativa centralizzata che associa ogni [AudioSceneState] al suo rispettivo [AudioSceneProfile].
const Map<AudioSceneState, AudioSceneProfile> audioSceneProfiles = {
  AudioSceneState.boot: AudioSceneProfile(
    track: AudioTrackId.main,
    volume: 0.30,
    bpm: 120.0,
    transitionDuration: Duration(milliseconds: 400),
  ),
  AudioSceneState.menu: AudioSceneProfile(
    track: AudioTrackId.main,
    volume: 0.45,
    bpm: 120.0,
    transitionDuration: Duration(milliseconds: 500),
  ),
  AudioSceneState.gameAmbient: AudioSceneProfile(
    track: AudioTrackId.ambient,
    volume: 0.32,
    bpm: 60.0,
    transitionDuration: Duration(milliseconds: 400),
  ),
  AudioSceneState.gameTense: AudioSceneProfile(
    track: AudioTrackId.tense,
    volume: 0.55,
    bpm: 120.0,
    transitionDuration: Duration(milliseconds: 400),
  ),
  AudioSceneState.breakthrough: AudioSceneProfile(
    track: AudioTrackId.epic,
    volume: 0.30,
    bpm: 120.0,
    transitionDuration: Duration(milliseconds: 400),
  ),
  AudioSceneState.victory: AudioSceneProfile(
    track: AudioTrackId.epic,
    volume: 0.68,
    bpm: 120.0,
    transitionDuration: Duration(milliseconds: 700), // ramp volume più dolce
  ),
  AudioSceneState.defeat: AudioSceneProfile(
    track: AudioTrackId.tense,
    volume: 0.90,
    playbackRate: 1.20,
    bpm: 144.0,
    transitionDuration: Duration(milliseconds: 250), // fade in rapido per l'allarme
  ),
};
