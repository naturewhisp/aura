import 'package:meta/meta.dart';

import 'italian_phonemizer.dart';
import 'speech_segmenter.dart';
import 'speech_text_normalizer.dart';

/// Blocco di una battuta pronto per la sintesi.
@immutable
class SpeechChunk {
  const SpeechChunk(
      {required this.span, required this.spokenText, required this.phonemes});

  /// Porzione del testo mostrato a schermo a cui il blocco corrisponde.
  final SpeechSpan span;

  /// Testo normalizzato effettivamente pronunciato (numeri in lettere, sigle lette).
  final String spokenText;

  /// Trascrizione fonetica di [spokenText].
  final String phonemes;
}

/// Trasforma il testo di una battuta in blocchi da pronunciare.
///
/// Divide il testo mostrato a schermo, normalizza ogni blocco e ne calcola la
/// fonetica. Non dipende da alcun motore di sintesi.
@immutable
class SpeechTextPlanner {
  SpeechTextPlanner({
    this.segmenter = const SpeechSegmenter(),
    this.normalizer = const SpeechTextNormalizer(),
    ItalianPhonemizer? phonemizer,
  }) : phonemizer = phonemizer ?? ItalianPhonemizer();

  final SpeechSegmenter segmenter;
  final SpeechTextNormalizer normalizer;
  final ItalianPhonemizer phonemizer;

  /// Restituisce i blocchi di [displayText] nell'ordine di lettura.
  ///
  /// [displayText] è il testo mostrato a schermo, già privo dei tag dell'agent-loop
  /// (es. `<dialogo>`): un tag incollato alla punteggiatura impedisce di riconoscere
  /// la fine della frase. Eventuali tag residui non vengono comunque pronunciati.
  ///
  /// I blocchi che dopo la normalizzazione restano senza fonemi vengono scartati.
  List<SpeechChunk> plan(String displayText) {
    final out = <SpeechChunk>[];
    for (final span in segmenter.split(displayText)) {
      final spoken = normalizer.normalize(span.text).replaceAll('\n', ' ');
      final phonemes = phonemizer.transcribe(spoken);
      if (phonemes.trim().isEmpty) continue;
      out.add(SpeechChunk(span: span, spokenText: spoken, phonemes: phonemes));
    }
    return out;
  }
}
