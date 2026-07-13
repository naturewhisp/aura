import 'package:flutter_test/flutter_test.dart';
import 'package:aura_app/src/audio/audio_scene.dart';
import 'package:aura_app/src/audio/bgm_player.dart';
import 'package:aura_app/src/audio/audio_scene_machine.dart';
import 'package:aura_app/src/audio/audio_manager.dart';

class FakeBgmPlayer implements BgmPlayer {
  String? sourcePath;
  double volume = 0.0;
  double playbackRate = 1.0;
  int setSourceCalls = 0;
  int resumeCalls = 0;
  int stopCalls = 0;
  int disposeCalls = 0;
  bool isPlaying = false;
  bool isDisposed = false;

  bool failSetVolume = false;
  bool failSetVolumeOnce = false;
  bool failSetPlaybackRate = false;

  @override
  Future<void> setSource(String path) async {
    if (isDisposed) throw StateError("Player già rimosso");
    sourcePath = path;
    setSourceCalls++;
  }

  @override
  Future<void> setVolume(double vol) async {
    if (isDisposed) throw StateError("Player già rimosso");
    if (failSetVolumeOnce) {
      failSetVolumeOnce = false;
      throw Exception("Errore simulato setVolume una tantum");
    }
    if (failSetVolume) throw Exception("Errore simulato setVolume");
    volume = vol;
  }

  @override
  Future<void> setPlaybackRate(double rate) async {
    if (isDisposed) throw StateError("Player già rimosso");
    if (failSetPlaybackRate) throw Exception("Errore simulato setPlaybackRate");
    playbackRate = rate;
  }

  @override
  Future<void> resume() async {
    if (isDisposed) throw StateError("Player già rimosso");
    isPlaying = true;
    resumeCalls++;
  }

  @override
  Future<void> stop() async {
    if (isDisposed) throw StateError("Player già rimosso");
    isPlaying = false;
    stopCalls++;
  }

  @override
  Future<void> dispose() async {
    isDisposed = true;
    disposeCalls++;
  }
}

class FakeAudioPlaybackBackend implements AudioPlaybackBackend {
  final Map<AudioTrackId, FakeBgmPlayer> players = {
    AudioTrackId.main: FakeBgmPlayer(),
    AudioTrackId.ambient: FakeBgmPlayer(),
    AudioTrackId.tense: FakeBgmPlayer(),
    AudioTrackId.epic: FakeBgmPlayer(),
  };

  @override
  BgmPlayer playerFor(AudioTrackId track) {
    return players[track]!;
  }
}

