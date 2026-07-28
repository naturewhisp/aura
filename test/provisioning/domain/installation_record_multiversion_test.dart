import 'package:test/test.dart';
import 'package:aura_core/aura_offline.dart';

void main() {
  group('InstallationRecord Multi-Version Unit Tests', () {
    test('Coesistenza di più versioni dello stesso artifactId nel registro',
        () {
      var record = InstallationRecord.empty(updatedAt: '2026-07-28T10:00:00Z');

      final inst1 = InstalledArtifactDescriptor(
        installationId: 'inst_v1',
        artifactId: 'actor-mod',
        artifactType: CatalogArtifactType.model,
        displayName: 'Actor Model',
        platform: 'any',
        architecture: 'any',
        sourceKind: CatalogArtifactSourceKind.remoteHttps,
        version: '1.0.0',
        buildId: 'b1',
        sizeBytes: 1000,
        sha256: 'sha1',
        relativeInstallPath: 'actor-mod/1.0.0-b1',
        entryFileName: 'model.gguf',
        installedAt: '2026-07-28T10:00:00Z',
        status: InstallationStatus.verified,
        verifiedAt: '2026-07-28T10:00:00Z',
      );

      final inst2 = InstalledArtifactDescriptor(
        installationId: 'inst_v2',
        artifactId: 'actor-mod',
        artifactType: CatalogArtifactType.model,
        displayName: 'Actor Model',
        platform: 'any',
        architecture: 'any',
        sourceKind: CatalogArtifactSourceKind.remoteHttps,
        version: '2.0.0',
        buildId: 'b2',
        sizeBytes: 1200,
        sha256: 'sha2',
        relativeInstallPath: 'actor-mod/2.0.0-b2',
        entryFileName: 'model.gguf',
        installedAt: '2026-07-28T10:05:00Z',
        status: InstallationStatus.verified,
        verifiedAt: '2026-07-28T10:00:00Z',
      );

      record = record.upsertArtifact(inst1);
      record = record.upsertArtifact(inst2);

      expect(record.installedArtifacts.length, equals(2));
      expect(record.findInstallation('inst_v1'), equals(inst1));
      expect(record.findInstallation('inst_v2'), equals(inst2));

      final allVersions = record.findInstallationsForArtifact('actor-mod');
      expect(allVersions.length, equals(2));
    });

    test(
        'upsertArtifact aggiorna solo l\'installazione con lo stesso installationId',
        () {
      var record = InstallationRecord.empty(updatedAt: '2026-07-28T10:00:00Z');

      final inst1 = InstalledArtifactDescriptor(
        installationId: 'inst_v1',
        artifactId: 'actor-mod',
        artifactType: CatalogArtifactType.model,
        displayName: 'Actor Model',
        platform: 'any',
        architecture: 'any',
        sourceKind: CatalogArtifactSourceKind.remoteHttps,
        version: '1.0.0',
        buildId: 'b1',
        sizeBytes: 1000,
        sha256: 'sha1',
        relativeInstallPath: 'actor-mod/1.0.0-b1',
        entryFileName: 'model.gguf',
        installedAt: '2026-07-28T10:00:00Z',
        status: InstallationStatus.verified,
        verifiedAt: '2026-07-28T10:00:00Z',
      );

      record = record.upsertArtifact(inst1);

      final inst1Repaired = inst1.copyWith(
        repairCount: 1,
        lastRepairedAt: '2026-07-28T10:10:00Z',
      );

      record = record.upsertArtifact(inst1Repaired);

      expect(record.installedArtifacts.length, equals(1));
      expect(record.findInstallation('inst_v1')?.repairCount, equals(1));
      expect(record.findInstallation('inst_v1')?.lastRepairedAt,
          equals('2026-07-28T10:10:00Z'));
    });

    test(
        'findLatestVerifiedInstallation restituisce l\'installazione verified con versione maggiore',
        () {
      var record = InstallationRecord.empty(updatedAt: '2026-07-28T10:00:00Z');

      final inst1 = InstalledArtifactDescriptor(
        installationId: 'inst_v1',
        artifactId: 'actor-mod',
        artifactType: CatalogArtifactType.model,
        displayName: 'Actor Model',
        platform: 'any',
        architecture: 'any',
        sourceKind: CatalogArtifactSourceKind.remoteHttps,
        version: '1.0.0',
        buildId: 'b1',
        sizeBytes: 1000,
        sha256: 'sha1',
        relativeInstallPath: 'actor-mod/1.0.0-b1',
        installedAt: '2026-07-28T10:00:00Z',
        status: InstallationStatus.verified,
        verifiedAt: '2026-07-28T10:00:00Z',
      );

      final inst2 = InstalledArtifactDescriptor(
        installationId: 'inst_v2',
        artifactId: 'actor-mod',
        artifactType: CatalogArtifactType.model,
        displayName: 'Actor Model',
        platform: 'any',
        architecture: 'any',
        sourceKind: CatalogArtifactSourceKind.remoteHttps,
        version: '2.1.0',
        buildId: 'b2',
        sizeBytes: 1200,
        sha256: 'sha2',
        relativeInstallPath: 'actor-mod/2.1.0-b2',
        installedAt: '2026-07-28T10:05:00Z',
        status: InstallationStatus.verified,
        verifiedAt: '2026-07-28T10:00:00Z',
      );

      record = record.upsertArtifact(inst1).upsertArtifact(inst2);

      final latest = record.findLatestVerifiedInstallation('actor-mod');
      expect(latest?.installationId, equals('inst_v2'));
      expect(latest?.version, equals('2.1.0'));
    });
  });
}
