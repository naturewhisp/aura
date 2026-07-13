import 'audio_scene.dart';

/// Interfaccia astratta per il controllo di una singola traccia fisica di sottofondo.
///
/// Consente di disaccoppiare l'esecutore musicale nativo ([AudioPlayer] di audioplayers)
/// dalla macchina a stati, facilitando l'utilizzo di mock o fake backend durante i test unitari.
abstract interface class BgmPlayer {
  /// Imposta il percorso del file audio su disco.
  Future<void> setSource(String path);

  /// Imposta il volume lineare di riproduzione (da 0.0 a 1.0).
  Future<void> setVolume(double volume);

  /// Imposta la velocità di riproduzione (playback rate).
  Future<void> setPlaybackRate(double rate);

  /// Avvia o riprende la riproduzione in loop.
  Future<void> resume();

  /// Ferma temporaneamente la riproduzione e azzera la posizione.
  Future<void> stop();

  /// Rilascia le risorse allocate a basso livello per questo player.
  Future<void> dispose();
}

/// Backend per la gestione e l'accesso ai player delle tracce musicali.
abstract interface class AudioPlaybackBackend {
  /// Restituisce il player associato alla traccia specificata.
  BgmPlayer playerFor(AudioTrackId track);
}

/// Implementazione no-op (vuota) di [BgmPlayer] per evitare chiamate native nei test.
class NoOpBgmPlayer implements BgmPlayer {
  @override
  Future<void> setSource(String path) async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> setPlaybackRate(double rate) async {}
  @override
  Future<void> resume() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

/// Implementazione no-op (vuota) di [AudioPlaybackBackend] per evitare chiamate native nei test.
class NoOpAudioPlaybackBackend implements AudioPlaybackBackend {
  final _player = NoOpBgmPlayer();

  @override
  BgmPlayer playerFor(AudioTrackId track) => _player;
}
