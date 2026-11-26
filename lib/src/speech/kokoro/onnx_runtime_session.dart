import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

typedef _Ptr = Pointer<Void>;

/// Indici nella tabella `OrtApi`, verificati su `onnxruntime_c_api.h` di
/// ONNX Runtime 1.32.0. La tabella viene solo estesa in coda tra versioni,
/// quindi gli indici restano validi richiedendo l'API [_apiVersion].
abstract final class _OrtIndex {
  static const getErrorMessage = 2;
  static const createEnv = 3;
  static const createSession = 7;
  static const run = 9;
  static const createSessionOptions = 10;
  static const setIntraOpNumThreads = 24;
  static const setInterOpNumThreads = 25;
  static const createTensorWithDataAsOrtValue = 49;
  static const getTensorMutableData = 51;
  static const getTensorShapeElementCount = 64;
  static const getTensorTypeAndShape = 65;
  static const createCpuMemoryInfo = 69;
  static const releaseEnv = 92;
  static const releaseStatus = 93;
  static const releaseMemoryInfo = 94;
  static const releaseSession = 95;
  static const releaseValue = 96;
  static const releaseTensorTypeAndShapeInfo = 99;
  static const releaseSessionOptions = 100;
}

/// Versione minima dell'API C richiesta.
const int _apiVersion = 17;

const int _elementFloat = 1;
const int _elementInt64 = 7;

/// Errore di ONNX Runtime. Il messaggio della libreria può contenere percorsi
/// locali: va usato solo per diagnostica interna, mai mostrato o registrato.
final class OnnxRuntimeError implements Exception {
  const OnnxRuntimeError(this.message);
  final String message;
  @override
  String toString() => 'OnnxRuntimeError';
}

/// Funzioni dell'API C usate dal motore, risolte una volta dalla tabella.
final class _OrtApi {
  _OrtApi(Pointer<_Ptr> t)
      : getErrorMessage = t[_OrtIndex.getErrorMessage]
            .cast<NativeFunction<Pointer<Utf8> Function(_Ptr)>>()
            .asFunction(),
        createEnv = t[_OrtIndex.createEnv]
            .cast<
                NativeFunction<
                    _Ptr Function(Int32, Pointer<Utf8>, Pointer<_Ptr>)>>()
            .asFunction(),
        createSession = t[_OrtIndex.createSession]
            .cast<
                NativeFunction<
                    _Ptr Function(_Ptr, Pointer<Utf16>, _Ptr, Pointer<_Ptr>)>>()
            .asFunction(),
        run = t[_OrtIndex.run]
            .cast<
                NativeFunction<
                    _Ptr Function(
                        _Ptr,
                        _Ptr,
                        Pointer<Pointer<Utf8>>,
                        Pointer<_Ptr>,
                        Size,
                        Pointer<Pointer<Utf8>>,
                        Size,
                        Pointer<_Ptr>)>>()
            .asFunction(),
        createSessionOptions = t[_OrtIndex.createSessionOptions]
            .cast<NativeFunction<_Ptr Function(Pointer<_Ptr>)>>()
            .asFunction(),
        setIntraOpNumThreads = t[_OrtIndex.setIntraOpNumThreads]
            .cast<NativeFunction<_Ptr Function(_Ptr, Int32)>>()
            .asFunction(),
        setInterOpNumThreads = t[_OrtIndex.setInterOpNumThreads]
            .cast<NativeFunction<_Ptr Function(_Ptr, Int32)>>()
            .asFunction(),
        createTensor = t[_OrtIndex.createTensorWithDataAsOrtValue]
            .cast<
                NativeFunction<
                    _Ptr Function(_Ptr, _Ptr, Size, Pointer<Int64>, Size, Int32,
                        Pointer<_Ptr>)>>()
            .asFunction(),
        getTensorMutableData = t[_OrtIndex.getTensorMutableData]
            .cast<NativeFunction<_Ptr Function(_Ptr, Pointer<_Ptr>)>>()
            .asFunction(),
        getElementCount = t[_OrtIndex.getTensorShapeElementCount]
            .cast<NativeFunction<_Ptr Function(_Ptr, Pointer<Size>)>>()
            .asFunction(),
        getTypeAndShape = t[_OrtIndex.getTensorTypeAndShape]
            .cast<NativeFunction<_Ptr Function(_Ptr, Pointer<_Ptr>)>>()
            .asFunction(),
        createCpuMemoryInfo = t[_OrtIndex.createCpuMemoryInfo]
            .cast<NativeFunction<_Ptr Function(Int32, Int32, Pointer<_Ptr>)>>()
            .asFunction(),
        releaseEnv = _release(t, _OrtIndex.releaseEnv),
        releaseStatus = _release(t, _OrtIndex.releaseStatus),
        releaseMemoryInfo = _release(t, _OrtIndex.releaseMemoryInfo),
        releaseSession = _release(t, _OrtIndex.releaseSession),
        releaseValue = _release(t, _OrtIndex.releaseValue),
        releaseTypeAndShape =
            _release(t, _OrtIndex.releaseTensorTypeAndShapeInfo),
        releaseSessionOptions = _release(t, _OrtIndex.releaseSessionOptions);

