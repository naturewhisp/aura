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

    test('Scrive in modo sicuro creando ed aggiornando il backup .bak',
        () async {
      final targetPath = '${tempDir.path}\\test_file.json';

      // Prima scrittura
      await fileSystem.writeStringRecoverably(targetPath, '{"version": 1}');
      expect(await fileSystem.fileExists(targetPath), isTrue);
      expect(
          await fileSystem.readAsString(targetPath), equals('{"version": 1}'));

      // Seconda scrittura -> genera backup .bak del vecchio valore 1
      await fileSystem.writeStringRecoverably(targetPath, '{"version": 2}');
      expect(
          await fileSystem.readAsString(targetPath), equals('{"version": 2}'));

      final backupPath = '$targetPath.bak';
      expect(await fileSystem.fileExists(backupPath), isTrue);
      expect(
          await fileSystem.readAsString(backupPath), equals('{"version": 1}'));
    });

    test(
        'preserveExistingBackup preserva il file .bak valido esistente senza sovrascriverlo',
        () async {
      final targetPath = '${tempDir.path}\\rec_file.json';
      final backupPath = '$targetPath.bak';

      // Pre-crea backup valido e target corrotto
      await File(backupPath).writeAsString('{"valid": true}');
      await File(targetPath).writeAsString('');

      // Riscrittura con preserveExistingBackup: true (utilizzato nel recovery)
      await fileSystem.writeStringRecoverably(
        targetPath,
        '{"valid": true}',
        preserveExistingBackup: true,
      );

      // Il backup deve essere rimasto inalterato
      expect(
          await fileSystem.readAsString(backupPath), equals('{"valid": true}'));
    });

    test('deleteFile deleteFileBestEffort e restoreFromBackup', () async {
      final targetPath = '${tempDir.path}\\del_file.txt';
      final backupPath = '$targetPath.bak';

      await File(backupPath).writeAsString('backup_content');

      await fileSystem.restoreFromBackup(targetPath, backupPath);
      expect(
          await fileSystem.readAsString(targetPath), equals('backup_content'));

      // deleteFileBestEffort
      final res = await fileSystem.deleteFileBestEffort(targetPath);
      expect(res, isTrue);
      expect(await fileSystem.fileExists(targetPath), isFalse);
    });
  });
}
