import 'dart:convert';
import 'package:aura_core/aura_offline.dart';
import 'package:test/test.dart';

void main() {
  group('Catalog Selection Policy & Compatibility Tests', () {
    late ValidatedCatalogCandidate candidateRemote;
    late ValidatedCatalogCandidate candidateCached;
    late ValidatedCatalogCandidate candidateBundled;
    late ValidatedCatalogCandidate candidateDev;

    setUp(() {
      final manifest = CatalogManifest.initialDefault();
      final payloadV1 = CatalogSignedPayload(
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

      final envelopeV1 = CatalogEnvelope(
        signedPayload: payloadV1,
        signature: base64.encode(List.filled(64, 1)),
      );

      const comp = CatalogCompatibilityResult(
        status: CatalogCompatibilityStatus.compatible,
      );

      candidateRemote = ValidatedCatalogCandidate(
        envelope: envelopeV1,
        source: CatalogSource.remoteSigned,
        trustLevel: CatalogTrustLevel.signatureVerified,
        compatibility: comp,
        canonicalPayloadDigest: 'digest-sha256-v10',
      );

      candidateCached = ValidatedCatalogCandidate(
        envelope: envelopeV1,
        source: CatalogSource.cachedSigned,
        trustLevel: CatalogTrustLevel.signatureVerified,
        compatibility: comp,
        canonicalPayloadDigest: 'digest-sha256-v10',
      );

      candidateBundled = ValidatedCatalogCandidate(
        envelope: envelopeV1,
        source: CatalogSource.bundledBootstrap,
        trustLevel: CatalogTrustLevel.bootstrapDeclared,
        compatibility: comp,
        canonicalPayloadDigest: 'digest-sha256-v10',
      );

      candidateDev = ValidatedCatalogCandidate(
        envelope: envelopeV1,
        source: CatalogSource.localDevelopment,
        trustLevel: CatalogTrustLevel.developmentUnsigned,
        compatibility: comp,
        canonicalPayloadDigest: 'digest-sha256-v10',
      );
    });

    test(
        'DefaultCatalogCompatibilityEvaluator returns compatible status for schema 1.0',
        () {
      const evaluator = DefaultCatalogCompatibilityEvaluator();
      final payload = candidateRemote.envelope.signedPayload;
      final result = evaluator.evaluate(
        payload: payload,
        applicationVersion: '1.0.0',
      );

      expect(result.isCompatible, isTrue);
    });

    test(
        'CatalogSelectionPolicy ranks remoteSigned over cachedSigned over bundledBootstrap',
        () {
      final result = CatalogSelectionPolicy.selectCandidate(
        candidates: [candidateBundled, candidateCached, candidateRemote],
        isProduction: true,
      );

      expect(result.hasSelection, isTrue);
      expect(
          result.selectedCandidate!.source, equals(CatalogSource.remoteSigned));
    });

    test('CatalogSelectionPolicy excludes localDevelopment in production mode',
        () {
      final result = CatalogSelectionPolicy.selectCandidate(
        candidates: [candidateDev],
        isProduction: true,
      );

      expect(result.hasSelection, isFalse);
      expect(result.status, equals(CatalogSelectionStatus.allRejected));
    });

    test(
        'CatalogSelectionPolicy detects same revision payload digest mismatch and returns typed conflict',
        () {
      final payloadAlt = CatalogSignedPayload(
        schemaVersion: '1.0',
        signatureAlgorithm: 'ed25519-v1',
        keyId: 'aura-release-key-2026-01',
        catalogId: 'aura-official-catalog',
        catalogVersion: '1.0.0',
        catalogRevision: 10, // Same revision 10
        issuedAt: '2026-07-22T20:00:00Z',
        expiresAt: '2026-08-22T20:00:00Z',
        manifest: CatalogManifest.initialDefault(),
      );

      final envelopeAlt = CatalogEnvelope(
        signedPayload: payloadAlt,
        signature: base64.encode(List.filled(64, 2)),
      );

      final candidateMismatch = ValidatedCatalogCandidate(
        envelope: envelopeAlt,
        source: CatalogSource.remoteSigned,
        trustLevel: CatalogTrustLevel.signatureVerified,
        compatibility: const CatalogCompatibilityResult(
            status: CatalogCompatibilityStatus.compatible),
        canonicalPayloadDigest: 'DIFFERENT-digest-sha256-v10',
      );

      final result = CatalogSelectionPolicy.selectCandidate(
        candidates: [candidateRemote, candidateMismatch],
        isProduction: true,
      );

      expect(result.hasSelection, isFalse);
      expect(
          result.status, equals(CatalogSelectionStatus.sameRevisionMismatch));
      expect(result.conflictReason,
          equals(CatalogAcquisitionFailureReason.catalogIdentityMismatch));
    });
  });
}
