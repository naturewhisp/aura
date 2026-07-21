import 'dart:io';
import 'package:archive/archive.dart';
import 'package:aura_core/aura_core.dart';
import 'package:test/test.dart';

void main() {
  group('ZipArchiveExtractor Tests -', () {
    late Directory tempDir;
    late ZipArchiveExtractor extractor;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('aura_zip_test_');
      extractor = const ZipArchiveExtractor();
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('Estrae correttamente un archivio ZIP valido', () async {
      final zipFile = File('${tempDir.path}\\valid.zip');
      final targetDir = '${tempDir.path}\\extracted';

      final archive = Archive()
        ..addFile(ArchiveFile('file1.txt', 12, 'hello file 1'.codeUnits))
        ..addFile(ArchiveFile('sub/file2.txt', 12, 'hello file 2'.codeUnits));

      final zipData = ZipEncoder().encode(archive)!;
      await zipFile.writeAsBytes(zipData);

      final bytesExtracted = await extractor.extractZipArchive(
        archiveFilePath: zipFile.path,
        targetDirectoryPath: targetDir,
      );

      expect(bytesExtracted, equals(24));
      expect(await File('$targetDir\\file1.txt').readAsString(),
          equals('hello file 1'));
      expect(await File('$targetDir\\sub\\file2.txt').readAsString(),
          equals('hello file 2'));
    });

    test('Rileva e blocca attacchi Zip Slip (Path Traversal "..")', () async {
      final zipFile = File('${tempDir.path}\\malicious_slip.zip');
      final targetDir = '${tempDir.path}\\extracted';

      final archive = Archive()
        ..addFile(ArchiveFile('../../../evil.exe', 10, 'malicious!'.codeUnits));

      final zipData = ZipEncoder().encode(archive)!;
      await zipFile.writeAsBytes(zipData);

      expect(
        () => extractor.extractZipArchive(
          archiveFilePath: zipFile.path,
          targetDirectoryPath: targetDir,
        ),
        throwsA(isA<ProvisioningException>().having(
          (e) => e.reason,
          'reason',
          equals(ProvisioningFailureReason.unsafeArchiveEntry),
        )),
      );
    });

    test('Rileva e blocca voci ZIP con percorsi assoluti', () async {
      final zipFile = File('${tempDir.path}\\malicious_abs.zip');
      final targetDir = '${tempDir.path}\\extracted';

      final archive = Archive()
        ..addFile(ArchiveFile(
            'C:\\Windows\\System32\\evil.dll', 10, 'malicious!'.codeUnits));

      final zipData = ZipEncoder().encode(archive)!;
      await zipFile.writeAsBytes(zipData);

      expect(
        () => extractor.extractZipArchive(
          archiveFilePath: zipFile.path,
          targetDirectoryPath: targetDir,
        ),
        throwsA(isA<ProvisioningException>().having(
          (e) => e.reason,
          'reason',
          equals(ProvisioningFailureReason.unsafeArchiveEntry),
        )),
      );
    });
  });
}
