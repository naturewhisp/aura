import 'dart:convert';
import 'package:aura_core/aura_core.dart';
import 'package:test/test.dart';

/// Fake in-memory [ProvisioningFileSystem] per test deterministici.
final class MemoryProvisioningFileSystem implements ProvisioningFileSystem {
  final Map<String, String> files = {};
  final Set<String> directories = {};

  @override
  Future<bool> fileExists(String path) async => files.containsKey(path);

  @override
  Future<bool> directoryExists(String path) async => directories.contains(path);

  @override
  Future<String> readAsString(String path) async {
    if (!files.containsKey(path)) {
      throw const ProvisioningIoException(operation: 'readAsString');
    }
    return files[path]!;
  }

  @override
  Future<void> writeStringRecoverably(
    String path,
    String content, {
    bool preserveExistingBackup = false,
  }) async {
    if (files.containsKey(path)) {
      final oldContent = files[path]!;
      if (!preserveExistingBackup && oldContent.trim().isNotEmpty) {
        files['$path.bak'] = oldContent;
      }
    }
    files[path] = content;
  }

  @override
  Future<void> restoreFromBackup(String targetPath, String backupPath) async {
    if (!files.containsKey(backupPath)) {
      throw const ProvisioningIoException(operation: 'restoreFromBackup');
    }
    files[targetPath] = files[backupPath]!;
  }

  @override
  Future<void> deleteFile(String path) async {
    if (!files.containsKey(path)) {
      throw const ProvisioningIoException(operation: 'deleteFile');
    }
    files.remove(path);
  }

  @override
  Future<bool> deleteFileBestEffort(String path) async {
    if (files.containsKey(path)) {
      files.remove(path);
      return true;
    }
    return false;
  }

  @override
  Future<void> copyFile(String sourcePath, String targetPath) async {
    if (!files.containsKey(sourcePath)) {
      throw const ProvisioningIoException(operation: 'copyFile');
    }
    files[targetPath] = files[sourcePath]!;
  }

  @override
  Future<void> createDirectory(String path) async {
    directories.add(path);
  }
}

void main() {
  group('InstallationRecordRepository Tests -', () {
    late ProvisioningPathResolver pathResolver;
    late MemoryProvisioningFileSystem fileSystem;
    late TestProvisioningClock clock;
    late JsonInstallationRecordRepository repo;

    setUp(() {
      pathResolver = ProvisioningPathResolver(
        appManagedRoot: r'C:\AppManaged\Aura',
        bundledRoot: r'C:\Program Files\Aura',
      );
      fileSystem = MemoryProvisioningFileSystem();
      clock = TestProvisioningClock(DateTime.utc(2026, 7, 21, 21, 0, 0));
      repo = JsonInstallationRecordRepository(
        pathResolver: pathResolver,
        fileSystem: fileSystem,
        clock: clock,
      );
    });

    test('Restituisce record vuoto se il file non esiste', () async {
      final record = await repo.readRecord();
      expect(record.schemaVersion, equals('1.0'));
      expect(record.updatedAt, equals('2026-07-21T21:00:00.000Z'));
      expect(record.installedArtifacts, isEmpty);
    });

    test(
        'Scrive atomicamente e rilegge il record con installationId ed enum tipizzati',
        () async {
      final descriptor = InstalledArtifactDescriptor(
        installationId: 'inst-llama-b3500-1',
        artifactId: 'llama-b3500',
        artifactType: CatalogArtifactType.runtime,
        displayName: 'llama-server b3500',
        version: 'b3500',
        buildId: 'b3500',
        platform: 'windows',
        architecture: 'x64',
        relativeInstallPath: 'runtimes/llama-b3500/b3500',
        installedAt: '2026-07-21T21:00:00Z',
        sizeBytes: 10485760,
        sha256: 'a' * 64,
        sourceKind: CatalogArtifactSourceKind.remoteHttps,
        status: InstallationStatus.installed,
        ownership: ArtifactOwnership.appManaged,
        retained: true,
      );

      final record = InstallationRecord(
        updatedAt: '2026-07-21T21:00:00Z',
        installedArtifacts: [descriptor],
      );

      await repo.writeRecord(record);

      final loaded = await repo.readRecord();
      expect(loaded.installedArtifacts.length, equals(1));

      final readItem = loaded.installedArtifacts[0];
      expect(readItem.installationId, equals('inst-llama-b3500-1'));
      expect(readItem.status, equals(InstallationStatus.installed));
      expect(readItem.ownership, equals(ArtifactOwnership.appManaged));
      expect(readItem.retained, isTrue);
    });

    test('updateRecord serializza le modifiche prevenendo lost update',
        () async {
      await repo.updateRecord((current) {
        return current.copyWith(
          installedArtifacts: [
            InstalledArtifactDescriptor(
              installationId: 'inst-1',
              artifactId: 'art-1',
              artifactType: CatalogArtifactType.runtime,
              displayName: 'Art 1',
              version: '1.0',
              buildId: 'b1',
              platform: 'windows',
              architecture: 'x64',
              relativeInstallPath: 'runtimes/art-1/b1',
              installedAt: '2026-07-21T21:00:00Z',
              sizeBytes: 100,
              sha256: 'a' * 64,
              sourceKind: CatalogArtifactSourceKind.bundled,
            ),
          ],
        );
      });

      final updated = await repo.readRecord();
      expect(updated.installedArtifacts.length, equals(1));
      expect(updated.installedArtifacts[0].installationId, equals('inst-1'));
    });

    test(
        'Tenta il recovery dal backup .bak preservando il file di backup valido senza sovrascriverlo col primary corrotto',
        () async {
      final recordPath = pathResolver.installationRecordPath;
      final backupPath = '$recordPath.bak';

      final validRecord = InstallationRecord(
        updatedAt: '2026-07-21T20:00:00Z',
        installedArtifacts: [
          InstalledArtifactDescriptor(
            installationId: 'inst-recovered-1',
            artifactId: 'rt-1',
            artifactType: CatalogArtifactType.runtime,
            displayName: 'RT 1',
            version: '1.0',
            buildId: 'b1',
            platform: 'windows',
            architecture: 'x64',
            relativeInstallPath: 'runtimes/rt-1/b1',
            installedAt: '2026-07-21T20:00:00Z',
            sizeBytes: 500,
            sha256: 'b' * 64,
            sourceKind: CatalogArtifactSourceKind.bundled,
          ),
        ],
      );

      fileSystem.files[backupPath] = jsonEncode(validRecord.toJson());
      fileSystem.files[recordPath] = ''; // file vuoto corrotto

      final recovered = await repo.readRecord();
      expect(recovered.installedArtifacts.length, equals(1));
      expect(recovered.installedArtifacts[0].installationId,
          equals('inst-recovered-1'));
      // Il backup .bak deve essere rimasto inalterato con i dati validi originari
      expect(fileSystem.files[backupPath], contains('inst-recovered-1'));
    });

    test(
        'Rilancia direttamente unsupportedSchemaVersion senza fare recovery improprio',
        () async {
      final recordPath = pathResolver.installationRecordPath;
      fileSystem.files[recordPath] = jsonEncode({
        'schemaVersion': '99.0',
        'updatedAt': '2026-07-21T20:00:00Z',
        'installedArtifacts': [],
      });

      expect(
        () => repo.readRecord(),
        throwsA(isA<ProvisioningException>().having(
          (e) => e.reason,
          'reason',
          equals(ProvisioningFailureReason.unsupportedSchemaVersion),
        )),
      );
    });
  });
}
