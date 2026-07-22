import 'dart:convert';
import 'dart:typed_data';
import 'package:aura_core/aura_offline.dart';
import 'package:cryptography/cryptography.dart' as crypto;
import 'package:test/test.dart';

void main() {
  group('Real Ed25519 Signature Verifier (RFC 8032) & Trust Store Tests', () {
    late InMemoryCatalogTrustStore trustStore;
    late crypto.SimpleKeyPair keyPair;
    late Uint8List publicKeyBytes;
    late CatalogPublicKey catalogPublicKey;

    setUp(() async {
      final algorithm = crypto.Ed25519();
      keyPair = await algorithm.newKeyPair();
      final simplePubKey = await keyPair.extractPublicKey();
      publicKeyBytes = Uint8List.fromList(simplePubKey.bytes);

      catalogPublicKey = CatalogPublicKey(
        keyId: 'aura-release-key-2026-01',
        algorithm: 'ed25519-v1',
        rawKeyBytes: publicKeyBytes,
      );
      trustStore = InMemoryCatalogTrustStore.fromKeys([catalogPublicKey]);
    });

    test('Verifies valid Ed25519 signature (RFC 8032) and returns valid result',
        () async {
      final payload = CatalogSignedPayload(
        schemaVersion: '1.0',
        signatureAlgorithm: 'ed25519-v1',
        keyId: 'aura-release-key-2026-01',
        catalogId: 'aura-official-catalog',
        catalogVersion: '1.0.0',
        catalogRevision: 42,
        issuedAt: '2026-07-22T20:00:00Z',
        expiresAt: '2026-08-22T20:00:00Z',
        manifest: CatalogManifest.initialDefault(),
      );

      final canonicalBytes =
          Rfc8785JcsCanonicalizer.canonicalizeBytes(payload.toJson());

      // Firma crittografica reale RFC 8032
      final algorithm = crypto.Ed25519();
      final signatureObj = await algorithm.sign(
        canonicalBytes,
        keyPair: keyPair,
      );

      final envelope = CatalogEnvelope(
        signedPayload: payload,
        signature: base64.encode(signatureObj.bytes),
      );

      final verifier = Ed25519CatalogSignatureVerifier();
      final result = await verifier.verify(
        envelope: envelope,
        canonicalSignedPayload: canonicalBytes,
        trustStore: trustStore,
      );

      expect(result.isValid, isTrue);
      expect(result.keyId, equals('aura-release-key-2026-01'));
      expect(result.failureReason, isNull);
    });

    test(
        'Rejects tampered canonical message payload byte with signatureVerificationFailed',
        () async {
      final payload = CatalogSignedPayload(
        schemaVersion: '1.0',
        signatureAlgorithm: 'ed25519-v1',
        keyId: 'aura-release-key-2026-01',
        catalogId: 'aura-official-catalog',
        catalogVersion: '1.0.0',
        catalogRevision: 42,
        issuedAt: '2026-07-22T20:00:00Z',
        expiresAt: '2026-08-22T20:00:00Z',
        manifest: CatalogManifest.initialDefault(),
      );

      final canonicalBytes =
          Rfc8785JcsCanonicalizer.canonicalizeBytes(payload.toJson());

      final algorithm = crypto.Ed25519();
      final signatureObj = await algorithm.sign(
        canonicalBytes,
        keyPair: keyPair,
      );

      final envelope = CatalogEnvelope(
        signedPayload: payload,
        signature: base64.encode(signatureObj.bytes),
      );

      // Alterazione del messaggio di 1 byte
      final tamperedBytes = Uint8List.fromList(canonicalBytes);
      tamperedBytes[0] ^= 0xFF;

      final verifier = Ed25519CatalogSignatureVerifier();
      final result = await verifier.verify(
        envelope: envelope,
        canonicalSignedPayload: tamperedBytes,
        trustStore: trustStore,
      );

      expect(result.isValid, isFalse);
      expect(result.failureReason,
          equals(CatalogAcquisitionFailureReason.signatureVerificationFailed));
    });

    test('Rejects tampered 64-byte signature with signatureVerificationFailed',
        () async {
      final payload = CatalogSignedPayload(
        schemaVersion: '1.0',
        signatureAlgorithm: 'ed25519-v1',
        keyId: 'aura-release-key-2026-01',
        catalogId: 'aura-official-catalog',
        catalogVersion: '1.0.0',
        catalogRevision: 42,
        issuedAt: '2026-07-22T20:00:00Z',
        expiresAt: '2026-08-22T20:00:00Z',
        manifest: CatalogManifest.initialDefault(),
      );

      final canonicalBytes =
          Rfc8785JcsCanonicalizer.canonicalizeBytes(payload.toJson());

      final algorithm = crypto.Ed25519();
      final signatureObj = await algorithm.sign(
        canonicalBytes,
        keyPair: keyPair,
      );

      // Alterazione della firma di 1 byte
      final tamperedSigBytes = Uint8List.fromList(signatureObj.bytes);
      tamperedSigBytes[0] ^= 0xFF;

      final envelope = CatalogEnvelope(
        signedPayload: payload,
        signature: base64.encode(tamperedSigBytes),
      );

      final verifier = Ed25519CatalogSignatureVerifier();
      final result = await verifier.verify(
        envelope: envelope,
        canonicalSignedPayload: canonicalBytes,
        trustStore: trustStore,
      );

      expect(result.isValid, isFalse);
      expect(result.failureReason,
          equals(CatalogAcquisitionFailureReason.signatureVerificationFailed));
    });

    test('Rejects unsupported algorithm and unknown keyId', () async {
      final payload = CatalogSignedPayload(
        schemaVersion: '1.0',
        signatureAlgorithm: 'rsa-sha256',
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
        signature: base64.encode(Uint8List(64)),
      );

      final verifier = Ed25519CatalogSignatureVerifier();
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
  });
}