  static void Function(_Ptr) _release(Pointer<_Ptr> t, int i) =>
      t[i].cast<NativeFunction<Void Function(_Ptr)>>().asFunction();

  final Pointer<Utf8> Function(_Ptr) getErrorMessage;
  final _Ptr Function(int, Pointer<Utf8>, Pointer<_Ptr>) createEnv;
  final _Ptr Function(_Ptr, Pointer<Utf16>, _Ptr, Pointer<_Ptr>) createSession;
  final _Ptr Function(_Ptr, _Ptr, Pointer<Pointer<Utf8>>, Pointer<_Ptr>, int,
      Pointer<Pointer<Utf8>>, int, Pointer<_Ptr>) run;
  final _Ptr Function(Pointer<_Ptr>) createSessionOptions;
  final _Ptr Function(_Ptr, int) setIntraOpNumThreads;
  final _Ptr Function(_Ptr, int) setInterOpNumThreads;
  final _Ptr Function(_Ptr, _Ptr, int, Pointer<Int64>, int, int, Pointer<_Ptr>)
      createTensor;
  final _Ptr Function(_Ptr, Pointer<_Ptr>) getTensorMutableData;
  final _Ptr Function(_Ptr, Pointer<Size>) getElementCount;
  final _Ptr Function(_Ptr, Pointer<_Ptr>) getTypeAndShape;
  final _Ptr Function(int, int, Pointer<_Ptr>) createCpuMemoryInfo;
  final void Function(_Ptr) releaseEnv,
      releaseStatus,
      releaseMemoryInfo,
      releaseSession,
      releaseValue,
      releaseTypeAndShape,
      releaseSessionOptions;

  /// Converte uno stato di errore in eccezione, rilasciandolo.
  void check(_Ptr status) {
    if (status == nullptr) return;
    final message = getErrorMessage(status).toDartString();
    releaseStatus(status);
    throw OnnxRuntimeError(message);
  }

  static void releaseIf(void Function(_Ptr) release, _Ptr p) {
    if (p != nullptr) release(p);
  }
}

/// Sessione ONNX Runtime per il modello Kokoro, con l'API C via FFI.
///
/// Da usare in un solo isolate: le chiamate sono sincrone e bloccanti.
final class KokoroOnnxSession {
  KokoroOnnxSession._(this._api, this._env, this._session, this._memory);

  /// Carica la libreria [libraryPath] e il modello [modelPath].
  ///
  /// Lancia [ArgumentError] se la libreria non si carica e [OnnxRuntimeError]
  /// se ONNX Runtime rifiuta il modello.
  factory KokoroOnnxSession.open({
    required String libraryPath,
    required String modelPath,
    required int threads,
  }) {
    final lib = DynamicLibrary.open(libraryPath);
    final base =
        lib.lookupFunction<Pointer<_Ptr> Function(), Pointer<_Ptr> Function()>(
      'OrtGetApiBase',
    )();
    final table = base[0]
        .cast<NativeFunction<_Ptr Function(Uint32)>>()
        .asFunction<_Ptr Function(int)>()(_apiVersion)
        .cast<_Ptr>();
    if (table == nullptr) {
      throw const OnnxRuntimeError(
          'API C non disponibile nella versione richiesta.');
    }
    final api = _OrtApi(table);
    final out = calloc<_Ptr>();
    final name = 'aura'.toNativeUtf8();
    final path = modelPath.toNativeUtf16();
    _Ptr env = nullptr, options = nullptr, session = nullptr, memory = nullptr;
    try {
      api.check(api.createEnv(3, name, out));
      env = out.value;
      api.check(api.createSessionOptions(out));
      options = out.value;
      api.check(api.setIntraOpNumThreads(options, threads));
      api.check(api.setInterOpNumThreads(options, 1));
      api.check(api.createSession(env, path, options, out));
      session = out.value;
      api.check(api.createCpuMemoryInfo(0, 0, out));
      memory = out.value;
      return KokoroOnnxSession._(api, env, session, memory);
    } catch (_) {
      _OrtApi.releaseIf(api.releaseMemoryInfo, memory);
      _OrtApi.releaseIf(api.releaseSession, session);
      _OrtApi.releaseIf(api.releaseEnv, env);
      rethrow;
    } finally {
      _OrtApi.releaseIf(api.releaseSessionOptions, options);
      calloc.free(out);
      calloc.free(name);
      calloc.free(path);
    }
  }

