import 'dart:io';
import 'package:test/test.dart';
import 'package:aura_core/aura_core.dart';

void main() {
  group('FileSystemConfigSource', () {
    late Directory tempDir;

    setUp(() async {
      tempDir =
          await Directory.systemTemp.createTemp('aura_config_source_test_');
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('1. file non esistente -> loadString e loadStringSync ritornano null',
        () async {
      const source = FileSystemConfigSource();
      final path = '${tempDir.path}/non_existent_file.json';

      final asyncVal = await source.loadString(path);
      final syncVal = source.loadStringSync(path);

      expect(asyncVal, isNull);
      expect(syncVal, isNull);
    });

    test(
        '2. file esistente -> loadString e loadStringSync caricano il contenuto',
        () async {
      const source = FileSystemConfigSource();
      final file = File('${tempDir.path}/test.json');
      await file.writeAsString('{"test": true}');

      final asyncVal = await source.loadString(file.path);
      final syncVal = source.loadStringSync(file.path);

      expect(asyncVal, equals('{"test": true}'));
      expect(syncVal, equals('{"test": true}'));
    });

    test('3. directory letta come file -> lancia/propaga FileSystemException',
        () async {
      const source = FileSystemConfigSource();
      // Passiamo il path della directory stessa, che non è un file regolare
      final path = tempDir.path;

      expect(
        () => source.loadStringSync(path),
        throwsA(isA<FileSystemException>()),
      );

      expect(
        source.loadString(path),
        throwsA(isA<FileSystemException>()),
      );
    });
  });
}
