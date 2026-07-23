import '../crypto/catalog_signature_verifier.dart';
import '../crypto/catalog_trust_store.dart';
import '../validation/catalog_validation_service.dart';
import 'catalog_acquisition_exceptions.dart';
import 'catalog_acquisition_models.dart';
import 'catalog_compatibility_evaluator.dart';
import 'validated_catalog_candidate.dart';
import 'validated_catalog_candidate_factory.dart';

/// DTO contenente i parametri di una richiesta di refresh o acquisizione di catalogo.
final class CatalogRefreshRequest {
  final bool forceRefresh;
  final bool offlineOnly;
  final Duration? timeout;
  final String? targetCatalogId;

  const CatalogRefreshRequest({
    this.forceRefresh = false,
    this.offlineOnly = false,
    this.timeout,
    this.targetCatalogId,
  });

  @override
  String toString() =>
      'CatalogRefreshRequest(force: $forceRefresh, offlineOnly: $offlineOnly, timeout: $timeout, targetCatalogId: $targetCatalogId)';
}

/// Contesto condiviso di runtime fornito a ciascun [CatalogProvider].
final class CatalogProviderContext {
  final CatalogTrustStore trustStore;
  final CatalogCompatibilityEvaluator compatibilityEvaluator;
  final CatalogValidationService validationService;
  final CatalogSignatureVerifier signatureVerifier;
  final ValidatedCatalogCandidateFactory candidateFactory;
  final DateTime nowUtc;
  final String applicationVersion;
  final Duration remoteTimeout;
  final String? cachedEtag;
  final bool forceRefresh;

  const CatalogProviderContext({
    required this.trustStore,
    required this.compatibilityEvaluator,
    required this.validationService,
    required this.signatureVerifier,
    required this.candidateFactory,
    required this.nowUtc,
    required this.applicationVersion,
    this.remoteTimeout = const Duration(seconds: 15),
    this.cachedEtag,
    this.forceRefresh = false,
  });
}

/// Esito tipizzato restituito dall'interrogazione di un [CatalogProvider].
final class CatalogProviderResult {
  final ValidatedCatalogCandidate? candidate;
  final CatalogAcquisitionFailureReason? failureReason;
  final String? message;
  final bool isNotModified;
  final String? responseEtag;
  final Uri? sourceUri;

  const CatalogProviderResult.success(
    this.candidate, {
    this.responseEtag,
    this.sourceUri,
  })  : failureReason = null,
        message = null,
        isNotModified = false;

  const CatalogProviderResult.notModified({
    this.responseEtag,
    this.message,
    this.sourceUri,
  })  : candidate = null,
        failureReason = null,
        isNotModified = true;

  const CatalogProviderResult.failure({
    required this.failureReason,
    required this.message,
  })  : candidate = null,
        isNotModified = false,
        responseEtag = null,
        sourceUri = null;

  const CatalogProviderResult.absent()
      : candidate = null,
        failureReason = null,
        message = null,
        isNotModified = false,
        responseEtag = null,
        sourceUri = null;

  bool get isSuccess => candidate != null;
  bool get isAbsent =>
      candidate == null && failureReason == null && !isNotModified;
  bool get isFailure => failureReason != null;
}

/// Contratto astratto per i provider di catalogo della catena di acquisizione.
abstract interface class CatalogProvider {
  /// Origine del catalogo fornito da questo provider.
  CatalogSource get source;

  /// Acquisisce e restituisce un [ValidatedCatalogCandidate] attraverso le componenti del [context].
  Future<CatalogProviderResult> getCandidate(CatalogProviderContext context);
}
