import 'package:aura_core/aura_core.dart';
import 'package:test/test.dart';

void main() {
  group('Catalog Acquisition Domain & Identity Models', () {
    test(
        'ContentIdentity validates sizeBytes > 0 and 64-hex SHA-256 (normalizing to lowercase)',
        () {
      final content = ContentIdentity(
        sizeBytes: 1024,
        sha256: 'A' * 64,
      );

      expect(content.sizeBytes, equals(1024));
      expect(content.sha256, equals('a' * 64));

      expect(() => ContentIdentity(sizeBytes: 0, sha256: 'a' * 64),
          throwsArgumentError);
      expect(() => ContentIdentity(sizeBytes: -5, sha256: 'a' * 64),
          throwsArgumentError);
      expect(() => ContentIdentity(sizeBytes: 100, sha256: 'invalid-sha'),
          throwsArgumentError);
    });

    test(
        'ArtifactIdentity combines artifactId, version, buildId, and ContentIdentity',
        () {
      final content = ContentIdentity(sizeBytes: 2048, sha256: 'b' * 64);
      final artifact = ArtifactIdentity(
        artifactId: 'gemma-4-12b-it-qat-q4_0',
        version: '1.0.0',
        buildId: 'b1042',
        contentIdentity: content,
      );

      expect(artifact.artifactId, equals('gemma-4-12b-it-qat-q4_0'));
      expect(artifact.version, equals('1.0.0'));
      expect(artifact.buildId, equals('b1042'));
      expect(artifact.contentIdentity, equals(content));

      expect(
          () => ArtifactIdentity(
              artifactId: '',
              version: '1.0',
              buildId: 'b1',
              contentIdentity: content),
          throwsArgumentError);
    });

    test(
        'CatalogDeclarationIdentity combines catalogId, catalogRevision, and ArtifactIdentity',
        () {
      final content = ContentIdentity(sizeBytes: 2048, sha256: 'b' * 64);
      final artifact = ArtifactIdentity(
        artifactId: 'gemma-4-12b-it-qat-q4_0',
        version: '1.0.0',
        buildId: 'b1042',
        contentIdentity: content,
      );
      final declaration = CatalogDeclarationIdentity(
        catalogId: 'aura-official-catalog',
        catalogRevision: 42,
        artifactIdentity: artifact,
      );

      expect(declaration.catalogId, equals('aura-official-catalog'));
      expect(declaration.catalogRevision, equals(42));
      expect(declaration.artifactIdentity, equals(artifact));
    });

    test(
        'Differentiates same binary blob under different artifact identity (version/buildId)',
        () {
      final content = ContentIdentity(sizeBytes: 2048, sha256: 'b' * 64);
      final v1 = ArtifactIdentity(
        artifactId: 'gemma-4-12b-it-qat-q4_0',
        version: '1.0.0',
        buildId: 'b1042',
        contentIdentity: content,
      );
      final v2 = ArtifactIdentity(
        artifactId: 'gemma-4-12b-it-qat-q4_0',
        version: '1.1.0',
        buildId: 'b1043',
        contentIdentity: content,
      );

      expect(v1, isNot(equals(v2)));
      expect(v1.hashCode, isNot(equals(v2.hashCode)));
    });

    test('CatalogSignedPayload & CatalogEnvelope round-trip JSON serialization',
        () {
      final manifest = CatalogManifest.initialDefault();
      final payload = CatalogSignedPayload(
        schemaVersion: '1.0',
        signatureAlgorithm: 'ed25519-v1',
        keyId: 'aura-release-key-2026-01',
        catalogId: 'aura-official-catalog',
        catalogVersion: '1.2.0',
        catalogRevision: 42,
        issuedAt: '2026-07-22T21:30:00Z',
        expiresAt: '2026-08-22T21:30:00Z',
        manifest: manifest,
      );

      final envelope = CatalogEnvelope(
        signedPayload: payload,
        signature: 'c2lnbmF0dXJlLWJhc2U2NA==',
      );

      final jsonMap = envelope.toJson();
      final restored = CatalogEnvelope.fromJson(jsonMap);

      expect(restored.signedPayload.catalogId, equals(payload.catalogId));
      expect(restored.signedPayload.catalogRevision,
          equals(payload.catalogRevision));
      expect(restored.signedPayload.signatureAlgorithm, equals('ed25519-v1'));
      expect(restored.signedPayload.keyId, equals('aura-release-key-2026-01'));
      expect(restored.signature, equals(envelope.signature));
    });
  });
}
