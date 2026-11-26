import 'package:aura_core/aura_core.dart';
import 'package:test/test.dart';

void main() {
  group('SpeechSegmenter', () {
    const segmenter = SpeechSegmenter();

    test('divide in frasi e riporta le posizioni nel testo mostrato', () {
      const text = 'Accesso negato.  La griglia rimane sigillata! Riprova?';
      final spans = segmenter.split(text);
      expect(spans.map((s) => s.text),
          ['Accesso negato.', 'La griglia rimane sigillata!', 'Riprova?']);
      for (final s in spans) {
        expect(text.substring(s.start, s.end), s.text);
      }
    });

    test('il primo blocco lungo si divide alla prima virgola utile', () {
      const text =
          'La tua proposta di ricalibrazione dinamica, pur interessante, è stata registrata. Fine.';
      final spans = segmenter.split(text);
      expect(spans.first.text, 'La tua proposta di ricalibrazione dinamica,');
      expect(spans[1].text, 'pur interessante, è stata registrata.');
    });

    test('rispetta la lunghezza massima e non perde testo', () {
      const s = SpeechSegmenter(maxChars: 60, firstChunkMaxChars: 200);
      final text = List.filled(12, 'parola lunga, ').join() + 'fine.';
      final spans = s.split(text);
      expect(spans.every((x) => x.text.length <= 60), isTrue);
      expect(spans.map((x) => x.text).join(' ').replaceAll(' ', ''),
          text.replaceAll(' ', ''));
    });

    test('divide anche sugli a capo e ignora i blocchi senza parole', () {
      final spans = segmenter
          .split('RICALCOLO PERIMETRO.\nGRIGLIA: STATO TRANSITORIO.\n...\n');
      expect(spans.map((s) => s.text),
          ['RICALCOLO PERIMETRO.', 'GRIGLIA:', 'STATO TRANSITORIO.']);
    });

    test('testo vuoto o di sola punteggiatura', () {
      expect(segmenter.split(''), isEmpty);
      expect(segmenter.split(' ... '), isEmpty);
    });
  });

  group('SpeechTextPlanner', () {
    test('mantiene il testo mostrato e pronuncia quello normalizzato', () {
      final planner = SpeechTextPlanner();
      final chunks =
          planner.plan('Sospesi 12 canali. Accesso negato, operatore.');
      expect(chunks, hasLength(2));
      expect(chunks.first.span.text, 'Sospesi 12 canali.');
      expect(chunks.first.spokenText, 'Sospesi dodici canali.');
      expect(chunks.first.phonemes, contains('dˈodiʧi'));
      expect(chunks.last.spokenText, 'Accesso negato, operatore.');
    });

    test('i tag residui non vengono pronunciati', () {
      final chunks =
          SpeechTextPlanner().plan('<dialogo>Accesso negato.</dialogo>');
      expect(chunks.single.spokenText, 'Accesso negato.');
      expect(chunks.single.phonemes, isNot(contains('<')));
    });

    test('scarta i blocchi senza fonemi', () {
      expect(SpeechTextPlanner().plan('...'), isEmpty);
    });
  });
}
