import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../speech_engine.dart';
import 'kokoro_tokenizer.dart';
import 'onnx_runtime_session.dart';

/// File necessari al motore Kokoro.
@immutable
class KokoroEngineFiles {
  const KokoroEngineFiles({
    required this.modelPath,
    required this.voicePath,
    required this.onnxRuntimeLibraryPath,
  });

  /// Modello ONNX di Kokoro-82M v1.0 (`model.onnx`).
  final String modelPath;

  /// Stili della voce (float32 little-endian, righe × 256).
  final String voicePath;

  /// Libreria nativa di ONNX Runtime (`onnxruntime.dll` su Windows).
  final String onnxRuntimeLibraryPath;
}

/// Motore di sintesi Kokoro-82M eseguito con ONNX Runtime su CPU.
///
/// Modello e sessione vivono in un isolate dedicato: la sintesi non blocca mai
/// l'isolate dell'interfaccia. Le richieste vengono servite una alla volta,
/// nell'ordine di arrivo.
final class KokoroOnnxSpeechEngine implements SpeechEngine {
  KokoroOnnxSpeechEngine({required this.files, this.threads = 4})
      : assert(threads >= 1);

  final KokoroEngineFiles files;

  /// Thread di calcolo di ONNX Runtime (4 tengono la sintesi oltre il tempo reale
  /// anche con Attore e Valutatore attivi).
  final int threads;

  static const int sampleRate = 24000;

  Isolate? _isolate;
  SendPort? _requests;
  ReceivePort? _replies;
  final Map<int, Completer<Object?>> _pending = {};
  int _nextRequestId = 0;
  Future<void>? _initializing;
  Future<void>? _disposing;
  bool _disposed = false;

  @override
  String get id => 'kokoro-82m-onnx';

  @override
  bool get isReady => _requests != null && !_disposed;

  @override
  Future<void> initialize() {
    if (_disposed) {
      return Future.error(const SpeechEngineException(
        SpeechEngineFailureCode.invalidState,
        'Il motore è già stato rilasciato.',
      ));
    }
    return _initializing ??= _start().catchError((Object e) {
      _initializing = null;
      throw e;
    });
  }

  Future<void> _start() async {
    final names = {
      files.modelPath: 'modello',
      files.voicePath: 'voce',
      files.onnxRuntimeLibraryPath: 'libreria ONNX Runtime',
    };
    for (final e in names.entries) {
      if (!File(e.key).existsSync()) {
        throw SpeechEngineException(
          SpeechEngineFailureCode.assetMissing,
          'File della voce mancante: ${e.value}.',
        );
      }
    }
    final Uint8List voiceBytes;
    try {
      voiceBytes = await File(files.voicePath).readAsBytes();
    } catch (e) {
      throw SpeechEngineException(
        SpeechEngineFailureCode.assetMissing,
        'File della voce non leggibile.',
        cause: e,
      );
    }
    KokoroVoiceStyle.fromBytes(voiceBytes);

    final replies = ReceivePort();
    final ready = Completer<SendPort>();
    replies.listen((Object? message) {
      if (message is SendPort) {
        ready.complete(message);
      } else if (message is _Reply) {
        _pending.remove(message.id)?.complete(message.payload);
      }
    });
    _replies = replies;
    try {
      _isolate = await Isolate.spawn(
        _workerMain,
        _WorkerConfig(
          replies.sendPort,
          files.onnxRuntimeLibraryPath,
          files.modelPath,
          TransferableTypedData.fromList([voiceBytes]),
          threads,
        ),
        debugName: 'aura-speech-kokoro',
        errorsAreFatal: false,
      );
      _requests = await ready.future;
      final result = await _call(const _InitRequest());
      if (result is _WorkerFailure) throw result.toException();
    } catch (e) {
      await _shutdown();
      if (e is SpeechEngineException) rethrow;
      throw SpeechEngineException(
        SpeechEngineFailureCode.initializationFailed,
        'Avvio del motore vocale non riuscito.',
        cause: e,
      );
    }
  }

  Future<Object?> _call(Object request, [SendPort? port]) {
    final target = port ?? _requests;
    if (target == null) {
      return Future.value(const _WorkerFailure(
        SpeechEngineFailureCode.invalidState,
        'Il motore vocale non è attivo.',
      ));
    }
    final id = _nextRequestId++;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    target.send(_Envelope(id, request));
    return completer.future;
  }

