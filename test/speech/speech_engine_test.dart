import 'dart:io';
import 'dart:typed_data';

import 'package:aura_core/aura_offline.dart';
import 'package:test/test.dart';

void main() {
  group('SpeechAudio e SpeechVoiceRequest', () {
    test('durata calcolata dai campioni', () {
      final a = SpeechAudio(samples: Float32List(36000), sampleRate: 24000);
      expect(a.duration, const Duration(milliseconds: 1500));
      expect(SpeechAudio.silent().isEmpty, isTrue);
    });

    test('valori non validi rifiutati', () {
      expect(() => SpeechAudio(samples: Float32List(1), sampleRate: 0),
          throwsArgumentError);
      expect(() => SpeechVoiceRequest(speed: 0.1), throwsArgumentError);
      expect(() => SpeechVoiceRequest(speed: double.nan), throwsArgumentError);
    });

    test('toString delle eccezioni senza causa', () {
      const e = SpeechEngineException(
        SpeechEngineFailureCode.assetMissing,
        'File della voce mancante: modello.',
        cause: 'C:\percorso\segreto',
      );
      expect(e.toString(), isNot(contains('segreto')));
      expect(e.toString(), contains('assetMissing'));
    });
  });

  group('SilentSpeechEngine', () {
    test('restituisce audio vuoto e rifiuta dopo il rilascio', () async {
      final e = SilentSpeechEngine();
      await e.initialize();
      expect((await e.synthesize('a', SpeechVoiceRequest())).isEmpty, isTrue);
      await e.dispose();
      expect(e.isReady, isFalse);
      await expectLater(
        e.synthesize('a', SpeechVoiceRequest()),
        throwsA(isA<SpeechEngineException>().having(
            (x) => x.code, 'code', SpeechEngineFailureCode.invalidState)),
      );
    });
  });

  group('encodePcm16Wav', () {
    test('intestazione e campioni', () {
      final bytes = encodePcm16Wav(
        SpeechAudio(
            samples: Float32List.fromList([0, 1, -1, 2, double.nan]),
            sampleRate: 24000),
      );
      final d = ByteData.sublistView(bytes);
      expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
      expect(d.getUint32(24, Endian.little), 24000);
      expect(d.getUint32(40, Endian.little), 10);
      expect(
          [for (var i = 0; i < 5; i++) d.getInt16(44 + i * 2, Endian.little)],
          [0, 32767, -32767, 32767, 0]);
    });
  });

  group('KokoroTokenizer', () {
    test('aggiunge i bordi e scarta i simboli sconosciuti', () {
      final t = KokoroTokenizer.tokenize('pˈɔrta<');
      expect(t.ids.first, 0);
      expect(t.ids.last, 0);
      expect(t.symbolCount, 6);
      expect(t.droppedSymbols, 1);
    });

    test('rifiuta blocchi vuoti o troppo lunghi', () {
      expect(() => KokoroTokenizer.tokenize('<>'),
          throwsA(isA<SpeechEngineException>()));
      expect(
        () => KokoroTokenizer.tokenize('a' * (KokoroTokenizer.maxSymbols + 1)),
        throwsA(isA<SpeechEngineException>().having(
            (x) => x.code, 'code', SpeechEngineFailureCode.invalidRequest)),
      );
      expect(
          KokoroTokenizer.tokenize('a' * KokoroTokenizer.maxSymbols)
              .symbolCount,
          KokoroTokenizer.maxSymbols);
    });

    test('copre tutti i simboli prodotti dalla fonetica italiana', () {
      final p = ItalianPhonemizer().transcribe(
        'Escalation rilevata: Panopticon ha sospeso dodici canali, analizzare la zona e la porta.',
      );
      expect(KokoroTokenizer.tokenize(p).droppedSymbols, 0);
    });
  });

  group('KokoroVoiceStyle', () {
    Uint8List rows(int n) {
      final f = Float32List(n * 256);
      for (var i = 0; i < f.length; i++) {
        f[i] = i / f.length;
      }
      return f.buffer.asUint8List();
    }

    test('sceglie la riga per lunghezza e la limita', () {
      final v = KokoroVoiceStyle.fromBytes(rows(3));
      expect(v.rowCount, 3);
      expect(v.rowFor(1).first, 0);
      expect(v.rowFor(2).first, closeTo(256 / 768, 1e-6));
      expect(v.rowFor(99).first, closeTo(512 / 768, 1e-6));
      expect(v.rowFor(1), hasLength(256));
    });

    test('rifiuta dimensioni e valori non validi', () {
      expect(() => KokoroVoiceStyle.fromBytes(Uint8List(100)),
          throwsA(isA<SpeechEngineException>()));
      final bad = Float32List(256)..[3] = double.infinity;
      expect(() => KokoroVoiceStyle.fromBytes(bad.buffer.asUint8List()),
          throwsA(isA<SpeechEngineException>()));
    });
  });

  group('KokoroOnnxSpeechEngine senza file nativi', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('aura_voce_'));
    tearDown(() => dir.deleteSync(recursive: true));

    KokoroOnnxSpeechEngine engine() => KokoroOnnxSpeechEngine(
          files: KokoroEngineFiles(
            modelPath: '${dir.path}${Platform.pathSeparator}model.onnx',
            voicePath: '${dir.path}${Platform.pathSeparator}voce.bin',
            onnxRuntimeLibraryPath:
                '${dir.path}${Platform.pathSeparator}onnxruntime.dll',
          ),
        );

    test('file mancanti: errore tipizzato senza percorsi', () async {
      final e = engine();
      await expectLater(
        e.initialize(),
        throwsA(isA<SpeechEngineException>()
            .having((x) => x.code, 'code', SpeechEngineFailureCode.assetMissing)
            .having((x) => x.message, 'message', isNot(contains(dir.path)))),
      );
      expect(e.isReady, isFalse);
    });

    test('voce non valida rilevata prima di avviare il motore', () async {
      final sep = Platform.pathSeparator;
      File('${dir.path}${sep}model.onnx').writeAsBytesSync([1]);
      File('${dir.path}${sep}onnxruntime.dll').writeAsBytesSync([1]);
      File('${dir.path}${sep}voce.bin').writeAsBytesSync(List.filled(10, 0));
      await expectLater(
        engine().initialize(),
        throwsA(isA<SpeechEngineException>().having(
            (x) => x.code, 'code', SpeechEngineFailureCode.assetInvalid)),
      );
    });

    test('sintesi prima dell\'avvio e rilascio single-flight', () async {
      final e = engine();
      await expectLater(
        e.synthesize('a', SpeechVoiceRequest()),
        throwsA(isA<SpeechEngineException>().having(
            (x) => x.code, 'code', SpeechEngineFailureCode.invalidState)),
      );
      final f1 = e.dispose();
      final f2 = e.dispose();
      expect(identical(f1, f2), isTrue);
      await f1;
      await expectLater(e.initialize(), throwsA(isA<SpeechEngineException>()));
    });
  });
}
