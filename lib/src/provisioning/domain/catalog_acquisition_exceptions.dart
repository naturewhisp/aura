/// Enum normativo per le ragioni di fallimento dell'acquisizione, validazione e verifica di catalogo.
enum CatalogAcquisitionFailureReason {
  malformedEnvelope,
  unsupportedSchemaVersion,
  unsupportedSignatureAlgorithm,
  invalidSignatureEncoding,
  invalidSignatureLength,
  unknownKeyId,
  invalidPublicKeyLength,
  signatureVerificationFailed,
  floatingRepositoryRevision,
  invalidIssuedAt,
  invalidExpiresAt,
  catalogExpired,
  invalidSha256,
  invalidSizeBytes,
  duplicateArtifactIdentity,
  noCompatibleCatalogCandidate,
  catalogIdentityMismatch,
  applicationIncompatible,
  canonicalizationFailed,
  nonJsonSafeValue,
}

/// Eccezione di dominio base per i fallimenti di acquisizione e gestione catalogo.
class CatalogAcquisitionException implements Exception {
  final String message;
  final CatalogAcquisitionFailureReason failureReason;
  final Object? cause;

  CatalogAcquisitionException(
    this.message, {
    required this.failureReason,
    this.cause,
  });

  @override
  String toString() =>
      'CatalogAcquisitionException: $message (reason: ${failureReason.name})';
}

/// Eccezione scatenata per invalidità strutturale o semantica del catalogo.
class CatalogValidationException extends CatalogAcquisitionException {
  CatalogValidationException(
    super.message, {
    required super.failureReason,
    super.cause,
  });
}

/// Eccezione scatenata per fallimenti di verifica della firma crittografica o chiavi non fidate.
class CatalogSignatureException extends CatalogAcquisitionException {
  CatalogSignatureException(
    super.message, {
    required super.failureReason,
    super.cause,
  });
}

/// Eccezione scatenata per revisioni del repository non immutabili (es. branch o tag mobili).
class InvalidCatalogRevisionException extends CatalogAcquisitionException {
  InvalidCatalogRevisionException(
    super.message, {
    super.failureReason =
        CatalogAcquisitionFailureReason.floatingRepositoryRevision,
    super.cause,
  });
}
