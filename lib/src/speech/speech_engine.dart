import 'dart:typed_data';

import 'package:meta/meta.dart';

/// Audio sintetizzato: campioni mono in virgola mobile nell'intervallo [-1, 1].
@immutable
class SpeechAudio {
  SpeechAudio({required this.samples, required this.sampleRate}) {
    if (sampleRate <= 0) {
      throw ArgumentError.value(
          sampleRate, 'sampleRate', 'deve essere positivo');
    }
  }

  /// Audio vuoto, prodotto dal motore silenzioso.
  factory SpeechAudio.silent({int sampleRate = 24000}) =>
      SpeechAudio(samples: Float32List(0), sampleRate: sampleRate);

  final Float32List samples;
  final int sampleRate;

  /// Durata dell'audio, usata dalla sincronizzazione del testo.
  Duration get duration =>
      Duration(microseconds: samples.length * 1000000 ~/ sampleRate);

  bool get isEmpty => samples.isEmpty;
}

/// Parametri di voce per una singola sintesi.
@immutable
class SpeechVoiceRequest {
  SpeechVoiceRequest({this.speed = 1.0}) {
    if (!speed.isFinite || speed < 0.5 || speed > 2.0) {
      throw ArgumentError.value(
          speed, 'speed', 'deve essere compresa tra 0.5 e 2.0');
    }
  }

  /// Velocità di lettura relativa: 1.0 è quella naturale della voce.
  final double speed;
}

/// Cause di fallimento di un [SpeechEngine].
enum SpeechEngineFailureCode {
  /// Un file del motore (modello, voce, libreria) manca o non è leggibile.
  assetMissing,

  /// Un file del motore esiste ma ha un formato non valido.
  assetInvalid,

  /// La libreria nativa non si carica o non espone l'API attesa.
  runtimeUnavailable,

  /// L'inizializzazione del modello è fallita.
  initializationFailed,

  /// La richiesta non è valida (es. testo troppo lungo per il modello).
  invalidRequest,

  /// La sintesi è fallita durante l'esecuzione del modello.
  synthesisFailed,

  /// Operazione richiesta prima di `initialize()` o dopo `dispose()`.
  invalidState,
}

/// Errore tipizzato di un motore di sintesi.
///
/// Il messaggio è già sanitizzato (nessun percorso locale); la causa originaria
/// resta disponibile in [cause] ma non compare in [toString].
final class SpeechEngineException implements Exception {
  const SpeechEngineException(this.code, this.message, {this.cause});

  final SpeechEngineFailureCode code;
  final String message;
  final Object? cause;

  @override
  String toString() => 'SpeechEngineException(${code.name}): $message';
}

/// Contratto di un motore di sintesi vocale.
///
/// I fonemi arrivano già calcolati (vedi `SpeechTextPlanner`): il motore non conosce
/// la lingua. L'uso tipico è `initialize()` una volta, poi `synthesize()` per ogni
/// blocco, infine `dispose()`.
abstract interface class SpeechEngine {
  /// Identificativo stabile del motore, per diagnostica e provenance.
  String get id;

  /// Vero dopo un'inizializzazione riuscita e prima di `dispose()`.
  bool get isReady;

  /// Carica modello e voce. Idempotente: chiamate successive non ricaricano.
  Future<void> initialize();

  /// Sintetizza [phonemes] con i parametri di [request].
  Future<SpeechAudio> synthesize(String phonemes, SpeechVoiceRequest request);

  /// Rilascia le risorse. Idempotente e single-flight.
  Future<void> dispose();
}

/// Motore di ripiego che non produce suono.
///
/// Usato quando la voce è spenta o non disponibile: il resto del gioco non deve
/// distinguere i due casi.
final class SilentSpeechEngine implements SpeechEngine {
  SilentSpeechEngine({this.sampleRate = 24000});

  final int sampleRate;
  bool _disposed = false;

  @override
  String get id => 'silent';

  @override
  bool get isReady => !_disposed;

  @override
  Future<void> initialize() async {}

  @override
  Future<SpeechAudio> synthesize(
      String phonemes, SpeechVoiceRequest request) async {
    if (_disposed) {
      throw const SpeechEngineException(
        SpeechEngineFailureCode.invalidState,
        'Il motore silenzioso è già stato rilasciato.',
      );
    }
    return SpeechAudio.silent(sampleRate: sampleRate);
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
  }
}
