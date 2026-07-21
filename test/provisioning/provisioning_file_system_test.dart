import 'dart:io';
import 'package:aura_core/aura_core.dart';
import 'package:test/test.dart';

void main() {
  group('LocalProvisioningFileSystem Tests -', () {
    late Directory tempDir;
    late LocalProvisioningFileSystem fileSystem;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('aura_fs_test_');
      fileSystem = const LocalProvisioningFileSystem();
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
        'Scrive atomicamente un file creando il backup .bak se il file esisteva già',
        () async {
      final targetPath = '${tempDir.path}\\test_file.json';

      // Prima scrittura atomica
      await fileSystem.writeStringAtomic(targetPath, '{"version": 1}');
      expect(await fileSystem.fileExists(targetPath), isTrue);
      expect(
          await fileSystem.readAsString(targetPath), equals('{"version": 1}'));

      // Seconda scrittura atomica -> genera il backup .bak
      await fileSystem.writeStringAtomic(targetPath, '{"version": 2}');
      expect(
          await fileSystem.readAsString(targetPath), equals('{"version": 2}'));

      final backupPath = '$targetPath.bak';
      expect(await fileSystem.fileExists(backupPath), isTrue);
      expect(
          await fileSystem.readAsString(backupPath), equals('{"version": 1}'));
    });
  });
}
