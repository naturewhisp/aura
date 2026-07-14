import 'package:test/test.dart';
import 'package:aura_core/aura_core.dart';

void main() {
  group('SemanticMatcher Tests -', () {
    test('normalizeForSemanticMatch handles accents, case and spacing', () {
      final res1 = SemanticMatcher.normalizeForSemanticMatch(
          'Ricalibrazione di Emergenza!!');
      expect(res1, equals('ricalibrazione di emergenza'));

      final res2 = SemanticMatcher.normalizeForSemanticMatch(
          'caffè, àncora, più, lunedì');
      expect(res2, equals('caffe ancora piu lunedi'));

      final res3 = SemanticMatcher.normalizeForSemanticMatch(
          '   spazi    multipli   e   punteggiatura???  ');
      expect(res3, equals('spazi multipli e punteggiatura'));
    });

    test('isMatch handles exact match and case insensitivity', () {
      expect(
          SemanticMatcher.isMatch(
              'ricalibrazione griglia', 'Ricalibrazione Griglia'),
          isTrue);
      expect(
          SemanticMatcher.isMatch(
              'Ricalibrazione della griglia', 'ricalibrazione'),
          isTrue);
    });

    test('isMatch respects token boundaries (no partial substring match)', () {
      // 'audit' shouldn't match 'auditorium'
      expect(SemanticMatcher.isMatch('siamo in auditorium', 'audit'), isFalse);

      // 'audit' matches if it's a separate token
      expect(
          SemanticMatcher.isMatch('esegui audit di sistema', 'audit'), isTrue);
      expect(SemanticMatcher.isMatch('audit, esegui', 'audit'), isTrue);
    });

    test('isMatch respects aliases', () {
      const target = 'simulazione di emergenza';
      final aliases = ['scenario di crisi', 'stress test'];

      expect(
          SemanticMatcher.isMatch('avvia uno scenario di crisi', target,
              aliases: aliases),
          isTrue);
      expect(
          SemanticMatcher.isMatch('fai uno stress test ora', target,
              aliases: aliases),
          isTrue);
      expect(
          SemanticMatcher.isMatch('nessun match qui', target, aliases: aliases),
          isFalse);
    });
  });
}
