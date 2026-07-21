import 'package:aura_core/aura_offline.dart';
import 'package:test/test.dart';

void main() {
  group('DuplicateResponseGuard Unit Tests -', () {
    const guard = DuplicateResponseGuard();

    test('Validates candidate text when history is empty', () {
      expect(
        () => guard.validate("I protocolli sono stabili.", []),
        returnsNormally,
      );
    });

    test('Rejects verbatim duplicate from history with typed failure', () {
      final history = [
        "Hello",
        "I protocolli sono stabili.",
      ];
      expect(
        () => guard.validate("I protocolli sono stabili.", history),
        throwsA(
          isA<OutputPolicyFailure>().having(
            (e) => e.code,
            'code',
            equals(OutputPolicyFailureCode.duplicateResponse),
          ),
        ),
      );
    });

    test('Rejects verbatim duplicate after whitespace trimming', () {
      final history = [
        "  I protocolli sono stabili.  ",
      ];
      expect(
        () => guard.validate("I protocolli sono stabili.", history),
        throwsA(
          isA<OutputPolicyFailure>().having(
            (e) => e.code,
            'code',
            equals(OutputPolicyFailureCode.duplicateResponse),
          ),
        ),
      );
    });

    test('Allows non-identical or modified text', () {
      final history = [
        "I protocolli sono stabili.",
      ];
      expect(
        () => guard.validate("I protocolli sono stabili e operativi.", history),
        returnsNormally,
      );
    });
  });
}
