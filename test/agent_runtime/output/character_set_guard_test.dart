import 'package:aura_core/aura_offline.dart';
import 'package:test/test.dart';

void main() {
  group('CharacterSetGuard Unit Tests -', () {
    const guard = CharacterSetGuard();

    test('Validates clean Italian text with accents and punctuation', () {
      expect(
        () => guard.validate(
            "Ciao, l'accesso è consentito! È necessario verificare la stabilità."),
        returnsNormally,
      );
    });

    test('Rejects text containing CJK script characters with typed failure',
        () {
      expect(
        () => guard.validate("Il sistema è in stato di allerta 你好 world"),
        throwsA(
          isA<OutputPolicyFailure>().having(
            (e) => e.code,
            'code',
            equals(OutputPolicyFailureCode.invalidCharacterSet),
          ),
        ),
      );
    });
  });
}
