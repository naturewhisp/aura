import 'package:flutter_test/flutter_test.dart';
import 'package:aura_app/src/settings/app_settings.dart';

void main() {
  group('AppSettings', () {
    group('1. Defaults esatti', () {
      test('AppSettings.defaults() restituisce i valori attesi', () {
        final s = AppSettings.defaults();
        expect(s.evaluatorModelId, equals('mistralai/ministral-3-3b'));
        expect(s.actorModelId, equals('qwen/qwen3.5-9b'));
        expect(s.reasoningEnabled, isFalse);
        expect(s.conciseReasoning, isFalse);
        expect(s.shaderEnabled, isTrue);
        expect(s.audioEnabled, isTrue);
        expect(s.defaultDifficulty, equals('standard'));
        expect(s.userCustomizedModels, isFalse);
      });
    });

    group('2. Round-trip toJson → fromJson', () {
      test('Un AppSettings round-trippato è uguale all\'originale', () {
        const original = AppSettings(
          evaluatorModelId: 'some/evaluator',
          actorModelId: 'some/actor',
          reasoningEnabled: true,
          conciseReasoning: true,
          shaderEnabled: false,
          audioEnabled: false,
          defaultDifficulty: 'hard',
          userCustomizedModels: true,
        );

        final json = original.toJson();
        final restored = AppSettings.fromJson(json);

        expect(restored, equals(original));
      });
    });

    group('3. Tutte le chiavi correnti sono presenti nel JSON', () {
      test('toJson contiene esattamente le chiavi previste', () {
        final json = AppSettings.defaults().toJson();

        expect(json.containsKey('evaluator_model_id'), isTrue);
        expect(json.containsKey('actor_model_id'), isTrue);
        expect(json.containsKey('reasoning_enabled'), isTrue);
        expect(json.containsKey('concise_reasoning'), isTrue);
        expect(json.containsKey('shader_enabled'), isTrue);
        expect(json.containsKey('audio_enabled'), isTrue);
        expect(json.containsKey('difficulty_level'), isTrue);
        expect(json.containsKey('default_difficulty'), isTrue);
        expect(json.containsKey('user_customized_models'), isTrue);
      });
    });

    group('4. Fallback da default_difficulty', () {
      test('Legge default_difficulty se presente', () {
        final s = AppSettings.fromJson({'default_difficulty': 'hard'});
        expect(s.defaultDifficulty, equals('hard'));
      });
    });

    group('5. Fallback legacy da difficulty_level', () {
      test(
          'Legge difficulty_level come fallback quando default_difficulty è assente',
          () {
        final s = AppSettings.fromJson({'difficulty_level': 'easy'});
        expect(s.defaultDifficulty, equals('easy'));
      });
    });

    group('6. Precedenza default_difficulty su difficulty_level', () {
      test('default_difficulty prevale su difficulty_level', () {
        final s = AppSettings.fromJson({
          'difficulty_level': 'easy',
          'default_difficulty': 'hard',
        });
        expect(s.defaultDifficulty, equals('hard'));
      });
    });

    group('7. Campi mancanti → default', () {
      test('fromJson con mappa vuota restituisce tutti i default', () {
        final s = AppSettings.fromJson({});
        final d = AppSettings.defaults();

        expect(s.evaluatorModelId, equals(d.evaluatorModelId));
        expect(s.actorModelId, equals(d.actorModelId));
        expect(s.reasoningEnabled, equals(d.reasoningEnabled));
        expect(s.conciseReasoning, equals(d.conciseReasoning));
        expect(s.shaderEnabled, equals(d.shaderEnabled));
        expect(s.audioEnabled, equals(d.audioEnabled));
        expect(s.defaultDifficulty, equals(d.defaultDifficulty));
        expect(s.userCustomizedModels, equals(d.userCustomizedModels));
      });
    });

    group('8. user_customized_models', () {
      test('Legge user_customized_models = true', () {
        final s = AppSettings.fromJson({'user_customized_models': true});
        expect(s.userCustomizedModels, isTrue);
      });

      test('Legge user_customized_models = false', () {
        final s = AppSettings.fromJson({'user_customized_models': false});
        expect(s.userCustomizedModels, isFalse);
      });
    });

    group('9. Tipi errati producono FormatException', () {
      test('evaluator_model_id int → FormatException', () {
        expect(
          () => AppSettings.fromJson({'evaluator_model_id': 42}),
          throwsA(isA<FormatException>()),
        );
      });

      test('actor_model_id bool → FormatException', () {
        expect(
          () => AppSettings.fromJson({'actor_model_id': true}),
          throwsA(isA<FormatException>()),
        );
      });

      test('reasoning_enabled stringa → FormatException', () {
        expect(
          () => AppSettings.fromJson({'reasoning_enabled': 'yes'}),
          throwsA(isA<FormatException>()),
        );
      });

      test('shader_enabled int → FormatException', () {
        expect(
          () => AppSettings.fromJson({'shader_enabled': 1}),
          throwsA(isA<FormatException>()),
        );
      });

      test('default_difficulty int → FormatException', () {
        expect(
          () => AppSettings.fromJson({'default_difficulty': 99}),
          throwsA(isA<FormatException>()),
        );
      });

      test('difficulty_level (legacy) int → FormatException', () {
        expect(
          () => AppSettings.fromJson({'difficulty_level': 99}),
          throwsA(isA<FormatException>()),
        );
      });

      test('user_customized_models stringa → FormatException', () {
        expect(
          () => AppSettings.fromJson({'user_customized_models': 'true'}),
          throwsA(isA<FormatException>()),
        );
      });
    });

    group('10. toJson scrive sia difficulty_level che default_difficulty', () {
      test('Entrambe le chiavi hanno il valore corretto', () {
        const s = AppSettings(
          evaluatorModelId: 'e',
          actorModelId: 'a',
          reasoningEnabled: false,
          conciseReasoning: false,
          shaderEnabled: true,
          audioEnabled: true,
          defaultDifficulty: 'hard',
          userCustomizedModels: false,
        );
        final json = s.toJson();

        expect(json['difficulty_level'], equals('hard'));
        expect(json['default_difficulty'], equals('hard'));
      });
    });

    group('copyWith', () {
      test('copyWith modifica solo il campo specificato', () {
        final original = AppSettings.defaults();
        final modified = original.copyWith(shaderEnabled: false);

        expect(modified.shaderEnabled, isFalse);
        expect(modified.audioEnabled, equals(original.audioEnabled));
        expect(modified.evaluatorModelId, equals(original.evaluatorModelId));
      });
    });

    group('userDisplayName & clearUserDisplayName', () {
      test('copyWith con userDisplayName valorizzato aggiorna il nome', () {
        final original = AppSettings.defaults();
        final custom = original.copyWith(userDisplayName: 'Davide');
        expect(custom.userDisplayName, equals('Davide'));
      });

      test('copyWith senza userDisplayName mantiene il valore precedente', () {
        final custom =
            AppSettings.defaults().copyWith(userDisplayName: 'Davide');
        final modified = custom.copyWith(shaderEnabled: false);
        expect(modified.userDisplayName, equals('Davide'));
      });

      test('copyWith con userDisplayName: null cancella il nome salvato', () {
        final custom =
            AppSettings.defaults().copyWith(userDisplayName: 'Davide');
        final cleared = custom.copyWith(userDisplayName: null);
        expect(cleared.userDisplayName, isNull);
      });

      test('clearUserDisplayName ripristina il nome a null', () {
        final custom =
            AppSettings.defaults().copyWith(userDisplayName: 'Davide');
        final cleared = custom.clearUserDisplayName();
        expect(cleared.userDisplayName, isNull);
      });

      test('toJson omette user_display_name quando è nullo o vuoto', () {
        final defaultJson = AppSettings.defaults().toJson();
        expect(defaultJson.containsKey('user_display_name'), isFalse);

        final customJson =
            AppSettings.defaults().copyWith(userDisplayName: 'Davide').toJson();
        expect(customJson['user_display_name'], equals('Davide'));
      });
    });

    group('equality e hashCode', () {
      test('Due istanze con gli stessi valori sono uguali', () {
        final a = AppSettings.defaults();
        final b = AppSettings.defaults();
        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });

      test('Istanze con valori diversi non sono uguali', () {
        final a = AppSettings.defaults();
        final b = a.copyWith(shaderEnabled: false);
        expect(a, isNot(equals(b)));
      });
    });
  });
}
