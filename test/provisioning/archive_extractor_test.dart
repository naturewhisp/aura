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
      final sep = Platform.pathSeparator;
      final zipFile = File('${tempDir.path}${sep}valid.zip');
      final targetDir = '${tempDir.path}${sep}extracted';

      final archive = Archive()
        ..addFile(ArchiveFile('file1.txt', 12, 'hello file 1'.codeUnits))
        ..addFile(ArchiveFile('sub/file2.txt', 12, 'hello file 2'.codeUnits));

      final zipData = ZipEncoder().encode(archive)!;
      await zipFile.writeAsBytes(zipData);

      final bytesExtracted = await extractor.extractZipArchive(
        archiveFilePath: zipFile.path,
        targetDirectoryPath: targetDir,
        maxExpectedBytes: 100,
      );

      expect(bytesExtracted, equals(24));
      expect(await File('$targetDir${sep}file1.txt').readAsString(),
          equals('hello file 1'));
      expect(await File('$targetDir${sep}sub${sep}file2.txt').readAsString(),
          equals('hello file 2'));
    });

    test('Rileva e blocca attacchi Zip Slip (Path Traversal "..")', () async {
      final sep = Platform.pathSeparator;
      final zipFile = File('${tempDir.path}${sep}malicious_slip.zip');
      final targetDir = '${tempDir.path}${sep}extracted';

      final archive = Archive()
        ..addFile(ArchiveFile('../../../evil.exe', 10, 'malicious!'.codeUnits));

      final zipData = ZipEncoder().encode(archive)!;
      await zipFile.writeAsBytes(zipData);

      expect(
        () => extractor.extractZipArchive(
          archiveFilePath: zipFile.path,
          targetDirectoryPath: targetDir,
          maxExpectedBytes: 100,
        ),
        throwsA(isA<ProvisioningException>().having(
          (e) => e.reason,
          'reason',
          equals(ProvisioningFailureReason.unsafeArchiveEntry),
        )),
      );
    });

    test('Rileva e blocca voci ZIP con percorsi assoluti', () async {
      final sep = Platform.pathSeparator;
      final zipFile = File('${tempDir.path}${sep}malicious_abs.zip');
      final targetDir = '${tempDir.path}${sep}extracted';

      final archive = Archive()
        ..addFile(ArchiveFile(
            'C:\\Windows\\System32\\evil.dll', 10, 'malicious!'.codeUnits));

      final zipData = ZipEncoder().encode(archive)!;
      await zipFile.writeAsBytes(zipData);

      expect(
        () => extractor.extractZipArchive(
          archiveFilePath: zipFile.path,
          targetDirectoryPath: targetDir,
          maxExpectedBytes: 100,
        ),
        throwsA(isA<ProvisioningException>().having(
          (e) => e.reason,
          'reason',
          equals(ProvisioningFailureReason.unsafeArchiveEntry),
        )),
      );
    });

    test(
        'Rileva e blocca Zip Bomb (superamento dimensione estratta consentita)',
        () async {
      final sep = Platform.pathSeparator;
      final zipFile = File('${tempDir.path}${sep}zip_bomb.zip');
      final targetDir = '${tempDir.path}${sep}extracted';

      final hugeContent = List<int>.filled(2 * 1024 * 1024, 65); // 2 MB
      final archive = Archive()
        ..addFile(ArchiveFile('bomb.bin', hugeContent.length, hugeContent));

      final zipData = ZipEncoder().encode(archive)!;
      await zipFile.writeAsBytes(zipData);

      expect(
        () => extractor.extractZipArchive(
          archiveFilePath: zipFile.path,
          targetDirectoryPath: targetDir,
          maxExpectedBytes:
              100, // Limite max piccolo -> 500 MB max ma 2 MB supera il rapporto di compressione o limite custom
        ),
        throwsA(isA<ProvisioningException>().having(
          (e) => e.reason,
          'reason',
          equals(ProvisioningFailureReason.sizeLimitExceeded),
        )),
      );
    });
  });
}
