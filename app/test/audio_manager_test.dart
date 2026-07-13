import 'package:flutter_test/flutter_test.dart';
import 'package:aura_app/src/audio/audio_scene.dart';
import 'package:aura_app/src/audio/bgm_player.dart';
import 'package:aura_app/src/audio/audio_scene_machine.dart';

class FakeBgmPlayer implements BgmPlayer {
  String? sourcePath;
  double volume = 0.0;
  double playbackRate = 1.0;
  int setSourceCalls = 0;
  int resumeCalls = 0;
  int stopCalls = 0;
  bool isPlaying = false;
  bool isDisposed = false;

  @override
  Future<void> setSource(String path) async {
    sourcePath = path;
    setSourceCalls++;
  }

  @override
  Future<void> setVolume(double vol) async {
    volume = vol;
  }

  @override
  Future<void> setPlaybackRate(double rate) async {
    playbackRate = rate;
  }

  @override
  Future<void> resume() async {
    isPlaying = true;
    resumeCalls++;
  }

  @override
  Future<void> stop() async {
    isPlaying = false;
    stopCalls++;
  }

  @override
  Future<void> dispose() async {
    isDisposed = true;
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
  group('AudioSceneMachine - Test della macchina a stati e transizioni', () {
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
      expect(mainPlayer.volume, closeTo(0.30, 0.01)); // boot profile volume
      expect(mainPlayer.sourcePath, '/path/bgm_main.wav');
    });

    test('Richiesta identica alla scena richiesta (non force) non riavvia e non fa nulla', () async {
      await machine.transitionTo(AudioSceneState.menu);
      final menuPlayer = backend.players[AudioTrackId.main]!;
      final int initialResumeCalls = menuPlayer.resumeCalls;

      // Richiesta duplicata
      await machine.transitionTo(AudioSceneState.menu);

      // Le chiamate resume e setSource non devono essere aumentate
      expect(menuPlayer.resumeCalls, initialResumeCalls);
    });

    test('Transizione same-track (es. breakthrough -> victory su traccia epic) non esegue stop/resume e preserva trackStartTime', () async {
      await machine.transitionTo(AudioSceneState.breakthrough);
      final epicPlayer = backend.players[AudioTrackId.epic]!;
      
      expect(epicPlayer.isPlaying, isTrue);
      expect(epicPlayer.volume, closeTo(0.30, 0.01));
      final int firstResumeCalls = epicPlayer.resumeCalls;
      final int firstSetSourceCalls = epicPlayer.setSourceCalls;
      final DateTime firstStartTime = machine.trackStartTime;

      // transizione verso victory (same-track su epic)
      await machine.transitionTo(AudioSceneState.victory);

      expect(machine.currentScene, AudioSceneState.victory);
      expect(machine.currentTrack, AudioTrackId.epic);
      expect(epicPlayer.volume, closeTo(0.68, 0.01));

      // Nessuna chiamata stop/resume aggiuntiva o re-impostazione sorgente
      expect(epicPlayer.resumeCalls, firstResumeCalls);
      expect(epicPlayer.setSourceCalls, firstSetSourceCalls);
      expect(machine.trackStartTime, firstStartTime);
    });

    test('Annullamento logico in corsa: una transizione obsoleta non imposta lo stato finale ed il nuovo fade parte dal volume corrente', () async {
      // Avvia ambient
      await machine.transitionTo(AudioSceneState.gameAmbient);
      final ambientPlayer = backend.players[AudioTrackId.ambient]!;
      expect(ambientPlayer.volume, closeTo(0.32, 0.01));

      // Eseguiamo due transizioni veloci per forzare l'invalidazione della prima
      final f1 = machine.transitionTo(AudioSceneState.gameTense);
      // Immediatamente dopo, richiediamo breakthrough
      final f2 = machine.transitionTo(AudioSceneState.breakthrough);

      await Future.wait([f1, f2]);

      // Alla fine deve trionfare breakthrough (traccia epic)
      expect(machine.currentScene, AudioSceneState.breakthrough);
      expect(machine.currentTrack, AudioTrackId.epic);

      final tensePlayer = backend.players[AudioTrackId.tense]!;
      // Tense Player non deve essere attivo o deve essere stoppato dal cleanup
      expect(tensePlayer.isPlaying, isFalse);
      expect(tensePlayer.volume, 0.0);

      final epicPlayer = backend.players[AudioTrackId.epic]!;
      expect(epicPlayer.isPlaying, isTrue);
      expect(epicPlayer.volume, closeTo(0.30, 0.01));
    });

    test('Disable (suspendAudio) ferma i player ma conserva la scena richiesta, ed Enable riavvia la riproduzione', () async {
      await machine.transitionTo(AudioSceneState.gameAmbient);
      final ambientPlayer = backend.players[AudioTrackId.ambient]!;
      expect(ambientPlayer.isPlaying, isTrue);

      // Disabilitazione
      await machine.suspendAudio();
      expect(ambientPlayer.isPlaying, isFalse);
      expect(machine.isTrackPlaying, isFalse);
      expect(machine.currentTrack, isNull);
      expect(machine.requestedScene, AudioSceneState.gameAmbient); // preservata

      // Riabilitazione
      await machine.resumeAudio();
      expect(ambientPlayer.isPlaying, isTrue);
      expect(machine.isTrackPlaying, isTrue);
      expect(machine.currentTrack, AudioTrackId.ambient);
      expect(machine.currentScene, AudioSceneState.gameAmbient);
    });

    test('stopBgm resetta lo stato logico e ferma fisicamente i player', () async {
      await machine.transitionTo(AudioSceneState.gameAmbient);
      final ambientPlayer = backend.players[AudioTrackId.ambient]!;
      expect(ambientPlayer.isPlaying, isTrue);

      await machine.stopBgm();
      expect(ambientPlayer.isPlaying, isFalse);
      expect(machine.currentScene, isNull);
      expect(machine.currentTrack, isNull);
      expect(machine.isTrackPlaying, isFalse);
    });
  });
}
