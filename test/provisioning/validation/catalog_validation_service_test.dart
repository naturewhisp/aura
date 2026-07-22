import 'dart:convert';
import 'package:aura_core/aura_offline.dart';
import 'package:test/test.dart';

void main() {
  group('Catalog Validation Service Tests (Finding 4, 5, 6 Corrections)', () {
    late CatalogValidationService validator;
    late DateTime nowUtc;

    setUp(() {
      validator = const CatalogValidationService();
      nowUtc = DateTime.parse('2026-07-22T21:30:00Z').toUtc();
    });

    test('Rejects catalog when expiresAt == issuedAt (Finding 4)', () {
      final payload = CatalogSignedPayload(
        schemaVersion: '1.0',
        signatureAlgorithm: 'ed25519-v1',
        keyId: 'aura-release-key-2026-01',
        catalogId: 'aura-official-catalog',
        catalogVersion: '1.0.0',
        catalogRevision: 1,
        issuedAt: '2026-07-22T20:00:00Z',
        expiresAt: '2026-07-22T20:00:00Z', // Equality is invalid per spec
        manifest: CatalogManifest.initialDefault(),
      );
      final envelope = CatalogEnvelope(
        signedPayload: payload,
        signature: base64.encode(List.filled(64, 1)),
      );

      final result = validator.validate(envelope, nowUtc: nowUtc);
      expect(result.isValid, isFalse);
      expect(result.failureReason,
          equals(CatalogAcquisitionFailureReason.invalidExpiresAt));
    });

    test(
        'Rejects catalog when issuedAt is too far in the future beyond clock skew (Finding 6)',
        () {
      final payload = CatalogSignedPayload(
        schemaVersion: '1.0',
        signatureAlgorithm: 'ed25519-v1',
        keyId: 'aura-release-key-2026-01',
        catalogId: 'aura-official-catalog',
        catalogVersion: '1.0.0',
        catalogRevision: 1,
        issuedAt:
            '2026-07-22T22:30:00Z', // 1 hour in the future relative to 21:30:00Z
        expiresAt: '2026-08-22T20:00:00Z',
        manifest: CatalogManifest.initialDefault(),
      );
      final envelope = CatalogEnvelope(
        signedPayload: payload,
        signature: base64.encode(List.filled(64, 1)),
      );

      final result = validator.validate(
        envelope,
        nowUtc: nowUtc,
        allowedClockSkew: const Duration(minutes: 5),
      );
      expect(result.isValid, isFalse);
      expect(result.failureReason,
          equals(CatalogAcquisitionFailureReason.invalidIssuedAt));
    });

    test(
        'Rejects remoteSigned catalog when artifact metadata lacks repositoryRevision (Finding 5)',
        () {
      final manifest = CatalogManifest(
        schemaVersion: '1.0',
        catalogId: 'aura-official-catalog',
        generatedAt: '2026-07-22T20:00:00Z',
        artifacts: [
          CatalogArtifact(
            artifactId: 'gemma-4-12b-it-qat-q4-0',
            artifactType: CatalogArtifactType.model,
            displayName: 'Gemma Model',
            version: '1.0.0',
            buildId: 'b1',
            platform: 'windows',
            architecture: 'x64',
            fileName: 'gemma.gguf',
            sourceKind: CatalogArtifactSourceKind.remoteHttps,
            sizeBytes: 1024,
            sha256: 'a' * 64,
            compression: CatalogCompressionFormat.none,
            license: 'MIT',
            releaseChannel: 'stable',
            metadata: {}, // Missing repositoryRevision metadata!
          ),
        ],
      );

      final payload = CatalogSignedPayload(
        schemaVersion: '1.0',
        signatureAlgorithm: 'ed25519-v1',
        keyId: 'aura-release-key-2026-01',
        catalogId: 'aura-official-catalog',
        catalogVersion: '1.0.0',
        catalogRevision: 1,
        issuedAt: '2026-07-22T20:00:00Z',
        expiresAt: '2026-08-22T20:00:00Z',
        manifest: manifest,
      );
      final envelope = CatalogEnvelope(
        signedPayload: payload,
        signature: base64.encode(List.filled(64, 1)),
      );

      final result = validator.validate(
        envelope,
        nowUtc: nowUtc,
        source: CatalogSource.remoteSigned,
      );
      expect(result.isValid, isFalse);
      expect(result.failureReason,
          equals(CatalogAcquisitionFailureReason.floatingRepositoryRevision));
    });
  });
}