  final _OrtApi _api;
  final _Ptr _env, _session, _memory;
  bool _closed = false;

  /// Esegue il modello e restituisce la forma d'onda a 24 kHz.
  Float32List run(List<int> ids, Float32List style, double speed) {
    if (_closed) throw const OnnxRuntimeError('Sessione già chiusa.');
    final api = _api;
    final n = ids.length;
    final idsBuf = calloc<Int64>(n);
    final styleBuf = calloc<Float>(style.length);
    final speedBuf = calloc<Float>();
    final inputs = calloc<_Ptr>(3);
    final inputNames = calloc<Pointer<Utf8>>(3);
    final outputNames = calloc<Pointer<Utf8>>();
    final output = calloc<_Ptr>();
    final out = calloc<_Ptr>();
    final count = calloc<Size>();
    _Ptr info = nullptr;
    try {
      idsBuf.asTypedList(n).setAll(0, ids);
      styleBuf.asTypedList(style.length).setAll(0, style);
      speedBuf.value = speed;
      inputs[0] = _tensor(idsBuf.cast(), n * 8, [1, n], _elementInt64);
      inputs[1] = _tensor(
          styleBuf.cast(), style.length * 4, [1, style.length], _elementFloat);
      inputs[2] = _tensor(speedBuf.cast(), 4, [1], _elementFloat);
      inputNames[0] = 'input_ids'.toNativeUtf8();
      inputNames[1] = 'style'.toNativeUtf8();
      inputNames[2] = 'speed'.toNativeUtf8();
      outputNames[0] = 'waveform'.toNativeUtf8();
      api.check(api.run(
          _session, nullptr, inputNames, inputs, 3, outputNames, 1, output));
      api.check(api.getTypeAndShape(output.value, out));
      info = out.value;
      api.check(api.getElementCount(info, count));
      api.check(api.getTensorMutableData(output.value, out));
      return Float32List.fromList(
          out.value.cast<Float>().asTypedList(count.value));
    } finally {
      _OrtApi.releaseIf(api.releaseTypeAndShape, info);
      _OrtApi.releaseIf(api.releaseValue, output.value);
      for (var i = 0; i < 3; i++) {
        _OrtApi.releaseIf(api.releaseValue, inputs[i]);
        if (inputNames[i] != nullptr) calloc.free(inputNames[i]);
      }
      if (outputNames[0] != nullptr) calloc.free(outputNames[0]);
      for (final p in <Pointer<NativeType>>[
        idsBuf,
        styleBuf,
        speedBuf,
        inputs,
        inputNames,
        outputNames,
        output,
        out,
        count,
      ]) {
        calloc.free(p);
      }
    }
  }

  _Ptr _tensor(_Ptr data, int bytes, List<int> shape, int type) {
    final dims = calloc<Int64>(shape.length);
    final out = calloc<_Ptr>();
    try {
      dims.asTypedList(shape.length).setAll(0, shape);
      _api.check(_api.createTensor(
          _memory, data, bytes, dims, shape.length, type, out));
      return out.value;
    } finally {
      calloc.free(dims);
      calloc.free(out);
    }
  }

  /// Rilascia memoria, sessione e ambiente. Idempotente.
  void close() {
    if (_closed) return;
    _closed = true;
    _OrtApi.releaseIf(_api.releaseMemoryInfo, _memory);
    _OrtApi.releaseIf(_api.releaseSession, _session);
    _OrtApi.releaseIf(_api.releaseEnv, _env);
  }
}
