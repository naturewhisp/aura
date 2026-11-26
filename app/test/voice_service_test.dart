import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:aura_app/src/speech/voice_service.dart';
import 'package:aura_core/aura_core.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeEngine implements SpeechEngine {
  final List<String> requests = [];
  final List<double> speeds = [];
  bool failInit = false;
  int failAt = -1;
  bool disposed = false;
  int initCalls = 0;

  @override
  String get id => 'fake';
  @override
  bool get isReady => initCalls > 0 && !disposed;
  @override
  Future<void> initialize() async {
    initCalls++;
    if (failInit) {
      throw const SpeechEngineException(
          SpeechEngineFailureCode.assetMissing, 'mancante');
    }
  }

  @override
  Future<SpeechAudio> synthesize(
      String phonemes, SpeechVoiceRequest request) async {
    requests.add(phonemes);
    speeds.add(request.speed);
    if (requests.length - 1 == failAt) {
      throw const SpeechEngineException(
          SpeechEngineFailureCode.synthesisFailed, 'errore');
    }
    return SpeechAudio(
        samples: Float32List(2400)..fillRange(0, 2400, 0.1), sampleRate: 24000);
  }

  @override
  Future<void> dispose() async => disposed = true;
}

class _FakePlayback implements VoicePlaybackBackend {
  final List<Uint8List> played = [];
  Completer<void>? current;
  bool holdPlayback = false;
  int stops = 0;
  bool disposed = false;

  @override
  Future<void> play(Uint8List wav) {
    played.add(wav);
    if (!holdPlayback) return Future.value();
    current = Completer<void>();
    return current!.future;
  }

  @override
  Future<void> stop() async {
    stops++;
    final c = current;
    current = null;
    if (c != null && !c.isCompleted) c.complete();
  }

  @override
  Future<void> dispose() async => disposed = true;
}

void main() {
  late _FakeEngine engine;
  late _FakePlayback playback;
  late List<bool> ducking;
  late bool allowed;

  final profile = VoiceProfile(
    identityId: 'panopticon',
    voiceFile: 'im_nicola.bin',
    sentencePauseMs: 100,
    alertRules: const [VoiceAlertRule(minAlert: 70, speedFactor: 1.2)],
  );

  VoiceService service({bool available = true}) => VoiceService(
        engine: engine,
        playback: playback,
        profile: profile,
        isAllowed: () => allowed,
        setDucked: (d) async => ducking.add(d),
        assetsAvailable: available,
      );

  setUp(() {
    engine = _FakeEngine();
    playback = _FakePlayback();
    ducking = [];
    allowed = true;
  });

  test('pronuncia i blocchi in ordine, abbassando la musica solo mentre parla',
      () async {
    final v = service();
    await v.speak('Accesso negato. La griglia rimane sigillata.');
    expect(engine.requests, hasLength(2));
    expect(playback.played, hasLength(2));
    expect(ducking, [true, false]);
    expect(v.status.value, VoiceStatus.idle);
  });

  test('pausa tra i blocchi, non dopo l\'ultimo', () async {
    final v = service();
    await v.speak('Primo blocco. Secondo blocco.');
    // 2400 campioni di voce + 100 ms di pausa (2400 campioni), 16 bit, intestazione 44 byte.
    expect(playback.played[0].length, 44 + (2400 + 2400) * 2);
    expect(playback.played[1].length, 44 + 2400 * 2);
  });

  test('velocità dalla regia dell\'allerta', () async {
    await service().speak('Allarme.', cue: null);
    expect(engine.speeds.single, 1.0);
  });

  test('voce non consentita o non disponibile: nessuna sintesi', () async {
    allowed = false;
    await service().speak('Accesso negato.');
    allowed = true;
    await service(available: false).speak('Accesso negato.');
    expect(engine.initCalls, 0);
    expect(playback.played, isEmpty);
    expect(ducking, isEmpty);
  });

  test('avvio del motore fallito: voce non disponibile, nessun errore',
      () async {
    engine.failInit = true;
    final v = service();
    await v.speak('Accesso negato.');
    expect(v.status.value, VoiceStatus.unavailable);
    expect(v.isAvailable, isFalse);
    await v.speak('Ancora.');
    expect(engine.initCalls, 1);
  });

  test('errore di sintesi a metà battuta: si ferma e rilascia la musica',
      () async {
    engine.failAt = 1;
    final v = service();
    await v.speak('Uno. Due. Tre.');
    expect(playback.played, hasLength(1));
    expect(ducking.last, isFalse);
    expect(v.status.value, VoiceStatus.idle);
  });

  test('stop durante la riproduzione interrompe la battuta', () async {
    playback.holdPlayback = true;
    final v = service();
    final speaking = v.speak('Uno. Due. Tre.');
    await pumpEventQueue();
    expect(v.status.value, VoiceStatus.speaking);
    await v.stop();
    await speaking;
    expect(playback.played, hasLength(1));
    expect(ducking.last, isFalse);
    expect(v.status.value, VoiceStatus.idle);
  });

  test('una nuova battuta interrompe la precedente', () async {
    playback.holdPlayback = true;
    final v = service();
    final first = v.speak('Vecchia uno. Vecchia due. Vecchia tre.');
    await pumpEventQueue();
    final second = v.speak('Nuova.');
    await pumpEventQueue();
    playback.current?.complete();
    await Future.wait([first, second]);
    expect(playback.played, hasLength(2),
        reason: 'un blocco vecchio e quello nuovo');
    expect(ducking.last, isFalse);
  });

  test('rilascio single-flight di motore e riproduzione', () async {
    final v = service();
    final d1 = v.dispose();
    expect(identical(d1, v.dispose()), isTrue);
    await d1;
    expect(engine.disposed, isTrue);
    expect(playback.disposed, isTrue);
    await v.speak('Dopo il rilascio.');
    expect(playback.played, isEmpty);
  });

  group('VoiceAssetLocation', () {
    test('AURA_SPEECH_DIR ha precedenza sulla cartella dell\'eseguibile', () {
      final sep = Platform.pathSeparator;
      expect(
          VoiceAssetLocation.resolve(
              environment: const {'AURA_SPEECH_DIR': 'X'}).directory,
          'X');
      final exe = '${Directory.systemTemp.path}${sep}aura_app.exe';
      expect(
          VoiceAssetLocation.resolve(environment: const {}, executablePath: exe)
              .directory,
          '${Directory.systemTemp.path}${sep}speech');
    });

    test('completa solo con modello, voce e libreria', () {
      final dir = Directory.systemTemp.createTempSync('aura_voce_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final loc = VoiceAssetLocation(dir.path);
      expect(loc.isComplete(profile), isFalse);
      final f = loc.filesFor(profile);
      for (final p in [f.modelPath, f.voicePath, f.onnxRuntimeLibraryPath]) {
        File(p)
          ..parent.createSync(recursive: true)
          ..writeAsBytesSync([0]);
      }
      expect(loc.isComplete(profile), isTrue);
    });
  });
}
