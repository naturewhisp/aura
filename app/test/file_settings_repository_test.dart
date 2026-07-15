import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:aura_app/src/settings/app_settings.dart';
import 'package:aura_app/src/settings/file_settings_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late FileSettingsRepository repo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('aura_settings_test_');
    repo = FileSettingsRepository(basePath: tempDir.path);
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('FileSettingsRepository', () {
    test('1. load restituisce null se settings.json non esiste', () async {
      final result = await repo.load();
      expect(result, isNull);
    });

    test('2. save crea la directory se non esiste', () async {
      final subDir = Directory('${tempDir.path}/sub/dir');
      final repoInSub = FileSettingsRepository(basePath: subDir.path);

      await repoInSub.save(AppSettings.defaults());

      expect(subDir.existsSync(), isTrue);
    });

    test('3. save crea settings.json', () async {
      await repo.save(AppSettings.defaults());

      final file = File('${tempDir.path}/settings.json');
      expect(file.existsSync(), isTrue);
    });

    test('4. load dopo save restituisce lo stesso aggregate', () async {
      const original = AppSettings(
        evaluatorModelId: 'test/evaluator',
        actorModelId: 'test/actor',
        reasoningEnabled: true,
        conciseReasoning: false,
        shaderEnabled: false,
        audioEnabled: false,
        defaultDifficulty: 'hard',
        userCustomizedModels: true,
      );

      await repo.save(original);
      final loaded = await repo.load();

      expect(loaded, equals(original));
    });

    test('5. File legacy con solo difficulty_level', () async {
      final file = File('${tempDir.path}/settings.json');
      await file.writeAsString('{"difficulty_level":"easy"}');

      final loaded = await repo.load();
      expect(loaded, isNotNull);
      expect(loaded!.defaultDifficulty, equals('easy'));
    });

    test('6. JSON malformato propaga FormatException', () async {
      final file = File('${tempDir.path}/settings.json');
      await file.writeAsString('{ invalid json }');

      expect(
        () async => await repo.load(),
        throwsA(isA<FormatException>()),
      );
    });

    test('7a. Root JSON array [] propaga FormatException', () async {
      final file = File('${tempDir.path}/settings.json');
      await file.writeAsString('[1, 2, 3]');

      expect(
        () async => await repo.load(),
        throwsA(isA<FormatException>()),
      );
    });

    test('7b. Root JSON stringa propaga FormatException', () async {
      final file = File('${tempDir.path}/settings.json');
      await file.writeAsString('"solo una stringa"');

      expect(
        () async => await repo.load(),
        throwsA(isA<FormatException>()),
      );
    });

    test('7c. Root JSON numero propaga FormatException', () async {
      final file = File('${tempDir.path}/settings.json');
      await file.writeAsString('123');

      expect(
        () async => await repo.load(),
        throwsA(isA<FormatException>()),
      );
    });

    test('8. Tipo errato di una chiave propaga FormatException', () async {
      final file = File('${tempDir.path}/settings.json');
      await file.writeAsString('{"shader_enabled": "yes"}');

      expect(
        () async => await repo.load(),
        throwsA(isA<FormatException>()),
      );
    });

    test('9. Sovrascrittura di un file esistente', () async {
      final first = AppSettings.defaults();
      await repo.save(first);

      final second = first.copyWith(defaultDifficulty: 'hard');
      await repo.save(second);

      final loaded = await repo.load();
      expect(loaded!.defaultDifficulty, equals('hard'));
    });
  });
}
