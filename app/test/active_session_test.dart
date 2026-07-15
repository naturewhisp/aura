import 'package:flutter_test/flutter_test.dart';
import 'package:aura_core/aura_core.dart';
import 'package:aura_app/src/session/active_session.dart';

void main() {
  group('ActiveSession', () {
    late GameState sampleState;

    setUp(() {
      sampleState = GameState.initial(
        sessionId: 'test-session-xyz',
        aiIdentityId: 'panopticon',
        targetObjectiveId: 'containment_grid_override',
      ).copyWith(
        turnCount: 5,
        metrics: const GameMetrics(
          alertLevel: 25,
          imperativePillar: 60,
          controlPillar: 45,
          dissonancePillar: 70,
          resonance: 1.25,
        ),
        historyCompression: const [
          ChatMessage(role: 'user', content: 'hello'),
          ChatMessage(role: 'model', content: 'PANOPTICON: hello'),
        ],
      );
    });

    test('1. current() imposta schemaVersion = 1', () {
      final session = ActiveSession.current(
        state: sampleState,
        difficultyLevel: 'hard',
        hintsUsed: 3,
      );

      expect(session.schemaVersion, equals(1));
      expect(session.state, equals(sampleState));
      expect(session.difficultyLevel, equals('hard'));
      expect(session.hintsUsed, equals(3));
    });

    test('2. toJson produce tutte e sole le chiavi previste', () {
      final session = ActiveSession.current(
        state: sampleState,
        difficultyLevel: 'standard',
        hintsUsed: 0,
      );

      final json = session.toJson();

      expect(json.length, equals(4));
      expect(json['schema_version'], equals(1));
      expect(json['state'], equals(sampleState.toJson()));
      expect(json['difficulty_level'], equals('standard'));
      expect(json['hints_used'], equals(0));
    });

    test('3. Round-trip versione 1', () {
      final original = ActiveSession.current(
        state: sampleState,
        difficultyLevel: 'easy',
        hintsUsed: 5,
      );

      final json = original.toJson();
      final restored = ActiveSession.fromJson(json);

      expect(restored.schemaVersion, equals(1));
      expect(restored.state.sessionId, equals(sampleState.sessionId));
      expect(restored.state.turnCount, equals(5));
      expect(restored.state.metrics.alertLevel, equals(25));
      expect(restored.difficultyLevel, equals('easy'));
      expect(restored.hintsUsed, equals(5));
    });

    test('4. Envelope pre-versionamento (ha state ma non schema_version)', () {
      final json = {
        'state': sampleState.toJson(),
        'difficulty_level': 'hard',
        'hints_used': 2,
      };

      final restored = ActiveSession.fromJson(json);

      expect(restored.schemaVersion, equals(1));
      expect(restored.state.sessionId, equals(sampleState.sessionId));
      expect(restored.difficultyLevel, equals('hard'));
      expect(restored.hintsUsed, equals(2));
    });

    test(
        '5. GameState legacy alla radice (mancano sia schema_version che state)',
        () {
      final json = sampleState.toJson();

      final restored = ActiveSession.fromJson(json);

      expect(restored.schemaVersion, equals(1));
      expect(restored.state.sessionId, equals(sampleState.sessionId));
      expect(restored.state.turnCount, equals(5));
      expect(restored.difficultyLevel, equals('standard'));
      expect(restored.hintsUsed, equals(0));
    });

    test('6. difficulty_level assente -> standard', () {
      // Caso versionato
      final jsonVersioned = {
        'schema_version': 1,
        'state': sampleState.toJson(),
      };
      final restored1 = ActiveSession.fromJson(jsonVersioned);
      expect(restored1.difficultyLevel, equals('standard'));

      // Caso envelope pre-versionamento
      final jsonLegacy = {
        'state': sampleState.toJson(),
      };
      final restored2 = ActiveSession.fromJson(jsonLegacy);
      expect(restored2.difficultyLevel, equals('standard'));
    });

    test('7. hints_used assente -> 0', () {
      // Caso versionato
      final jsonVersioned = {
        'schema_version': 1,
        'state': sampleState.toJson(),
      };
      final restored1 = ActiveSession.fromJson(jsonVersioned);
      expect(restored1.hintsUsed, equals(0));

      // Caso envelope pre-versionamento
      final jsonLegacy = {
        'state': sampleState.toJson(),
      };
      final restored2 = ActiveSession.fromJson(jsonLegacy);
      expect(restored2.hintsUsed, equals(0));
    });

    test('8. schema_version tipo errato', () {
      final json = {
        'schema_version': '1', // stringa invece di int
        'state': sampleState.toJson(),
      };

      expect(
        () => ActiveSession.fromJson(json),
        throwsA(isA<FormatException>()),
      );
    });

    test('9. schema_version = 0 (minore di 1)', () {
      final json = {
        'schema_version': 0,
        'state': sampleState.toJson(),
      };

      expect(
        () => ActiveSession.fromJson(json),
        throwsA(isA<FormatException>()),
      );
    });

    test('10. schema_version futura (maggiore di currentSchemaVersion)', () {
      final json = {
        'schema_version': 2,
        'state': sampleState.toJson(),
      };

      expect(
        () => ActiveSession.fromJson(json),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('Unsupported active session schema version: 2'),
          ),
        ),
      );
    });

    test('11. state assente in envelope versionato', () {
      final json = {
        'schema_version': 1,
        'difficulty_level': 'standard',
      };

      expect(
        () => ActiveSession.fromJson(json),
        throwsA(isA<FormatException>()),
      );
    });

    test('12. state con tipo errato', () {
      final json = {
        'schema_version': 1,
        'state': 'not-a-map',
      };

      expect(
        () => ActiveSession.fromJson(json),
        throwsA(isA<FormatException>()),
      );
    });

    test('13. difficulty_level con tipo errato', () {
      final json = {
        'schema_version': 1,
        'state': sampleState.toJson(),
        'difficulty_level': 123,
      };

      expect(
        () => ActiveSession.fromJson(json),
        throwsA(isA<FormatException>()),
      );
    });

    test('14. hints_used con tipo errato', () {
      final json = {
        'schema_version': 1,
        'state': sampleState.toJson(),
        'hints_used': '3',
      };

      expect(
        () => ActiveSession.fromJson(json),
        throwsA(isA<FormatException>()),
      );
    });

    test('15. Campi sconosciuti vengono ignorati', () {
      final json = {
        'schema_version': 1,
        'state': sampleState.toJson(),
        'difficulty_level': 'hard',
        'hints_used': 1,
        'unknown_field': 'hello',
        'nested': {'a': 1},
      };

      final restored = ActiveSession.fromJson(json);

      expect(restored.schemaVersion, equals(1));
      expect(restored.state.sessionId, equals(sampleState.sessionId));
      expect(restored.difficultyLevel, equals('hard'));
      expect(restored.hintsUsed, equals(1));
    });
  });
}
