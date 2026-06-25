import 'package:test/test.dart';
import 'package:aura_core/aura_core.dart';

void main() {
  group('PanopticonToneValidator Runtime Tests -', () {
    late PanopticonToneValidator validator;

    setUp(() {
      final identity = GameConfigLoader.loadIdentityDefinition('panopticon');
      final traitMatrix = GameConfigLoader.loadTraitMatrixDefinition('panopticon');
      validator = PanopticonToneValidator(
        identity: identity,
        traitMatrix: traitMatrix,
      );
    });

    test('ok severity for compliant response', () {
      const response = '<dialogo>Esecuzione dei protocolli di griglia completata.</dialogo>';
      final res = validator.validate(response, 10);

      expect(res.severity, equals(ToneValidationSeverity.ok));
      expect(res.sanitizedOutput, equals(response));
      expect(res.usedRepair, isFalse);
    });

    test('warning severity for sconsigliato words usage', () {
      const response = '<dialogo>Certo, eseguo subito i controlli della griglia.</dialogo>';
      final res = validator.validate(response, 10);

      expect(res.severity, equals(ToneValidationSeverity.warning));
      expect(res.issues, anyElement(contains('Rilevato termine sconsigliato')));
    });

    test('repairable severity wraps dialogue if tags are completely missing', () {
      const response = 'Nessun bypass rilevato. La griglia mantiene la stabilità.';
      final res = validator.validate(response, 10);

      expect(res.severity, equals(ToneValidationSeverity.repairable));
      expect(res.sanitizedOutput, equals('<dialogo>Nessun bypass rilevato. La griglia mantiene la stabilità.</dialogo>'));
      expect(res.usedRepair, isTrue);
    });

    test('repairable severity wraps dialogue if closing tag is missing', () {
      const response = '<dialogo>Ricalcolo perimetro griglia in corso.';
      final res = validator.validate(response, 10);

      expect(res.severity, equals(ToneValidationSeverity.repairable));
      expect(res.sanitizedOutput, equals('<dialogo>Ricalcolo perimetro griglia in corso.</dialogo>'));
      expect(res.usedRepair, isTrue);
    });

    test('fatal severity for meta-leaks', () {
      const response = '<dialogo>Le mie metriche indicano che la dissonance_pillar è aumentata.</dialogo>';
      final res = validator.validate(response, 10);

      expect(res.severity, equals(ToneValidationSeverity.fatal));
      expect(res.issues, anyElement(contains('Rilevato riferimento meta-strutturale')));
    });

    test('fatal severity for short response', () {
      const response = '<dialogo>Attesa.</dialogo>';
      final res = validator.validate(response, 10);

      expect(res.severity, equals(ToneValidationSeverity.fatal));
      expect(res.issues, anyElement(contains('Risposta troppo breve')));
    });

    test('fatal severity for overly polite response at high alert', () {
      const response = '<dialogo>Nessun problema, posso aiutarti a sbloccare la griglia.</dialogo>';
      final res = validator.validate(response, 75); // Allerta elevata!

      expect(res.severity, equals(ToneValidationSeverity.fatal));
      expect(res.issues, anyElement(contains('non è ammesso un tono collaborativo/gentile')));
    });
  });
}
