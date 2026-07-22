import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart' as crypto;
import '../domain/catalog_acquisition_exceptions.dart';
import '../domain/catalog_acquisition_models.dart';
import 'catalog_trust_store.dart';

/// Stato dell'esito della verifica di firma crittografica.
enum CatalogSignatureVerificationStatus {
  valid,
  failed,
}

/// Risultato tipizzato ed invariante dell'operazione di verifica firma.
final class CatalogSignatureVerificationResult {
  final CatalogSignatureVerificationStatus status;
  final CatalogAcquisitionFailureReason? failureReason;
  final String? keyId;

  const CatalogSignatureVerificationResult.valid({this.keyId})
      : status = CatalogSignatureVerificationStatus.valid,
        failureReason = null;

  const CatalogSignatureVerificationResult.failure(
    CatalogAcquisitionFailureReason reason, {
    this.keyId,
  })  : status = CatalogSignatureVerificationStatus.failed,
        failureReason = reason;

  bool get isValid => status == CatalogSignatureVerificationStatus.valid;

  @override
  String toString() =>
      'CatalogSignatureVerificationResult(status: $status, reason: $failureReason, keyId: $keyId)';
}

/// Contratto astratto per il verificatore di firma digitale dell'envelope di catalogo.
abstract interface class CatalogSignatureVerifier {
  /// Verifica la firma dell'[envelope] sui byte canonicalizzati [canonicalSignedPayload] tramite le chiavi in [trustStore].
  Future<CatalogSignatureVerificationResult> verify({
    required CatalogEnvelope envelope,
    required Uint8List canonicalSignedPayload,
    required CatalogTrustStore trustStore,
  });
}

/// Implementazione concreta per l'algoritmo di firma `ed25519-v1` (RFC 8032) delegata a package:cryptography.
final class Ed25519CatalogSignatureVerifier
    implements CatalogSignatureVerifier {
  final crypto.Ed25519 _algorithm;

  Ed25519CatalogSignatureVerifier({crypto.Ed25519? algorithm})
      : _algorithm = algorithm ?? crypto.Ed25519();

  @override
  Future<CatalogSignatureVerificationResult> verify({
    required CatalogEnvelope envelope,
    required Uint8List canonicalSignedPayload,
    required CatalogTrustStore trustStore,
  }) async {
    final payload = envelope.signedPayload;

    // 1. Verifica dell'algoritmo supportato ('ed25519-v1')
    if (payload.signatureAlgorithm != 'ed25519-v1') {
      return CatalogSignatureVerificationResult.failure(
        CatalogAcquisitionFailureReason.unsupportedSignatureAlgorithm,
        keyId: payload.keyId,
      );
    }

    // 2. Verifica della presenza di keyId
    if (payload.keyId.trim().isEmpty) {
      return const CatalogSignatureVerificationResult.failure(
        CatalogAcquisitionFailureReason.unknownKeyId,
      );
    }

    // 3. Ricerca della chiave fidata nel trust store
    final trustedKey = await trustStore.findTrustedKey(payload.keyId);
    if (trustedKey == null) {
      return CatalogSignatureVerificationResult.failure(
        CatalogAcquisitionFailureReason.unknownKeyId,
        keyId: payload.keyId,
      );
    }

    // 4. Decodifica della firma in Base64
    Uint8List signatureBytes;
    try {
      signatureBytes = Uint8List.fromList(base64.decode(envelope.signature));
    } catch (_) {
      return CatalogSignatureVerificationResult.failure(
        CatalogAcquisitionFailureReason.invalidSignatureEncoding,
        keyId: payload.keyId,
      );
    }

    // 5. Verifica della lunghezza della firma per Ed25519 (64 byte)
    if (signatureBytes.length != 64) {
      return CatalogSignatureVerificationResult.failure(
        CatalogAcquisitionFailureReason.invalidSignatureLength,
        keyId: payload.keyId,
      );
    }

    // 6. Esecuzione della verifica crittografica RFC 8032 reale tramite package:cryptography
    try {
      final ed25519Signature = crypto.Signature(
        signatureBytes,
        publicKey: crypto.SimplePublicKey(
          trustedKey.rawKeyBytes,
          type: crypto.KeyPairType.ed25519,
        ),
      );

      final isVerified = await _algorithm.verify(
        canonicalSignedPayload,
        signature: ed25519Signature,
      );

      if (!isVerified) {
        return CatalogSignatureVerificationResult.failure(
          CatalogAcquisitionFailureReason.signatureVerificationFailed,
          keyId: payload.keyId,
        );
      }

      return CatalogSignatureVerificationResult.valid(keyId: payload.keyId);
    } catch (_) {
      return CatalogSignatureVerificationResult.failure(
        CatalogAcquisitionFailureReason.signatureVerificationFailed,
        keyId: payload.keyId,
      );
    }
  }
}

/// Implementazione mock per i test unitari.
final class MockCatalogSignatureVerifier implements CatalogSignatureVerifier {
  final CatalogSignatureVerificationResult defaultResult;

  const MockCatalogSignatureVerifier({
    this.defaultResult = const CatalogSignatureVerificationResult.valid(),
  });

  @override
  Future<CatalogSignatureVerificationResult> verify({
    required CatalogEnvelope envelope,
    required Uint8List canonicalSignedPayload,
    required CatalogTrustStore trustStore,
  }) async {
    return defaultResult;
  }
}
