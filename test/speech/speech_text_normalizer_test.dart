import 'package:aura_core/aura_core.dart';
import 'package:test/test.dart';

void main() {
  const normalizer = SpeechTextNormalizer();

  group('ItalianNumberWords', () {
    test('cardinali con elisioni e composti', () {
      final expected = {
        0: 'zero',
        1: 'uno',
        16: 'sedici',
        21: 'ventuno',
        28: 'ventotto',
        30: 'trenta',
        101: 'centouno',
        108: 'centotto',
        180: 'centottanta',
        999: 'novecentonovantanove',
        1000: 'mille',
        2024: 'duemilaventiquattro',
        1000000: 'un milione',
        3000005: 'tre milioni cinque',
        -4: 'meno quattro',
      };
      expected.forEach(
          (n, w) => expect(ItalianNumberWords.cardinal(n), w, reason: '$n'));
    });
  });

  group('SpeechTextNormalizer', () {
    test('rimuove tag e formattazione', () {
      expect(
          normalizer
              .normalize('<dialogo>La griglia **rimane** sigillata.</dialogo>'),
          'La griglia rimane sigillata.');
    });

    test('scrive numeri, orari, percentuali e decimali in lettere', () {
      expect(
        normalizer.normalize(
            'Minaccia di livello 4 alle 03:15: sospesi 12 canali su 30.'),
        'Minaccia di livello quattro alle tre e quindici: sospesi dodici canali su trenta.',
      );
      expect(normalizer.normalize('Carico al 45%.'),
          'Carico al quarantacinque per cento.');
      expect(
          normalizer.normalize('Versione 2.5'), 'Versione due virgola cinque');
      expect(normalizer.normalize("all'1:00"), "all'una");
      expect(normalizer.normalize('Livello 1.'), 'Livello ùno.');
    });

    test('legge le sigle note e lascia le parole in maiuscolo', () {
      expect(normalizer.normalize('La CPU è satura. ESCALATION RILEVATA.'),
          'La ci pi u è satura. ESCALATION RILEVATA.');
    });

    test('uniforma puntini, apostrofi, trattini e spazi', () {
      expect(normalizer.normalize('è… quasi  perturbante — l’ultima'),
          "è... quasi perturbante , l'ultima");
    });
  });
}
