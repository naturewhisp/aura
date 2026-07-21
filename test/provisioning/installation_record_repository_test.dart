import 'dart:io';
import 'package:aura_core/aura_core.dart';
import 'package:test/test.dart';

void main() {
  group('InstallationRecordRepository Tests -', () {
    late Directory tempAppRoot;
    late Directory tempBundledRoot;
    late ProvisioningPathResolver pathResolver;
    late JsonInstallationRecordRepository repo;

    setUp(() async {
      tempAppRoot =
          await Directory.systemTemp.createTemp('aura_inst_rec_test_app_');
      tempBundledRoot =
          await Directory.systemTemp.createTemp('aura_inst_rec_test_bundled_');
      pathResolver = ProvisioningPathResolver(
        appManagedRoot: tempAppRoot.path,
        bundledRoot: tempBundledRoot.path,
      );
      repo = JsonInstallationRecordRepository(pathResolver: pathResolver);
    });

    tearDown(() async {
      if (await tempAppRoot.exists()) {
        await tempAppRoot.delete(recursive: true);
      }
      if (await tempBundledRoot.exists()) {
        await tempBundledRoot.delete(recursive: true);
      }
    });

    test('Restituisce record vuoto se il file non esiste', () async {
      final record = await repo.readRecord();
      expect(record.schemaVersion, equals('1.0'));
      expect(record.installedArtifacts, isEmpty);
    });

    test('Scrive atomicamente e rilegge correttamente l InstallationRecord',
        () async {
      final item = InstalledArtifactDescriptor(
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
      );

      final recordToSave = InstallationRecord(
        schemaVersion: '1.0',
        updatedAt: '2026-07-21T21:00:00Z',
        installedArtifacts: [item],
      );

      await repo.writeRecord(recordToSave);

      final loaded = await repo.readRecord();
      expect(loaded.schemaVersion, equals('1.0'));
      expect(loaded.installedArtifacts.length, equals(1));

      final readItem = loaded.installedArtifacts[0];
      expect(readItem.artifactId, equals('llama-b3500'));
      expect(
          readItem.relativeInstallPath, equals('runtimes/llama-b3500/b3500'));
      expect(readItem.sizeBytes, equals(10485760));
    });

    test('Lancia ProvisioningException se il file contiene JSON malformato',
        () async {
      final file = File(pathResolver.installationRecordPath);
      await file.parent.create(recursive: true);
      await file.writeAsString('{ bad json content }');

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
