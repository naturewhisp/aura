import 'dart:convert';
import 'package:aura_core/aura_offline.dart';
import 'package:test/test.dart';

void main() {
  group('Catalog Validation Service & Immutable Revision Policy Tests', () {
    late CatalogValidationService validator;
    late DateTime nowUtc;

    setUp(() {
      validator = const CatalogValidationService();
      nowUtc = DateTime.parse('2026-07-22T21:30:00Z').toUtc();
    });

    test(
        'ImmutableRepositoryRevisionPolicy rejects floating branch keywords and accepts 40-hex commit SHA',
        () {
      expect(
        () => ImmutableRepositoryRevisionPolicy.validateRevision(
            revision: 'main'),
        throwsA(isA<InvalidCatalogRevisionException>()),
      );
      expect(
        () => ImmutableRepositoryRevisionPolicy.validateRevision(
            revision: 'master'),
        throwsA(isA<InvalidCatalogRevisionException>()),
      );
      expect(
        () => ImmutableRepositoryRevisionPolicy.validateRevision(
            revision: 'HEAD'),
        throwsA(isA<InvalidCatalogRevisionException>()),
      );
      expect(
        () => ImmutableRepositoryRevisionPolicy.validateRevision(
            revision: 'refs/heads/feature'),
        throwsA(isA<InvalidCatalogRevisionException>()),
      );

      // Valid 40-character hexadecimal git commit SHA
      final validCommitSha = '72ca550021d6aceda98eb999f35b3407bce75383';
      expect(
        () => ImmutableRepositoryRevisionPolicy.validateRevision(
            revision: validCommitSha),
        returnsNormally,
      );
    });

    test('CatalogValidationService accepts valid catalog envelope', () {
      final payload = CatalogSignedPayload(
        schemaVersion: '1.0',
        signatureAlgorithm: 'ed25519-v1',
        keyId: 'aura-release-key-2026-01',
        catalogId: 'aura-official-catalog',
        catalogVersion: '1.0.0',
        catalogRevision: 1,
        issuedAt: '2026-07-22T20:00:00Z',
        expiresAt: '2026-08-22T20:00:00Z',
        manifest: CatalogManifest.initialDefault(),
      );
      final envelope = CatalogEnvelope(
        signedPayload: payload,
        signature: base64.encode(List.filled(64, 1)),
      );

      final result = validator.validate(envelope, nowUtc: nowUtc);
      expect(result.isValid, isTrue);
    });

    test(
        'CatalogValidationService rejects expired catalog considering clock skew',
        () {
      final payload = CatalogSignedPayload(
        schemaVersion: '1.0',
        signatureAlgorithm: 'ed25519-v1',
        keyId: 'aura-release-key-2026-01',
        catalogId: 'aura-official-catalog',
        catalogVersion: '1.0.0',
        catalogRevision: 1,
        issuedAt: '2026-06-01T00:00:00Z',
        expiresAt:
            '2026-07-22T20:00:00Z', // Expired compared to nowUtc (21:30:00Z)
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
          equals(CatalogAcquisitionFailureReason.catalogExpired));
    });

    test('CatalogValidationService rejects expiresAt <= issuedAt', () {
      final payload = CatalogSignedPayload(
        schemaVersion: '1.0',
        signatureAlgorithm: 'ed25519-v1',
        keyId: 'aura-release-key-2026-01',
        catalogId: 'aura-official-catalog',
        catalogVersion: '1.0.0',
        catalogRevision: 1,
        issuedAt: '2026-08-22T20:00:00Z',
        expiresAt: '2026-07-22T20:00:00Z',
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
  });
}
