import 'dart:async';
import 'package:aura_core/aura_core.dart';
import 'package:test/test.dart';
import 'provisioning_test_helpers.dart';

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
