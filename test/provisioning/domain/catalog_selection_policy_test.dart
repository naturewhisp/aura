import 'dart:convert';
import 'package:aura_core/aura_offline.dart';
import 'package:test/test.dart';

void main() {
  group('Catalog Selection Policy Revision-First Tests (Finding 7)', () {
    test(
        'CatalogSelectionPolicy selects higher revision cachedSigned (rev 12) over lower revision remoteSigned (rev 10)',
        () {
      final manifest = CatalogManifest.initialDefault();

      final payloadRev10 = CatalogSignedPayload(
        schemaVersion: '1.0',
        signatureAlgorithm: 'ed25519-v1',
        keyId: 'aura-release-key-2026-01',
        catalogId: 'aura-official-catalog',
        catalogVersion: '1.0.0',
        catalogRevision: 10,
        issuedAt: '2026-07-22T20:00:00Z',
        expiresAt: '2026-08-22T20:00:00Z',
        manifest: manifest,
      );

      final payloadRev12 = CatalogSignedPayload(
        schemaVersion: '1.0',
        signatureAlgorithm: 'ed25519-v1',
        keyId: 'aura-release-key-2026-01',
        catalogId: 'aura-official-catalog',
        catalogVersion: '1.2.0',
        catalogRevision: 12,
        issuedAt: '2026-07-22T20:00:00Z',
        expiresAt: '2026-08-22T20:00:00Z',
        manifest: manifest,
      );

      final candidateRemoteRev10 = ValidatedCatalogCandidate(
        envelope: CatalogEnvelope(
            signedPayload: payloadRev10,
            signature: base64.encode(List.filled(64, 1))),
        source: CatalogSource.remoteSigned,
        trustLevel: CatalogTrustLevel.signatureVerified,
        compatibility: const CatalogCompatibilityResult(
            status: CatalogCompatibilityStatus.compatible),
        canonicalPayloadDigest: 'digest-sha256-rev10',
      );

      final candidateCachedRev12 = ValidatedCatalogCandidate(
        envelope: CatalogEnvelope(
            signedPayload: payloadRev12,
            signature: base64.encode(List.filled(64, 2))),
        source: CatalogSource.cachedSigned,
        trustLevel: CatalogTrustLevel.signatureVerified,
        compatibility: const CatalogCompatibilityResult(
            status: CatalogCompatibilityStatus.compatible),
        canonicalPayloadDigest: 'digest-sha256-rev12',
      );

      final result = CatalogSelectionPolicy.selectCandidate(
        candidates: [candidateRemoteRev10, candidateCachedRev12],
        isProduction: true,
      );

      expect(result.hasSelection, isTrue);
      expect(result.selectedCandidate!.envelope.signedPayload.catalogRevision,
          equals(12));
      expect(
          result.selectedCandidate!.source, equals(CatalogSource.cachedSigned));
    });
  });
}
