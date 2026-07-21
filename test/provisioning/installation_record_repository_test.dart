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
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.installationRecordReadFailed,
        message: 'File non trovato.',
      );
    }
    return files[path]!;
  }

  @override
  Future<void> writeStringAtomic(String path, String content) async {
    if (files.containsKey(path)) {
      final oldContent = files[path]!;
      if (oldContent.trim().isNotEmpty) {
        files['$path.bak'] = oldContent;
      }
    }
    files[path] = content;
  }

  @override
  Future<void> deleteFile(String path) async {
    files.remove(path);
  }

  @override
  Future<void> copyFile(String sourcePath, String targetPath) async {
    if (!files.containsKey(sourcePath)) {
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.atomicMoveFailed,
        message: 'Sorgente non trovata per copia.',
      );
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

    test('Scrive atomicamente e rilegge il record con installationId',
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
        status: 'installed',
        ownership: 'appManaged',
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
      expect(readItem.status, equals('installed'));
      expect(readItem.retained, isTrue);
    });

    test(
        'Tenta il recovery automatico dal backup .bak se il file primario è vuoto o corrotto',
        () async {
      final recordPath = pathResolver.installationRecordPath;
      final backupPath = '$recordPath.bak';

      // Popola il backup .bak valido
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
      // File primario corrotto/vuoto
      fileSystem.files[recordPath] = '';

      final recovered = await repo.readRecord();
      expect(recovered.installedArtifacts.length, equals(1));
      expect(recovered.installedArtifacts[0].installationId,
          equals('inst-recovered-1'));
      // Verifica che il file primario sia stato ripristinato
      expect(fileSystem.files[recordPath], isNotEmpty);
    });

    test(
        'Lancia ProvisioningException se sia il primario che il backup sono introvabili o corrotti',
        () async {
      final recordPath = pathResolver.installationRecordPath;
      fileSystem.files[recordPath] = '{ invalid json }';

      expect(
        () => repo.readRecord(),
        throwsA(isA<ProvisioningException>().having(
          (e) => e.reason,
          'reason',
          equals(ProvisioningFailureReason.installationRecordReadFailed),
        )),
      );
    });
  });
}
