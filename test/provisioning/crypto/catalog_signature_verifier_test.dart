import 'dart:convert';
import 'dart:typed_data';
import 'package:aura_core/aura_offline.dart';
import 'package:test/test.dart';

void main() {
  group('Catalog Signature Verifier & Trust Store Tests', () {
    late InMemoryCatalogTrustStore trustStore;
    late CatalogPublicKey validPublicKey;

    setUp(() {
      validPublicKey = CatalogPublicKey(
        keyId: 'aura-release-key-2026-01',
        algorithm: 'ed25519-v1',
        rawKeyBytes: Uint8List(32), // 32 byte valid key length
      );
      trustStore = InMemoryCatalogTrustStore.fromKeys([validPublicKey]);
    });

    test('InMemoryCatalogTrustStore finds key by keyId', () async {
      final key = await trustStore.findTrustedKey('aura-release-key-2026-01');
      expect(key, equals(validPublicKey));

      final unknown = await trustStore.findTrustedKey('unknown-key-id');
      expect(unknown, isNull);
    });

    test('Ed25519CatalogSignatureVerifier rejects unsupported algorithm',
        () async {
      final payload = CatalogSignedPayload(
        schemaVersion: '1.0',
        signatureAlgorithm: 'rsa-sha256',
        keyId: 'aura-release-key-2026-01',
        catalogId: 'aura-official-catalog',
        catalogVersion: '1.0.0',
        catalogRevision: 1,
        issuedAt: '2026-07-22T21:30:00Z',
        expiresAt: '2026-08-22T21:30:00Z',
        manifest: CatalogManifest.initialDefault(),
      );
      final envelope = CatalogEnvelope(
        signedPayload: payload,
        signature: base64.encode(Uint8List(64)),
      );

      final verifier = const Ed25519CatalogSignatureVerifier();
      final result = await verifier.verify(
        envelope: envelope,
        canonicalSignedPayload: Uint8List.fromList([1, 2, 3]),
        trustStore: trustStore,
      );

      expect(result.isValid, isFalse);
      expect(
          result.failureReason,
          equals(
              CatalogAcquisitionFailureReason.unsupportedSignatureAlgorithm));
    });

    test('Ed25519CatalogSignatureVerifier rejects unknown keyId', () async {
      final payload = CatalogSignedPayload(
        schemaVersion: '1.0',
        signatureAlgorithm: 'ed25519-v1',
        keyId: 'untrusted-key-id',
        catalogId: 'aura-official-catalog',
        catalogVersion: '1.0.0',
        catalogRevision: 1,
        issuedAt: '2026-07-22T21:30:00Z',
        expiresAt: '2026-08-22T21:30:00Z',
        manifest: CatalogManifest.initialDefault(),
      );
      final envelope = CatalogEnvelope(
        signedPayload: payload,
        signature: base64.encode(Uint8List(64)),
      );

      final verifier = const Ed25519CatalogSignatureVerifier();
      final result = await verifier.verify(
        envelope: envelope,
        canonicalSignedPayload: Uint8List.fromList([1, 2, 3]),
        trustStore: trustStore,
      );

      expect(result.isValid, isFalse);
      expect(result.failureReason,
          equals(CatalogAcquisitionFailureReason.unknownKeyId));
    });

    test(
        'Ed25519CatalogSignatureVerifier rejects invalid Base64 signature encoding',
        () async {
      final payload = CatalogSignedPayload(
        schemaVersion: '1.0',
        signatureAlgorithm: 'ed25519-v1',
        keyId: 'aura-release-key-2026-01',
        catalogId: 'aura-official-catalog',
        catalogVersion: '1.0.0',
        catalogRevision: 1,
        issuedAt: '2026-07-22T21:30:00Z',
        expiresAt: '2026-08-22T21:30:00Z',
        manifest: CatalogManifest.initialDefault(),
      );
      final envelope = CatalogEnvelope(
        signedPayload: payload,
        signature: 'invalid-base64-!!!',
      );

      final verifier = const Ed25519CatalogSignatureVerifier();
      final result = await verifier.verify(
        envelope: envelope,
        canonicalSignedPayload: Uint8List.fromList([1, 2, 3]),
        trustStore: trustStore,
      );

      expect(result.isValid, isFalse);
      expect(result.failureReason,
          equals(CatalogAcquisitionFailureReason.invalidSignatureEncoding));
    });

    test(
        'Ed25519CatalogSignatureVerifier rejects decoded signature length != 64 bytes',
        () async {
      final payload = CatalogSignedPayload(
        schemaVersion: '1.0',
        signatureAlgorithm: 'ed25519-v1',
        keyId: 'aura-release-key-2026-01',
        catalogId: 'aura-official-catalog',
        catalogVersion: '1.0.0',
        catalogRevision: 1,
        issuedAt: '2026-07-22T21:30:00Z',
        expiresAt: '2026-08-22T21:30:00Z',
        manifest: CatalogManifest.initialDefault(),
      );
      // Signature length 32 instead of 64
      final envelope = CatalogEnvelope(
        signedPayload: payload,
        signature: base64.encode(Uint8List(32)),
      );

      final verifier = const Ed25519CatalogSignatureVerifier();
      final result = await verifier.verify(
        envelope: envelope,
        canonicalSignedPayload: Uint8List.fromList([1, 2, 3]),
        trustStore: trustStore,
      );

      expect(result.isValid, isFalse);
      expect(result.failureReason,
          equals(CatalogAcquisitionFailureReason.invalidSignatureLength));
    });
  });
}