  @override
  Future<SpeechAudio> synthesize(
      String phonemes, SpeechVoiceRequest request) async {
    if (!isReady) {
      throw const SpeechEngineException(
        SpeechEngineFailureCode.invalidState,
        'Il motore vocale non è inizializzato.',
      );
    }
    final tokens = KokoroTokenizer.tokenize(phonemes);
    final result = await _call(_SynthesisRequest(tokens.ids, request.speed));
    if (result is _WorkerFailure) throw result.toException();
    if (result is! TransferableTypedData) {
      throw const SpeechEngineException(
        SpeechEngineFailureCode.synthesisFailed,
        'Il motore vocale ha restituito una risposta inattesa.',
      );
    }
    final samples = result.materialize().asFloat32List();
    return SpeechAudio(samples: samples, sampleRate: sampleRate);
  }

  @override
  Future<void> dispose() {
    _disposed = true;
    return _disposing ??= _shutdown();
  }

  Future<void> _shutdown() async {
    final requests = _requests;
    _requests = null;
    if (requests != null && _isolate != null) {
      // Chiude la sessione nativa nell'isolate prima di terminarlo.
      await _call(const _CloseRequest(), requests)
          .timeout(const Duration(seconds: 5), onTimeout: () => null);
    }
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    for (final c in _pending.values) {
      if (!c.isCompleted) {
        c.complete(const _WorkerFailure(
            SpeechEngineFailureCode.invalidState, 'Motore vocale rilasciato.'));
      }
    }
    _pending.clear();
    _replies?.close();
    _replies = null;
  }
}

// ---------------------------------------------------------------------------
// Messaggi tra isolate (solo tipi trasferibili).

final class _WorkerConfig {
  const _WorkerConfig(
      this.replies, this.library, this.model, this.voice, this.threads);
  final SendPort replies;
  final String library, model;
  final TransferableTypedData voice;
  final int threads;
}

final class _Envelope {
  const _Envelope(this.id, this.request);
  final int id;
  final Object request;
}

final class _Reply {
  const _Reply(this.id, this.payload);
  final int id;
  final Object? payload;
}

final class _InitRequest {
  const _InitRequest();
}

final class _CloseRequest {
  const _CloseRequest();
}

final class _SynthesisRequest {
  const _SynthesisRequest(this.ids, this.speed);
  final List<int> ids;
  final double speed;
}

final class _WorkerFailure {
  const _WorkerFailure(this.code, this.message);
  final SpeechEngineFailureCode code;
  final String message;
  SpeechEngineException toException() => SpeechEngineException(code, message);
}

void _workerMain(_WorkerConfig config) {
  final inbox = ReceivePort();
  config.replies.send(inbox.sendPort);
  KokoroOnnxSession? session;
  KokoroVoiceStyle? voice;
  inbox.listen((Object? message) {
    if (message is! _Envelope) return;
    final request = message.request;
    Object? reply;
    if (request is _InitRequest) {
      try {
        voice = KokoroVoiceStyle.fromBytes(
            config.voice.materialize().asUint8List());
        session = KokoroOnnxSession.open(
          libraryPath: config.library,
          modelPath: config.model,
          threads: config.threads,
        );
      } on ArgumentError {
        reply = const _WorkerFailure(
          SpeechEngineFailureCode.runtimeUnavailable,
          'Libreria ONNX Runtime non caricabile.',
        );
      } on OnnxRuntimeError {
        // Il messaggio di ONNX Runtime può contenere percorsi locali: non viene propagato.
        reply = const _WorkerFailure(
          SpeechEngineFailureCode.initializationFailed,
          'ONNX Runtime non ha caricato il modello vocale.',
        );
      } on SpeechEngineException catch (e) {
        reply = _WorkerFailure(e.code, e.message);
      } catch (_) {
        reply = const _WorkerFailure(
          SpeechEngineFailureCode.runtimeUnavailable,
          'Libreria ONNX Runtime non compatibile.',
        );
      }
    } else if (request is _SynthesisRequest) {
      final s = session;
      if (s == null || voice == null) {
        reply = const _WorkerFailure(
            SpeechEngineFailureCode.invalidState, 'Modello non caricato.');
      } else {
        try {
          final wave = s.run(request.ids, voice!.rowFor(request.ids.length - 2),
              request.speed);
          reply = TransferableTypedData.fromList([wave]);
        } on OnnxRuntimeError {
          reply = const _WorkerFailure(
            SpeechEngineFailureCode.synthesisFailed,
            'ONNX Runtime non ha completato la sintesi.',
          );
        } catch (_) {
          reply = const _WorkerFailure(
              SpeechEngineFailureCode.synthesisFailed, 'Sintesi non riuscita.');
        }
      }
    } else if (request is _CloseRequest) {
      session?.close();
      session = null;
      config.replies.send(_Reply(message.id, null));
      inbox.close();
      return;
    }
    config.replies.send(_Reply(message.id, reply));
  });
}
