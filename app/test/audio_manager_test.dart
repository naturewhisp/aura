import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aura_core/aura_core.dart';
import 'package:aura_app/src/audio/audio_scene.dart';
import 'package:aura_app/src/audio/bgm_player.dart';
import 'package:aura_app/src/audio/audio_scene_machine.dart';
import 'package:aura_app/src/audio/audio_manager.dart';
import 'package:aura_app/src/screens/boot_menu_screen.dart';
import 'package:aura_app/src/state_management/game_controller_notifier.dart';

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
  bool failSetVolumeAfterStop = false;
  bool failSetPlaybackRate = false;
  bool failSetPlaybackRateOnce = false;

  Completer<void>? setVolumeCompleter;
  Completer<void>? stopCompleter;
  Completer<void>? resumeCompleter;

  @override
  Future<void> setSource(String path) async {
    if (isDisposed) throw StateError("Player già rimosso");
    sourcePath = path;
    setSourceCalls++;
  }

  @override
  Future<void> setVolume(double vol) async {
    if (isDisposed) throw StateError("Player già rimosso");
    if (setVolumeCompleter != null) {
      await setVolumeCompleter!.future;
    }
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
    if (failSetPlaybackRateOnce) {
      failSetPlaybackRateOnce = false;
      throw Exception("Errore simulato setPlaybackRate una tantum");
    }
    if (failSetPlaybackRate) throw Exception("Errore simulato setPlaybackRate");
    playbackRate = rate;
  }

  @override
  Future<void> resume() async {
    if (isDisposed) throw StateError("Player già rimosso");
    if (resumeCompleter != null) {
      await resumeCompleter!.future;
    }
    isPlaying = true;
    resumeCalls++;
  }

  @override
  Future<void> stop() async {
    if (isDisposed) throw StateError("Player già rimosso");
    if (stopCompleter != null) {
      await stopCompleter!.future;
    }
    isPlaying = false;
    stopCalls++;
    if (failSetVolumeAfterStop) {
      failSetVolumeOnce = true;
    }
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

    test('Race di Mute durante Finalizzazione: la finalizzazione non riattiva il volume e lascia requestedScene = target, currentScene = precedente, currentTrack = null, isPlaying = false', () async {
      await machine.transitionTo(AudioSceneState.gameAmbient);
      final tensePlayer = backend.players[AudioTrackId.tense]!;

      tensePlayer.setVolumeCompleter = Completer<void>();

      final f1 = machine.transitionTo(AudioSceneState.gameTense);
      
      // Chiamiamo suspendAudio ma non lo attendiamo qui per evitare deadlock
      final fSuspend = machine.suspendAudio();

      tensePlayer.setVolumeCompleter!.complete();
      await f1;
      await fSuspend;

      expect(machine.requestedScene, equals(AudioSceneState.gameTense));
      expect(machine.currentScene, equals(AudioSceneState.gameAmbient));
      expect(machine.currentTrack, isNull);
      expect(machine.isTrackPlaying, isFalse);
      for (final p in backend.players.values) {
        expect(p.isPlaying, isFalse);
      }
    });

    test('Race di Recovery su Transizione Obsoleta: se A fallisce dopo che B è già stata accodata, B non vede sovrascritto requestedScene, ma A ripristina comunque lo stato fisico stabile', () async {
      await machine.transitionTo(AudioSceneState.gameAmbient);
      final ambientPlayer = backend.players[AudioTrackId.ambient]!;
      final tensePlayer = backend.players[AudioTrackId.tense]!;

      tensePlayer.resumeCompleter = Completer<void>();

      final f1 = machine.transitionTo(AudioSceneState.gameTense);
      final f2 = machine.transitionTo(AudioSceneState.victory);

      tensePlayer.failSetVolume = true;
      tensePlayer.resumeCompleter!.complete();
      await f1;

      expect(machine.requestedScene, equals(AudioSceneState.victory));
      expect(tensePlayer.isPlaying, isFalse);
      expect(ambientPlayer.isPlaying, isTrue);

      tensePlayer.failSetVolume = false;
      await f2;
      expect(machine.currentScene, equals(AudioSceneState.victory));
    });

    test('Same-track Condizionale: attivo non aumenta resumeCalls e trackStartTime resta uguale; inattivo chiama resume e aggiorna trackStartTime', () async {
      await machine.transitionTo(AudioSceneState.gameTense);
      final tensePlayer = backend.players[AudioTrackId.tense]!;

      expect(machine.currentScene, equals(AudioSceneState.gameTense));
      final firstResumeCalls = tensePlayer.resumeCalls;
      final firstStartTime = machine.trackStartTime;

      await machine.transitionTo(AudioSceneState.defeat);
      expect(tensePlayer.resumeCalls, equals(firstResumeCalls));
      expect(machine.trackStartTime, equals(firstStartTime));

      // Simuliamo l'inattività fisica del player ma manteniamo same-track
      machine.isTrackPlayingForTesting = false;
      machine.currentTrackForTesting = AudioTrackId.tense;

      await machine.transitionTo(AudioSceneState.gameTense, force: true);
      expect(tensePlayer.resumeCalls, greaterThan(firstResumeCalls));
      expect(machine.trackStartTime, isNot(equals(firstStartTime)));
    });

    test('Recovery dopo Sospensione Fallito: se la macchina era sospesa, fallisce la transizione al resume, gameAmbient viene ripristinato fisicamente (con resume) e trackStartTime viene ricreato', () async {
      await machine.transitionTo(AudioSceneState.gameAmbient);
      final ambientPlayer = backend.players[AudioTrackId.ambient]!;
      expect(machine.currentScene, equals(AudioSceneState.gameAmbient));
      final originalStartTime = machine.trackStartTime;

      await machine.suspendAudio();
      expect(ambientPlayer.isPlaying, isFalse);

      ambientPlayer.failSetPlaybackRateOnce = true;
      await machine.resumeAudio();

      expect(machine.currentScene, equals(AudioSceneState.gameAmbient));
      expect(ambientPlayer.isPlaying, isTrue);
      expect(machine.trackStartTime, isNot(equals(originalStartTime)));
    });

    test('Errore prima dello stop della traccia stabile: trackStartTime resta invariato', () async {
      await machine.transitionTo(AudioSceneState.gameAmbient);
      final ambientPlayer = backend.players[AudioTrackId.ambient]!;
      final tensePlayer = backend.players[AudioTrackId.tense]!;
      final originalStartTime = machine.trackStartTime;

      tensePlayer.failSetVolume = true;

      await machine.transitionTo(AudioSceneState.gameTense);

      expect(machine.currentScene, equals(AudioSceneState.gameAmbient));
      expect(ambientPlayer.isPlaying, isTrue);
      expect(machine.trackStartTime, equals(originalStartTime));
    });

    test('Errore dopo lo stop della traccia stabile: il recovery esegue resume e assegna un nuovo trackStartTime', () async {
      await machine.transitionTo(AudioSceneState.gameAmbient);
      final ambientPlayer = backend.players[AudioTrackId.ambient]!;
      final originalStartTime = machine.trackStartTime;

      // Facciamo fallire setVolume sul player uscente dopo lo stop
      ambientPlayer.failSetVolumeAfterStop = true;

      await machine.transitionTo(AudioSceneState.gameTense);

      expect(machine.currentScene, equals(AudioSceneState.gameAmbient));
      expect(ambientPlayer.isPlaying, isTrue);
      expect(machine.trackStartTime, isNot(equals(originalStartTime)));
    });

    test('Stop riuscito ma setVolume() fallito nel crossfade: recovery ripristina la traccia stabile precedente', () async {
      await machine.transitionTo(AudioSceneState.gameAmbient);
      final ambientPlayer = backend.players[AudioTrackId.ambient]!;

      // Fallisce solo la prima volta sul player uscente dopo lo stop
      ambientPlayer.failSetVolumeAfterStop = true;

      await machine.transitionTo(AudioSceneState.gameTense);

      expect(machine.currentScene, equals(AudioSceneState.gameAmbient));
      expect(ambientPlayer.isPlaying, isTrue);
    });

    test('Cancellazione Generazionale Pre-Confine: la prima transizione obsoleta stabilizza fisicamente lo stato prima della successiva', () async {
      await machine.transitionTo(AudioSceneState.gameAmbient);
      final ambientPlayer = backend.players[AudioTrackId.ambient]!;
      final tensePlayer = backend.players[AudioTrackId.tense]!;
      final epicPlayer = backend.players[AudioTrackId.epic]!;

      tensePlayer.setVolumeCompleter = Completer<void>();

      final f1 = machine.transitionTo(AudioSceneState.gameTense);
      await Future.delayed(const Duration(milliseconds: 50));

      final f2 = machine.transitionTo(AudioSceneState.breakthrough);

      tensePlayer.setVolumeCompleter!.complete();
      await f1;

      expect(tensePlayer.isPlaying, isFalse);
      expect(ambientPlayer.isPlaying, isTrue);
      expect(machine.requestedScene, equals(AudioSceneState.breakthrough));

      await f2;
      expect(machine.currentScene, equals(AudioSceneState.breakthrough));
      expect(epicPlayer.isPlaying, isTrue);
    });

    test('Dispose durante recovery di transizione obsoleta spegne tutto e non committa', () async {
      await machine.transitionTo(AudioSceneState.gameAmbient);
      final ambientPlayer = backend.players[AudioTrackId.ambient]!;
      final tensePlayer = backend.players[AudioTrackId.tense]!;

      ambientPlayer.setVolumeCompleter = Completer<void>();
      tensePlayer.failSetVolumeOnce = true;

      final f1 = machine.transitionTo(AudioSceneState.gameTense);
      await Future.delayed(const Duration(milliseconds: 50));

      final f2 = machine.dispose();

      ambientPlayer.setVolumeCompleter!.complete();
      await f1;
      await f2;

      expect(machine.currentScene, isNull);
      expect(machine.currentTrack, isNull);
      expect(machine.isTrackPlaying, isFalse);
      for (final p in backend.players.values) {
        expect(p.isPlaying, isFalse);
      }
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

      await manager.dispose();

      expect(() => manager.initialize('test_dir'), throwsStateError);
    });

    test('Due pendingScene prima di initialize: viene applicata solo l’ultima', () async {
      final manager = AudioManager();
      
      await manager.transitionTo(AudioSceneState.gameAmbient);
      await manager.transitionTo(AudioSceneState.breakthrough);

      await manager.initialize('test_dir');

      expect(manager.machine.currentScene, AudioSceneState.breakthrough);
    });

    test('PendingScene con audio inizialmente muted: nessun player parte', () async {
      final manager = AudioManager();
      await manager.transitionTo(AudioSceneState.gameAmbient);

      await manager.initialize('test_dir', audioEnabled: false);

      expect(manager.audioEnabled, isFalse);
      expect(manager.machine.currentScene, isNull);
      expect(manager.machine.requestedScene, AudioSceneState.gameAmbient);
      expect(manager.machine.isTrackPlaying, isFalse);
    });

    test('dispose() SFX Stato Esplicito: dispose non accede agli SFX se _sfxPlayersCreated è false', () async {
      final manager = AudioManager();
      manager.resetForTesting();
      await manager.initialize('test_dir');
      
      await manager.dispose();
      expect(manager.isInitialized, isFalse);
    });
  });

  group('AudioManager - BootMenuScreen Rendering Integration', () {
    testWidgets('BootMenuScreen montata senza pre-inizializzare AudioManager non crasha', (WidgetTester tester) async {
      AudioManager().resetForTesting();

      final mockApiBridge = MockInferenceBridge(
        mockStructuredResponse: const {},
        mockTextResponse: '',
      );
      final initialState = GameState.initial(
        sessionId: 'test-session',
        aiIdentityId: 'panopticon',
        targetObjectiveId: 'tabula_rasa',
      );
      final notifier = GameControllerNotifier(
        bridge: mockApiBridge,
        initialState: initialState,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GameControllerProvider(
              notifier: notifier,
              child: BootMenuScreen(notifier: notifier),
            ),
          ),
        ),
      );

      expect(find.byType(BootMenuScreen), findsOneWidget);
    });
  });
}
