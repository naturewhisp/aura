import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import '../crypto/catalog_signature_verifier.dart';
import '../crypto/catalog_trust_store.dart';
import '../crypto/rfc8785_jcs_canonicalizer.dart';
import '../validation/catalog_validation_service.dart';
import 'catalog_acquisition_exceptions.dart';
import 'catalog_acquisition_models.dart';
import 'catalog_compatibility_evaluator.dart';
import 'validated_catalog_candidate.dart';

/// Risultato della creazione di un [ValidatedCatalogCandidate] tramite la factory.
final class ValidatedCatalogCandidateResult {
  final ValidatedCatalogCandidate? candidate;
  final CatalogAcquisitionFailureReason? failureReason;
  final String? errorMessage;

  const ValidatedCatalogCandidateResult.success(this.candidate)
      : failureReason = null,
        errorMessage = null;

  const ValidatedCatalogCandidateResult.failure({
    required this.failureReason,
    required this.errorMessage,
  }) : candidate = null;

  bool get isSuccess => candidate != null;
}

/// Contratto ed implementazione per la fabbrica di [ValidatedCatalogCandidate].
abstract interface class ValidatedCatalogCandidateFactory {
  /// Costruisce in modo sicuro e atomico un [ValidatedCatalogCandidate] dopo aver superato
  /// sia la validazione strutturale/semantica sia la verifica crittografica della firma.
  Future<ValidatedCatalogCandidateResult> createCandidate({
    required CatalogEnvelope envelope,
    required CatalogSource source,
    required CatalogTrustStore trustStore,
    required CatalogCompatibilityEvaluator compatibilityEvaluator,
    required CatalogValidationService validationService,
    required CatalogSignatureVerifier signatureVerifier,
    required DateTime nowUtc,
    required String applicationVersion,
  });
}

/// Implementazione predefinita di [ValidatedCatalogCandidateFactory].
final class DefaultValidatedCatalogCandidateFactory
    implements ValidatedCatalogCandidateFactory {
  const DefaultValidatedCatalogCandidateFactory();

  @override
  Future<ValidatedCatalogCandidateResult> createCandidate({
    required CatalogEnvelope envelope,
    required CatalogSource source,
    required CatalogTrustStore trustStore,
    required CatalogCompatibilityEvaluator compatibilityEvaluator,
    required CatalogValidationService validationService,
    required CatalogSignatureVerifier signatureVerifier,
    required DateTime nowUtc,
    required String applicationVersion,
  }) async {
    // 1. Validazione semantica e strutturale dell'envelope
    final validationResult = validationService.validate(
      envelope,
      nowUtc: nowUtc,
      source: source,
    );

    if (!validationResult.isValid) {
      return ValidatedCatalogCandidateResult.failure(
        failureReason: validationResult.failureReason ??
            CatalogAcquisitionFailureReason.malformedEnvelope,
        errorMessage: validationResult.errorMessage ?? 'Validazione fallita.',
      );
    }

    // 2. Canonicalizzazione JCS (RFC 8785) del payload firmato
    Uint8List canonicalPayloadBytes;
    try {
      canonicalPayloadBytes = Rfc8785JcsCanonicalizer.canonicalizeBytes(
        envelope.signedPayload.toJson(),
      );
    } catch (e) {
      return ValidatedCatalogCandidateResult.failure(
        failureReason: CatalogAcquisitionFailureReason.canonicalizationFailed,
        errorMessage: 'Canonicalizzazione JCS del payload fallita: $e',
      );
    }

    // 3. Verifica crittografica della firma (per cataloghi firmati remoti/cached)
    CatalogTrustLevel trustLevel;
    if (source == CatalogSource.remoteSigned ||
        source == CatalogSource.cachedSigned) {
      final sigResult = await signatureVerifier.verify(
        envelope: envelope,
        canonicalSignedPayload: canonicalPayloadBytes,
        trustStore: trustStore,
      );

      if (!sigResult.isValid) {
        return ValidatedCatalogCandidateResult.failure(
          failureReason: sigResult.failureReason ??
              CatalogAcquisitionFailureReason.signatureVerificationFailed,
          errorMessage: 'Verifica crittografica della firma Ed25519 fallita.',
        );
      }
      trustLevel = CatalogTrustLevel.signatureVerified;
    } else if (source == CatalogSource.bundledBootstrap) {
      trustLevel = CatalogTrustLevel.bootstrapDeclared;
    } else {
      trustLevel = CatalogTrustLevel.developmentUnsigned;
    }

    // 4. Valutazione della compatibilità di schema e versione applicativa
    final compatibility = compatibilityEvaluator.evaluate(
      payload: envelope.signedPayload,
      applicationVersion: applicationVersion,
    );

    // 5. Calcolo del digest SHA-256 esadecimale a 64 caratteri del payload canonico
    final canonicalDigest = sha256.convert(canonicalPayloadBytes).toString();

    // 6. Istanziazione del candidato validato e coerente
    try {
      final candidate = ValidatedCatalogCandidate(
        envelope: envelope,
        source: source,
        trustLevel: trustLevel,
        compatibility: compatibility,
        canonicalPayloadDigest: canonicalDigest,
      );
      return ValidatedCatalogCandidateResult.success(candidate);
    } catch (e) {
      return ValidatedCatalogCandidateResult.failure(
        failureReason: CatalogAcquisitionFailureReason.malformedEnvelope,
        errorMessage: 'Invarianti del candidato non soddisfatte: $e',
      );
    }
  }
}
