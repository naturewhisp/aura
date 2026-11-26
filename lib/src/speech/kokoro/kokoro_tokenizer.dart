import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../speech_engine.dart';

part 'kokoro_vocabulary_data.dart';

/// Risultato della conversione di fonemi in indici del modello.
@immutable
class KokoroTokens {
  const KokoroTokens(this.ids, this.droppedSymbols);

  /// Indici dei simboli, con il simbolo di bordo (0) in testa e in coda.
  final List<int> ids;

  /// Numero di simboli scartati perché assenti dal vocabolario.
  final int droppedSymbols;

  /// Numero di simboli effettivi, esclusi i bordi.
  int get symbolCount => ids.length - 2;
}

/// Converte i fonemi nei simboli di Kokoro-82M.
abstract final class KokoroTokenizer {
  /// Massimo numero di simboli per sintesi (contesto del modello meno i due bordi).
  static const int maxSymbols = 510;

  /// Converte [phonemes]; i simboli sconosciuti vengono scartati e contati.
  ///
  /// Lancia [SpeechEngineException] se non resta alcun simbolo o se sono troppi.
  static KokoroTokens tokenize(String phonemes) {
    final ids = <int>[0];
    var dropped = 0;
    for (final rune in phonemes.runes) {
      final id = _kokoroVocabulary[String.fromCharCode(rune)];
      if (id == null) {
        dropped++;
      } else {
        ids.add(id);
      }
    }
    final count = ids.length - 1;
    if (count == 0) {
      throw const SpeechEngineException(
        SpeechEngineFailureCode.invalidRequest,
        'Nessun simbolo pronunciabile nel blocco.',
      );
    }
    if (count > maxSymbols) {
      throw SpeechEngineException(
        SpeechEngineFailureCode.invalidRequest,
        'Blocco troppo lungo per il modello: $count simboli, massimo $maxSymbols.',
      );
    }
    ids.add(0);
    return KokoroTokens(List.unmodifiable(ids), dropped);
  }
}

/// Stili di una voce Kokoro: una riga di 256 valori per ogni lunghezza del blocco.
@immutable
class KokoroVoiceStyle {
  KokoroVoiceStyle._(this._rows, this.rowCount);

  /// Legge un file di voce: valori float32 little-endian, `righe × 256`.
  factory KokoroVoiceStyle.fromBytes(Uint8List bytes) {
    const rowBytes = styleWidth * 4;
    if (bytes.isEmpty || bytes.length % rowBytes != 0) {
      throw const SpeechEngineException(
        SpeechEngineFailureCode.assetInvalid,
        'File della voce non valido: dimensione non multipla di una riga di stile.',
      );
    }
    final copy = Uint8List.fromList(bytes);
    final values = copy.buffer.asFloat32List();
    if (values.any((v) => !v.isFinite)) {
      throw const SpeechEngineException(
        SpeechEngineFailureCode.assetInvalid,
        'File della voce non valido: contiene valori non finiti.',
      );
    }
    return KokoroVoiceStyle._(values, bytes.length ~/ rowBytes);
  }

  /// Valori per riga, come atteso dall'ingresso `style` del modello.
  static const int styleWidth = 256;

  final Float32List _rows;

  /// Numero di righe disponibili (510 nelle voci ufficiali).
  final int rowCount;

  /// Stile da usare per un blocco di [symbolCount] simboli.
  Float32List rowFor(int symbolCount) {
    final row = (symbolCount - 1).clamp(0, rowCount - 1);
    return Float32List.sublistView(
        _rows, row * styleWidth, (row + 1) * styleWidth);
  }
}
