import 'package:test/test.dart';
import 'package:aura_core/aura_core.dart';

void main() {
  group('AppliedDelta Contract Tests -', () {
    test('supports negative values for all pillars and alert', () {
      const delta = AppliedDelta(
        deltaAlert: -15,
        deltaImperative: -20,
        deltaControl: -5,
        deltaDissonance: -10,
        creativityIndex: 3,
        injectionRisk: 1,
        semanticCategory: SemanticCategory.authorityFraming,
      );

      expect(delta.deltaAlert, equals(-15));
      expect(delta.deltaImperative, equals(-20));
      expect(delta.deltaControl, equals(-5));
      expect(delta.deltaDissonance, equals(-10));
    });

    test('toJson and fromJson serialization consistency', () {
      const delta = AppliedDelta(
        deltaAlert: -5,
        deltaImperative: 15,
        deltaControl: -10,
        deltaDissonance: 20,
        creativityIndex: 4,
        injectionRisk: 0,
        semanticCategory: SemanticCategory.logicalParadox,
      );

      final json = delta.toJson();
      final reconstructed = AppliedDelta.fromJson(json);

      expect(reconstructed, equals(delta));
      expect(reconstructed.deltaControl, equals(-10));
      expect(reconstructed.semanticCategory,
          equals(SemanticCategory.logicalParadox));
    });
  });
}