void main() {
  group('AudioSceneMachine - Test Hardening, Mute, Recovery e Race', () {
    late FakeAudioPlaybackBackend backend;
    late Map<AudioTrackId, String> trackPaths;
    late AudioSceneMachine machine;

    setUp(() {
      backend = FakeAudioPlaybackBackend();
      trackPaths = {
        AudioTrackId.main: '/path/bgm_main.wav',
        AudioTrackId.ambient: '/path/bgm_ambient.wav',
        AudioTrackId.tense: '/path/bgm_tense.wav',
        AudioTrackId.epic: '/path/bgm_epic.wav',
      };
      machine = AudioSceneMachine(
        backend: backend,
        trackPaths: trackPaths,
      );
    });

    test('Stato iniziale nullable e prima richiesta boot che avvia realmente main', () async {
      expect(machine.currentScene, isNull);
      expect(machine.requestedScene, isNull);
      expect(machine.currentTrack, isNull);
      expect(machine.isTrackPlaying, isFalse);

      await machine.transitionTo(AudioSceneState.boot);

      expect(machine.currentScene, AudioSceneState.boot);
      expect(machine.requestedScene, AudioSceneState.boot);
      expect(machine.currentTrack, AudioTrackId.main);
      expect(machine.isTrackPlaying, isTrue);

      final mainPlayer = backend.players[AudioTrackId.main]!;
      expect(mainPlayer.isPlaying, isTrue);
      expect(mainPlayer.volume, closeTo(0.30, 0.01));
    });

    test('Richiesta identica alla scena richiesta (non force) non riavvia e non fa nulla', () async {
      await machine.transitionTo(AudioSceneState.menu);
      final menuPlayer = backend.players[AudioTrackId.main]!;
      final int initialResumeCalls = menuPlayer.resumeCalls;

      await machine.transitionTo(AudioSceneState.menu);
      expect(menuPlayer.resumeCalls, initialResumeCalls);
    });

    test('Richiesta scena durante mute non effettua nessuna chiamata fisica', () async {
      await machine.suspendAudio();
      await machine.transitionTo(AudioSceneState.gameAmbient);

      expect(machine.requestedScene, AudioSceneState.gameAmbient);
      expect(machine.currentScene, isNull);
      expect(machine.currentTrack, isNull);
      expect(machine.isTrackPlaying, isFalse);

      final ambientPlayer = backend.players[AudioTrackId.ambient]!;
      expect(ambientPlayer.isPlaying, isFalse);
      expect(ambientPlayer.resumeCalls, 0);
    });

    test('Dopo resume parte l’ultima scena richiesta durante mute', () async {
      await machine.suspendAudio();
      await machine.transitionTo(AudioSceneState.gameAmbient);
      await machine.transitionTo(AudioSceneState.breakthrough);

      expect(machine.requestedScene, AudioSceneState.breakthrough);

      await machine.resumeAudio();

      expect(machine.currentScene, AudioSceneState.breakthrough);
      expect(machine.currentTrack, AudioTrackId.epic);
      expect(machine.isTrackPlaying, isTrue);

      final epicPlayer = backend.players[AudioTrackId.epic]!;
      expect(epicPlayer.isPlaying, isTrue);
      expect(epicPlayer.volume, closeTo(0.30, 0.01));
    });

    test('Cancellazione ambient -> tense -> ambient lascia tense fermata e a volume zero', () async {
      await machine.transitionTo(AudioSceneState.gameAmbient);
      final ambientPlayer = backend.players[AudioTrackId.ambient]!;
      final tensePlayer = backend.players[AudioTrackId.tense]!;

      // Avvia la transizione per tense, ma senza attenderla (cancellazione veloce)
      final f1 = machine.transitionTo(AudioSceneState.gameTense);
      // Immediatamente dopo, ritorna ad ambient
      final f2 = machine.transitionTo(AudioSceneState.gameAmbient);

      await Future.wait([f1, f2]);

      expect(machine.currentScene, AudioSceneState.gameAmbient);
      expect(machine.currentTrack, AudioTrackId.ambient);
      expect(ambientPlayer.isPlaying, isTrue);

      // Tense Player deve essere stoppato e a volume 0.0
      expect(tensePlayer.isPlaying, isFalse);
      expect(tensePlayer.volume, 0.0);
    });

    test('Ogni transizione completata lascia esattamente un player attivo', () async {
      await machine.transitionTo(AudioSceneState.gameAmbient);
      await machine.transitionTo(AudioSceneState.gameTense);

      int activePlayers = 0;
      for (final p in backend.players.values) {
        if (p.isPlaying) activePlayers++;
      }
      expect(activePlayers, equals(1));
      expect(backend.players[AudioTrackId.tense]!.isPlaying, isTrue);
    });

    test('gameTense -> defeat applica rate 1.20 senza stop/resume', () async {
      await machine.transitionTo(AudioSceneState.gameTense);
      final tensePlayer = backend.players[AudioTrackId.tense]!;
      
      expect(tensePlayer.isPlaying, isTrue);
      expect(tensePlayer.playbackRate, equals(1.0));
      final resumeCallsBefore = tensePlayer.resumeCalls;

      await machine.transitionTo(AudioSceneState.defeat);

      expect(machine.currentScene, AudioSceneState.defeat);
      expect(tensePlayer.playbackRate, equals(1.20));
      expect(tensePlayer.resumeCalls, resumeCallsBefore); // non fermato
    });

    test('Fallimento same-track ripristina volume e playback rate precedenti', () async {
      await machine.transitionTo(AudioSceneState.gameTense);
      final tensePlayer = backend.players[AudioTrackId.tense]!;
      
      expect(machine.currentScene, AudioSceneState.gameTense);
      expect(tensePlayer.volume, closeTo(0.55, 0.01));
      expect(tensePlayer.playbackRate, equals(1.0));

      // Simuliamo fallimento del volume sul same-track verso defeat una sola volta
      tensePlayer.failSetVolumeOnce = true;

      await machine.transitionTo(AudioSceneState.defeat);

      // Lo stato deve rimanere gameTense
      expect(machine.currentScene, AudioSceneState.gameTense);
      expect(tensePlayer.volume, closeTo(0.55, 0.01)); // Ripristinato
      expect(tensePlayer.playbackRate, equals(1.0)); // Ripristinato
    });

    test('Fallimento crossfade rende il target nuovamente richiedibile', () async {
      await machine.transitionTo(AudioSceneState.gameAmbient);
      final epicPlayer = backend.players[AudioTrackId.epic]!;

      // Simuliamo errore setPlaybackRate su epic
      epicPlayer.failSetPlaybackRate = true;

      await machine.transitionTo(AudioSceneState.breakthrough);

      // Scena stabile deve rimanere gameAmbient
      expect(machine.currentScene, AudioSceneState.gameAmbient);
      expect(machine.requestedScene, AudioSceneState.gameAmbient); // resettata per retry

      // Togliamo l'errore e richiediamo di nuovo breakthrough
      epicPlayer.failSetPlaybackRate = false;
      await machine.transitionTo(AudioSceneState.breakthrough);

      expect(machine.currentScene, AudioSceneState.breakthrough);
    });

    test('Suspend durante fade impedisce qualsiasi volume finale successivo', () async {
      // Inizia transizione a gameAmbient
      final f1 = machine.transitionTo(AudioSceneState.gameAmbient);
      // Sospende immediatamente
      await machine.suspendAudio();
      await f1;

      final ambientPlayer = backend.players[AudioTrackId.ambient]!;
      expect(ambientPlayer.isPlaying, isFalse);
      expect(ambientPlayer.volume, equals(0.0));
      expect(machine.isTrackPlaying, isFalse);
    });

    test('Resume seguito immediatamente da suspend termina sospeso', () async {
      await machine.transitionTo(AudioSceneState.gameAmbient);
      await machine.suspendAudio();

      final f1 = machine.resumeAudio();
      final f2 = machine.suspendAudio();

      await Future.wait([f1, f2]);

      final ambientPlayer = backend.players[AudioTrackId.ambient]!;
      expect(ambientPlayer.isPlaying, isFalse);
      expect(machine.isTrackPlaying, isFalse);
    });

    test('Suspend seguito immediatamente da resume termina attivo', () async {
      await machine.transitionTo(AudioSceneState.gameAmbient);

      final f1 = machine.suspendAudio();
      final f2 = machine.resumeAudio();

      await Future.wait([f1, f2]);

      final ambientPlayer = backend.players[AudioTrackId.ambient]!;
      expect(ambientPlayer.isPlaying, isTrue);
      expect(machine.isTrackPlaying, isTrue);
    });

    test('Dispose durante fade invalida il fade e rilascia ogni player una sola volta', () async {
      final f1 = machine.transitionTo(AudioSceneState.gameAmbient);
      await machine.dispose();
      await f1;

      for (final p in backend.players.values) {
        expect(p.isDisposed, isTrue);
        expect(p.disposeCalls, equals(1));
      }
    });

    test('Chiamate successive a dispose non accedono al backend', () async {
      await machine.dispose();
      // Seconda chiamata
      await machine.dispose();
      
      for (final p in backend.players.values) {
        expect(p.disposeCalls, equals(1));
      }
    });

    test('currentBpm è 0 quando currentScene esiste ma nessun player è fisicamente attivo', () async {
      await machine.transitionTo(AudioSceneState.gameAmbient);
      expect(machine.currentBpm, closeTo(60.0, 0.01));

      await machine.suspendAudio();
      expect(machine.currentBpm, equals(0.0));
    });
  });

  group('AudioManager - Inizializzazione, Pending Scene, e Mute', () {
    setUp(() async {
      AudioManager().resetForTesting();
    });

    test('AudioManager.dispose è idempotente e blocca inizializzazioni successive seguendo la politica terminale', () async {
      final manager = AudioManager();
      await manager.initialize('test_dir');
      expect(manager.isInitialized, isTrue);

      await manager.dispose();
      expect(manager.isInitialized, isFalse);

      // Successiva chiamata a dispose è sicura
      await manager.dispose();

      // Inizializzazione post-dispose fallisce
      expect(() => manager.initialize('test_dir'), throwsStateError);
    });

    test('Due pendingScene prima di initialize: viene applicata solo l’ultima', () async {
      final manager = AudioManager();
      
      // Chiamiamo transizioni prima dell'inizializzazione
      await manager.transitionTo(AudioSceneState.gameAmbient);
      await manager.transitionTo(AudioSceneState.breakthrough);

      await manager.initialize('test_dir');

      expect(manager.machine.currentScene, AudioSceneState.breakthrough);
    });

    test('PendingScene con audio inizialmente muted: nessun player parte', () async {
      final manager = AudioManager();
      await manager.transitionTo(AudioSceneState.gameAmbient);

      // Inizializza con audio disabilitato
      await manager.initialize('test_dir', audioEnabled: false);

      expect(manager.audioEnabled, isFalse);
      expect(manager.machine.currentScene, isNull);
      expect(manager.machine.requestedScene, AudioSceneState.gameAmbient);
      expect(manager.machine.isTrackPlaying, isFalse);
    });
  });
}
