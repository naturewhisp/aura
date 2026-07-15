import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:aura_core/aura_core.dart';
import 'package:aura_app/src/session/active_session.dart';
import 'package:aura_app/src/session/file_session_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late FileSessionRepository repo;
  late GameState sampleState;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('aura_session_test_');
    repo = FileSessionRepository(basePath: tempDir.path);
    sampleState = GameState.initial(
      sessionId: 'repo-session-xyz',
      aiIdentityId: 'panopticon',
      targetObjectiveId: 'containment_grid_override',
    );
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('FileSessionRepository', () {
    test('1. exists false se file assente', () async {
      final exists = await repo.exists();
      expect(exists, isFalse);
    });

    test('2. load null se file assente', () async {
      final result = await repo.load();
      expect(result, isNull);
    });

    test('3. save crea directory', () async {
      final subDir = Directory('${tempDir.path}/deep/nested/dir');
      final nestedRepo = FileSessionRepository(basePath: subDir.path);

      final session = ActiveSession.current(
        state: sampleState,
        difficultyLevel: 'standard',
        hintsUsed: 0,
      );

      await nestedRepo.save(session);
      expect(subDir.existsSync(), isTrue);
    });

    test('4. save crea active_session.json', () async {
      final session = ActiveSession.current(
        state: sampleState,
        difficultyLevel: 'hard',
        hintsUsed: 1,
      );

      await repo.save(session);

      final file = File('${tempDir.path}/active_session.json');
      expect(file.existsSync(), isTrue);
    });

    test('5. il JSON scritto contiene schema_version = 1', () async {
      final session = ActiveSession.current(
        state: sampleState,
        difficultyLevel: 'hard',
        hintsUsed: 1,
      );

      await repo.save(session);

      final file = File('${tempDir.path}/active_session.json');
      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;

      expect(json['schema_version'], equals(1));
      expect(json['difficulty_level'], equals('hard'));
      expect(json['hints_used'], equals(1));
    });

    test('6. save/load round-trip', () async {
      final session = ActiveSession.current(
        state: sampleState.copyWith(turnCount: 12),
        difficultyLevel: 'easy',
        hintsUsed: 4,
      );

      await repo.save(session);
      final loaded = await repo.load();

      expect(loaded, isNotNull);
      expect(loaded!.schemaVersion, equals(1));
      expect(loaded.state.sessionId, equals(sampleState.sessionId));
      expect(loaded.state.turnCount, equals(12));
      expect(loaded.difficultyLevel, equals('easy'));
      expect(loaded.hintsUsed, equals(4));
    });

    test('7. sovrascrittura file esistente', () async {
      final first = ActiveSession.current(
        state: sampleState,
        difficultyLevel: 'standard',
        hintsUsed: 0,
      );
      await repo.save(first);

      final second = ActiveSession.current(
        state: sampleState.copyWith(turnCount: 2),
        difficultyLevel: 'hard',
        hintsUsed: 5,
      );
      await repo.save(second);

      final loaded = await repo.load();
      expect(loaded!.state.turnCount, equals(2));
      expect(loaded.difficultyLevel, equals('hard'));
      expect(loaded.hintsUsed, equals(5));
    });

    test('8. delete file esistente', () async {
      final session = ActiveSession.current(
        state: sampleState,
        difficultyLevel: 'standard',
        hintsUsed: 0,
      );
      await repo.save(session);

      final file = File('${tempDir.path}/active_session.json');
      expect(file.existsSync(), isTrue);

      await repo.delete();
      expect(file.existsSync(), isFalse);
      expect(await repo.exists(), isFalse);
    });

    test('9. delete idempotente (file assente non lancia errori)', () async {
      final file = File('${tempDir.path}/active_session.json');
      expect(file.existsSync(), isFalse);

      await expectLater(repo.delete(), completes);
    });

    test('10. envelope legacy caricato correttamente', () async {
      final legacyEnvelope = {
        'state': sampleState.toJson(),
        'difficulty_level': 'easy',
        'hints_used': 2,
      };

      final file = File('${tempDir.path}/active_session.json');
      await file.writeAsString(jsonEncode(legacyEnvelope));

      final loaded = await repo.load();
      expect(loaded, isNotNull);
      expect(loaded!.schemaVersion, equals(1));
      expect(loaded.state.sessionId, equals(sampleState.sessionId));
      expect(loaded.difficultyLevel, equals('easy'));
      expect(loaded.hintsUsed, equals(2));
    });

    test('11. raw GameState legacy caricato correttamente', () async {
      final file = File('${tempDir.path}/active_session.json');
      await file.writeAsString(jsonEncode(sampleState.toJson()));

      final loaded = await repo.load();
      expect(loaded, isNotNull);
      expect(loaded!.schemaVersion, equals(1));
      expect(loaded.state.sessionId, equals(sampleState.sessionId));
      expect(loaded.difficultyLevel, equals('standard'));
      expect(loaded.hintsUsed, equals(0));
    });

    test('12. JSON malformato propaga FormatException', () async {
      final file = File('${tempDir.path}/active_session.json');
      await file.writeAsString('{ malformed json ');

      expect(
        () async => await repo.load(),
        throwsA(isA<FormatException>()),
      );
    });

    test('13a. Root JSON array [] propaga FormatException', () async {
      final file = File('${tempDir.path}/active_session.json');
      await file.writeAsString('[1, 2, 3]');

      expect(
        () async => await repo.load(),
        throwsA(isA<FormatException>()),
      );
    });

    test('13b. Root JSON stringa propaga FormatException', () async {
      final file = File('${tempDir.path}/active_session.json');
      await file.writeAsString('"active-session-text"');

      expect(
        () async => await repo.load(),
        throwsA(isA<FormatException>()),
      );
    });

    test('13c. Root JSON numero propaga FormatException', () async {
      final file = File('${tempDir.path}/active_session.json');
      await file.writeAsString('12345');

      expect(
        () async => await repo.load(),
        throwsA(isA<FormatException>()),
      );
    });

    test('14. versione futura propaga FormatException', () async {
      final file = File('${tempDir.path}/active_session.json');
      final futureEnvelope = {
        'schema_version': 2,
        'state': sampleState.toJson(),
      };
      await file.writeAsString(jsonEncode(futureEnvelope));

      expect(
        () async => await repo.load(),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('Unsupported active session schema version: 2'),
          ),
        ),
      );
    });
  });
}
