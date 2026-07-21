import 'dart:async';
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
  Future<List<int>> readAsBytes(String path) async {
    if (!files.containsKey(path)) {
      throw const ProvisioningIoException(operation: 'readAsBytes');
    }
    return utf8.encode(files[path]!);
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
  Stream<List<int>> openRead(String path) {
    if (!files.containsKey(path)) {
      throw const ProvisioningIoException(operation: 'openRead');
    }
    return Stream.value(utf8.encode(files[path]!));
  }

  @override
  Future<int> getFileSize(String path) async {
    if (!files.containsKey(path)) {
      throw const ProvisioningIoException(operation: 'getFileSize');
    }
    return utf8.encode(files[path]!).length;
  }

  @override
  Future<List<String>> listDirectory(String path) async {
    final prefix = path.endsWith(r'\') ? path : '$path\\';
    final result = <String>[];
    for (final key in files.keys) {
      if (key.startsWith(prefix)) {
        final sub = key.substring(prefix.length);
        final firstSeg = sub.split(r'\').first;
        if (!result.contains(firstSeg)) result.add(firstSeg);
      }
    }
    for (final dir in directories) {
      if (dir.startsWith(prefix)) {
        final sub = dir.substring(prefix.length);
        final firstSeg = sub.split(r'\').first;
        if (!result.contains(firstSeg)) result.add(firstSeg);
      }
    }
    return result;
  }

  @override
  Future<void> deleteDirectory(String path) async {
    directories.remove(path);
    final prefix = path.endsWith(r'\') ? path : '$path\\';
    files.removeWhere((k, v) => k.startsWith(prefix));
    directories.removeWhere((d) => d.startsWith(prefix));
  }

  @override
  Future<bool> deleteDirectoryBestEffort(String path) async {
    await deleteDirectory(path);
    return true;
  }

  @override
  Future<void> copyDirectory(String sourcePath, String targetPath) async {
    final prefix = sourcePath.endsWith(r'\') ? sourcePath : '$sourcePath\\';
    final targetPrefix =
        targetPath.endsWith(r'\') ? targetPath : '$targetPath\\';
    directories.add(targetPath);

    final toAddFiles = <String, String>{};
    files.forEach((k, v) {
      if (k.startsWith(prefix)) {
        final rel = k.substring(prefix.length);
        toAddFiles['$targetPrefix$rel'] = v;
      }
    });
    files.addAll(toAddFiles);
  }

  @override
  Future<void> moveDirectory(String sourcePath, String targetPath) async {
    await copyDirectory(sourcePath, targetPath);
    await deleteDirectoryBestEffort(sourcePath);
  }

  @override
  Future<void> renameDirectoryWithoutFallback(
      String sourcePath, String targetPath) async {
    await copyDirectory(sourcePath, targetPath);
    await deleteDirectoryBestEffort(sourcePath);
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
    late ProvisioningLock sharedLock;
    late JsonInstallationRecordRepository repo;

    setUp(() {
      pathResolver = ProvisioningPathResolver(
        appManagedRoot: r'C:\AppManaged\Aura',
        bundledRoot: r'C:\Program Files\Aura',
      );
      fileSystem = MemoryProvisioningFileSystem();
      clock = TestProvisioningClock(DateTime.utc(2026, 7, 21, 21, 0, 0));
      sharedLock = InMemoryProvisioningLock();
      repo = JsonInstallationRecordRepository(
        pathResolver: pathResolver,
        lock: sharedLock,
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

    test('Scrive e rilegge il record con installationId ed enum tipizzati',
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
        installedAt: '2026-07-21T21:00:00.000Z',
        sizeBytes: 10485760,
        sha256: 'a' * 64,
        sourceKind: CatalogArtifactSourceKind.remoteHttps,
        status: InstallationStatus.installed,
        ownership: ArtifactOwnership.appManaged,
        retained: true,
      );

      final record = InstallationRecord(
        updatedAt: '2026-07-21T21:00:00.000Z',
        installedArtifacts: [descriptor],
      );

      final saved = await repo.replaceRecord(record);
      expect(saved.updatedAt, equals('2026-07-21T21:00:00.000Z'));

      final loaded = await repo.readRecord();
      expect(loaded.installedArtifacts.length, equals(1));

      final readItem = loaded.installedArtifacts[0];
      expect(readItem.installationId, equals('inst-llama-b3500-1'));
      expect(readItem.status, equals(InstallationStatus.installed));
      expect(readItem.ownership, equals(ArtifactOwnership.appManaged));
      expect(readItem.retained, isTrue);
    });

    test('Impone le invarianti di stato tra status e verifiedAt', () {
      // verified richiede verifiedAt
      expect(
        () => InstalledArtifactDescriptor(
          installationId: 'inst-1',
          artifactId: 'art-1',
          artifactType: CatalogArtifactType.runtime,
          displayName: 'Art 1',
          version: '1.0',
          buildId: 'b1',
          platform: 'windows',
          architecture: 'x64',
          relativeInstallPath: 'runtimes/art-1/b1',
          installedAt: '2026-07-21T21:00:00.000Z',
          sizeBytes: 100,
          sha256: 'a' * 64,
          sourceKind: CatalogArtifactSourceKind.bundled,
          status: InstallationStatus.verified,
          verifiedAt: null,
        ),
        throwsA(isA<ProvisioningException>()),
      );

      // installed non accetta verifiedAt
      expect(
        () => InstalledArtifactDescriptor(
          installationId: 'inst-1',
          artifactId: 'art-1',
          artifactType: CatalogArtifactType.runtime,
          displayName: 'Art 1',
          version: '1.0',
          buildId: 'b1',
          platform: 'windows',
          architecture: 'x64',
          relativeInstallPath: 'runtimes/art-1/b1',
          installedAt: '2026-07-21T21:00:00.000Z',
          sizeBytes: 100,
          sha256: 'a' * 64,
          sourceKind: CatalogArtifactSourceKind.bundled,
          status: InstallationStatus.installed,
          verifiedAt: '2026-07-21T21:00:00.000Z',
        ),
        throwsA(isA<ProvisioningException>()),
      );
    });

    test('Rifiuta installationId duplicati nello stesso InstallationRecord',
        () {
      final d1 = InstalledArtifactDescriptor(
        installationId: 'inst-dup',
        artifactId: 'art-1',
        artifactType: CatalogArtifactType.runtime,
        displayName: 'Art 1',
        version: '1.0',
        buildId: 'b1',
        platform: 'windows',
        architecture: 'x64',
        relativeInstallPath: 'runtimes/art-1/b1',
        installedAt: '2026-07-21T21:00:00.000Z',
        sizeBytes: 100,
        sha256: 'a' * 64,
        sourceKind: CatalogArtifactSourceKind.bundled,
      );

      final jsonMap = {
        'schemaVersion': '1.0',
        'updatedAt': '2026-07-21T21:00:00.000Z',
        'installedArtifacts': [d1.toJson(), d1.toJson()],
      };

      expect(
        () => InstallationRecord.fromJson(jsonMap),
        throwsA(isA<ProvisioningException>().having(
          (e) => e.reason,
          'reason',
          equals(ProvisioningFailureReason.catalogMalformed),
        )),
      );
    });

    test(
        'Due istanze di repository condividono il lock ed evitano lost update concorrenti',
        () async {
      final repo2 = JsonInstallationRecordRepository(
        pathResolver: pathResolver,
        lock: sharedLock,
        fileSystem: fileSystem,
        clock: clock,
      );

      final d1 = InstalledArtifactDescriptor(
        installationId: 'inst-1',
        artifactId: 'art-1',
        artifactType: CatalogArtifactType.runtime,
        displayName: 'Art 1',
        version: '1.0',
        buildId: 'b1',
        platform: 'windows',
        architecture: 'x64',
        relativeInstallPath: 'runtimes/art-1/b1',
        installedAt: '2026-07-21T21:00:00.000Z',
        sizeBytes: 100,
        sha256: 'a' * 64,
        sourceKind: CatalogArtifactSourceKind.bundled,
      );

      final d2 = InstalledArtifactDescriptor(
        installationId: 'inst-2',
        artifactId: 'art-2',
        artifactType: CatalogArtifactType.model,
        displayName: 'Art 2',
        version: '1.0',
        buildId: 'b2',
        platform: 'windows',
        architecture: 'x64',
        relativeInstallPath: 'models/art-2/b2',
        installedAt: '2026-07-21T21:00:00.000Z',
        sizeBytes: 200,
        sha256: 'b' * 64,
        sourceKind: CatalogArtifactSourceKind.bundled,
      );

      final f1 = repo.updateRecord((current) async {
        await Future.delayed(const Duration(milliseconds: 10));
        return current.copyWith(
          installedArtifacts: [...current.installedArtifacts, d1],
        );
      });

      final f2 = repo2.updateRecord((current) async {
        return current.copyWith(
          installedArtifacts: [...current.installedArtifacts, d2],
        );
      });

      await Future.wait([f1, f2]);

      final finalRecord = await repo.readRecord();
      expect(finalRecord.installedArtifacts.length, equals(2));
      final ids =
          finalRecord.installedArtifacts.map((a) => a.installationId).toSet();
      expect(ids, containsAll(['inst-1', 'inst-2']));
    });
  });
}
