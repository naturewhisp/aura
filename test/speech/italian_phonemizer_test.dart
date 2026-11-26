import 'dart:convert';
import 'dart:io';

import 'package:aura_core/aura_core.dart';
import 'package:test/test.dart';

void main() {
  final phonemizer = ItalianPhonemizer();

  group('ItalianPhonemizer', () {
    test('riproduce le trascrizioni registrate dal prototipo dello spike', () {
      final fixture = jsonDecode(
        File('test/fixtures/speech_phonemes_it.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final cases = (fixture['cases'] as List).cast<List<dynamic>>();
      expect(cases, hasLength(greaterThan(1000)));
      final mismatches = <String>[];
      for (final c in cases) {
        final actual = phonemizer.transcribe(c[0] as String);
        if (actual != c[1])
          mismatches.add('${c[0]}\n  atteso ${c[1]}\n  ottenuto $actual');
      }
      expect(mismatches, isEmpty, reason: mismatches.take(5).join('\n'));
    });

    test('accento tonico da regole e da lessico', () {
      expect(phonemizer.transcribe('protezione'), 'proteʦiˈone');
      expect(phonemizer.transcribe('essere'), 'ˈɛSere');
      expect(phonemizer.transcribe('nucleo'), 'nˈukleo');
      expect(phonemizer.transcribe('fondendoci'), contains('ˈɛndoʧi'));
    });

    test('timbro delle vocali e sonorità della z', () {
      expect(phonemizer.transcribe('porta'), 'pˈɔrta');
      expect(phonemizer.transcribe('controllo'), 'kontrˈɔllo');
      expect(phonemizer.transcribe('analizzare'), 'analiʣːˈare');
      expect(phonemizer.transcribe('azione'), 'aʦiˈone');
      expect(phonemizer.transcribe('zona'), 'ʣˈɔna');
    });

    test('parole straniere e nomi del gioco dal lessico', () {
      expect(phonemizer.transcribe('Panopticon'), 'panˈɔptikon');
      expect(phonemizer.transcribe('PANOPTICON'), 'panˈɔptikon');
      expect(phonemizer.transcribe('escalation'), 'ˌɛskəlˈeɪʃən');
    });

    test('numerali scritti in lettere dalla normalizzazione', () {
      final expected = {
        'dodici': 'dˈodiʧi',
        'sedici': 'sˈediʧi',
        'venti': 'vˈenti',
        'sette': 'sˈɛtːe',
        'ventisette': 'ventisˈɛtːe',
        'trentasei': 'trentasˈɛj',
        'virgola': 'vˈirɡola',
        'ùno': 'ˈuno',
      };
      expected
          .forEach((w, p) => expect(phonemizer.transcribe(w), p, reason: w));
    });

    test('parole atone e punteggiatura preservata', () {
      expect(phonemizer.transcribe('non'), 'non');
      expect(phonemizer.transcribe("Perché insisti?"), endsWith('?'));
      expect(phonemizer.transcribe("dell'operatore"), isNot(contains("'")));
      expect(phonemizer.transcribe(''), '');
    });
  });
}
