import 'package:test/test.dart';
import 'package:aura_core/aura_offline.dart';

void main() {
  group('ReleaseVersionComparer Unit Tests', () {
    test('Confronto SemVer classico: versione maggiore vince', () {
      final snap1 = CatalogArtifactSnapshot(
        catalogId: 'cat_1',
        catalogRevision: 1,
        catalogSchemaVersion: '1.0',
        signingKeyId: 'key1',
        trustLevel: CatalogTrustLevel.signatureVerified,
        artifactId: 'actor-mod',
        artifactVersion: '2.0.0',
        buildId: 'b1',
        fileName: 'model.gguf',
        sizeBytes: 1000,
        sha256: 'abc',
        acquiredAtUtc: DateTime.now().toUtc(),
      );

      final snap2 = CatalogArtifactSnapshot(
        catalogId: 'cat_1',
        catalogRevision: 10,
        catalogSchemaVersion: '1.0',
        signingKeyId: 'key1',
        trustLevel: CatalogTrustLevel.signatureVerified,
        artifactId: 'actor-mod',
        artifactVersion: '1.9.0',
        buildId: 'b2',
        fileName: 'model.gguf',
        sizeBytes: 1000,
        sha256: 'def',
        acquiredAtUtc: DateTime.now().toUtc(),
      );

      // snap1 (2.0.0) > snap2 (1.9.0), anche se snap2 ha catalogRevision più alta (10 vs 1)
      expect(
        ReleaseVersionComparer.compareSnapshots(
          current: snap2,
          candidate: snap1,
        ),
        greaterThan(0),
      );
      expect(
        ReleaseVersionComparer.compareSnapshots(
          current: snap1,
          candidate: snap2,
        ),
        lessThan(0),
      );
    });

    test('Tie-breaker catalogRevision a parità di SemVer', () {
      final snapOldRev = CatalogArtifactSnapshot(
        catalogId: 'cat_1',
        catalogRevision: 5,
        catalogSchemaVersion: '1.0',
        signingKeyId: 'key1',
        trustLevel: CatalogTrustLevel.signatureVerified,
        artifactId: 'actor-mod',
        artifactVersion: '1.0.0',
        buildId: 'b1',
        fileName: 'model.gguf',
        sizeBytes: 1000,
        sha256: 'abc',
        acquiredAtUtc: DateTime.now().toUtc(),
      );

      final snapNewRev = CatalogArtifactSnapshot(
        catalogId: 'cat_1',
        catalogRevision: 8,
        catalogSchemaVersion: '1.0',
        signingKeyId: 'key1',
        trustLevel: CatalogTrustLevel.signatureVerified,
        artifactId: 'actor-mod',
        artifactVersion: '1.0.0',
        buildId: 'b2',
        fileName: 'model.gguf',
        sizeBytes: 1000,
        sha256: 'def',
        acquiredAtUtc: DateTime.now().toUtc(),
      );

      expect(
        ReleaseVersionComparer.compareSnapshots(
          current: snapOldRev,
          candidate: snapNewRev,
        ),
        greaterThan(0),
      );
    });

    test('Snapshot identici restituiscono 0', () {
      final snap = CatalogArtifactSnapshot(
        catalogId: 'cat_1',
        catalogRevision: 5,
        catalogSchemaVersion: '1.0',
        signingKeyId: 'key1',
        trustLevel: CatalogTrustLevel.signatureVerified,
        artifactId: 'actor-mod',
        artifactVersion: '1.0.0',
        buildId: 'b1',
        fileName: 'model.gguf',
        sizeBytes: 1000,
        sha256: 'abc',
        acquiredAtUtc: DateTime.now().toUtc(),
      );

      expect(
        ReleaseVersionComparer.compareSnapshots(
          current: snap,
          candidate: snap,
        ),
        equals(0),
      );
    });

    test('compareSnapshotWithArtifact con candidato di catalogo', () {
      final snapCurrent = CatalogArtifactSnapshot(
        catalogId: 'cat_1',
        catalogRevision: 2,
        catalogSchemaVersion: '1.0',
        signingKeyId: 'key1',
        trustLevel: CatalogTrustLevel.signatureVerified,
        artifactId: 'actor-mod',
        artifactVersion: '1.0.0',
        buildId: 'b1',
        fileName: 'model.gguf',
        sizeBytes: 1000,
        sha256: 'abc',
        acquiredAtUtc: DateTime.now().toUtc(),
      );

      final candidateArtifact = CatalogArtifact(
        artifactId: 'actor-mod',
        artifactType: CatalogArtifactType.model,
        displayName: 'Actor Model',
        version: '1.1.0',
        buildId: 'b2',
        platform: 'any',
        architecture: 'any',
        fileName: 'model.gguf',
        sourceKind: CatalogArtifactSourceKind.remoteHttps,
        downloadUri: 'https://example.com/model.gguf',
        sizeBytes: 1000,
        sha256: 'xyz',
        license: 'MIT',
      );

      expect(
        ReleaseVersionComparer.compareSnapshotWithArtifact(
          current: snapCurrent,
          candidateArtifact: candidateArtifact,
          candidateCatalogRevision: 3,
        ),
        greaterThan(0),
      );
    });
  });
}
