import 'package:aura_core/aura_core.dart';
import 'package:test/test.dart';

void main() {
  group('UserProfile Tests', () {
    test(
        'Default e fallback restituiscono "Tu" per valori nulli, vuoti o spazi',
        () {
      expect(UserProfile.resolve(null), equals('Tu'));
      expect(UserProfile.resolve(''), equals('Tu'));
      expect(UserProfile.resolve('   '), equals('Tu'));

      final defaultProfile = UserProfile();
      expect(defaultProfile.displayName, isNull);
      expect(defaultProfile.effectiveDisplayName, equals('Tu'));
    });

    test('Normalizza e restituisce il nome personalizzato valido', () {
      expect(UserProfile.resolve('  Davide  '), equals('Davide'));
      final customProfile =
          UserProfile(displayName: UserProfile.normalize('  Alice  '));
      expect(customProfile.displayName, equals('Alice'));
      expect(customProfile.effectiveDisplayName, equals('Alice'));
    });

    test(
        'Validazione accetta nomi Unicode, emoji e accenti entro 32 grapheme cluster',
        () {
      expect(UserProfile.validate('Davide').isValid, isTrue);
      expect(UserProfile.validate('N3XUS 🤖').isValid, isTrue);
      expect(UserProfile.validate('ユーザー').isValid, isTrue);
      expect(UserProfile.validate('Davide 🜏').isValid, isTrue);
      expect(UserProfile.validate('Éléonore').isValid, isTrue);
    });

    test('Validazione rifiuta stringhe oltre 32 grapheme cluster', () {
      final longName = 'A' * 33;
      final res = UserProfile.validate(longName);
      expect(res.isValid, isFalse);
      expect(res.errorMessage, contains('superare i 32 caratteri'));
    });

    test('Validazione rifiuta newline, ritorni di carrello e tab', () {
      expect(UserProfile.validate('Davide\nAURA').isValid, isFalse);
      expect(UserProfile.validate('Davide\rAURA').isValid, isFalse);
      expect(UserProfile.validate('Davide\tAURA').isValid, isFalse);
    });

    test('Validazione rifiuta sequenze ANSI e caratteri di controllo', () {
      expect(UserProfile.validate('\x1B[31mDavide').isValid, isFalse);
      expect(UserProfile.validate('Davide\x07').isValid, isFalse);
    });

    test('Validazione rifiuta UTF-16 lone surrogates', () {
      final loneHigh = String.fromCharCodes([0xD83D]);
      final loneLow = String.fromCharCodes([0xDE00]);
      expect(UserProfile.validate(loneHigh).isValid, isFalse);
      expect(UserProfile.validate(loneLow).isValid, isFalse);
    });

    test(
        'Costruttore UserProfile valida ed esegue il throw di ArgumentError per stringhe non valide',
        () {
      expect(
          () => UserProfile(displayName: 'Davide\nAURA'), throwsArgumentError);
      expect(() => UserProfile(displayName: '\x1B[31mDavide'),
          throwsArgumentError);
    });
  });

  group('ChatMessage & ReplayEntry displayNameSnapshot Tests', () {
    test('ChatMessage.user popola displayNameSnapshot solo per ruoli user', () {
      final userMsg = ChatMessage.user(
        content: 'Ciao',
        displayNameSnapshot: '  Davide  ',
      );
      expect(userMsg.role, equals('user'));
      expect(userMsg.displayNameSnapshot, equals('Davide'));

      final modelMsg = ChatMessage.model(content: 'Risposta');
      expect(modelMsg.role, equals('model'));
      expect(modelMsg.displayNameSnapshot, isNull);
    });

    test(
        'ChatMessage serializza e deserializza display_name_snapshot con retrocompatibilità',
        () {
      final userMsg =
          ChatMessage.user(content: 'Test', displayNameSnapshot: 'Davide');
      final json = userMsg.toJson();
      expect(json['display_name_snapshot'], equals('Davide'));

      final restored = ChatMessage.fromJson(json);
      expect(restored.displayNameSnapshot, equals('Davide'));

      // Vecchio JSON senza display_name_snapshot
      final legacyJson = {'role': 'user', 'content': 'Vecchio'};
      final legacyMsg = ChatMessage.fromJson(legacyJson);
      expect(legacyMsg.displayNameSnapshot, isNull);
      expect(UserProfile.resolve(legacyMsg.displayNameSnapshot), equals('Tu'));
    });

    test(
        'ReplayEntry serializza e deserializza display_name_snapshot solo per user_turn',
        () {
      final entry = ReplayEntry(
        turnId: 1,
        userInput: 'Analizza',
        displayNameSnapshot: 'Davide',
        evaluatorOutput: const EvaluatorDelta(
          deltaAlert: 0,
          deltaImperative: 0,
          deltaControl: 0,
          deltaDissonance: 0,
          creativityIndex: 5,
          injectionRisk: 0,
          semanticCategory: SemanticCategory.authorityFraming,
        ),
        stateBefore: const {},
        stateAfter: const {},
        actorResponse: 'In corso',
        actorRequestId: 'req-1',
        actorResponseHash: 'hash-1',
        evaluatorModel: 'eval-m',
        actorModel: 'act-m',
        latencyTotalMs: 100,
        eventType: ReplayEventType.userTurn,
      );

      final json = entry.toJson();
      expect(json['display_name_snapshot'], equals('Davide'));

      final restored = ReplayEntry.fromJson(json);
      expect(restored.displayNameSnapshot, equals('Davide'));
    });
  });
}
