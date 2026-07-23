import 'catalog_acquisition_exceptions.dart';
import 'catalog_compatibility_evaluator.dart';
import 'validated_catalog_candidate.dart';

/// Risultato della valutazione delle regole di refresh ed anti-downgrade di catalogo.
final class CatalogRefreshEvaluationResult {
  final bool isQualified;
  final CatalogAcquisitionFailureReason? rejectionReason;
  final String? message;

  const CatalogRefreshEvaluationResult.qualified()
      : isQualified = true,
        rejectionReason = null,
        message = null;

  const CatalogRefreshEvaluationResult.rejected({
    required this.rejectionReason,
    required this.message,
  }) : isQualified = false;
}

/// Policy per la valutazione della freschezza, compatibilità e anti-downgrade dei cataloghi remoti.
abstract final class CatalogRefreshPolicy {
  /// Tolleranza predefinita per il disallineamento dell'orologio di sistema (Clock Skew Tolerance) in secondi (5 minuti).
  static const int defaultClockSkewMarginSeconds = 300;

  /// Valuta se un nuovo candidato remoto [remoteCandidate] è idoneo a sostituire o aggiornare
  /// un candidato attualmente in cache [cachedCandidate].
  static CatalogRefreshEvaluationResult evaluateRemoteRefresh({
    required ValidatedCatalogCandidate remoteCandidate,
    ValidatedCatalogCandidate? cachedCandidate,
    required DateTime nowUtc,
    required String applicationVersion,
    CatalogCompatibilityEvaluator? compatibilityEvaluator,
    int clockSkewMarginSeconds = defaultClockSkewMarginSeconds,
  }) {
    final remotePayload = remoteCandidate.envelope.signedPayload;

    // 1. Verifica della data di scadenza (expiresAt) con tolleranza per il clock skew
    if (remotePayload.expiresAt.isNotEmpty) {
      final parsedExpiresAt = DateTime.tryParse(remotePayload.expiresAt);
      if (parsedExpiresAt != null) {
        final maxAllowedTime = parsedExpiresAt
            .add(Duration(seconds: clockSkewMarginSeconds))
            .toUtc();
        if (nowUtc.toUtc().isAfter(maxAllowedTime)) {
          return const CatalogRefreshEvaluationResult.rejected(
            rejectionReason: CatalogAcquisitionFailureReason.expiredCatalog,
            message: 'Il catalogo remoto fornito risulta scaduto.',
          );
        }
      }
    }

    // 2. Valutazione della compatibilità dello schema e della versione applicativa
    if (!remoteCandidate.compatibility.isCompatible) {
      return const CatalogRefreshEvaluationResult.rejected(
        rejectionReason:
            CatalogAcquisitionFailureReason.unsupportedSchemaVersion,
        message:
            'Il catalogo remoto non è compatibile con la versione corrente.',
      );
    }

    // Se non esiste alcun catalogo in cache, il remoto valido e compatibile viene qualificato subito
    if (cachedCandidate == null) {
      return const CatalogRefreshEvaluationResult.qualified();
    }

    final cachedPayload = cachedCandidate.envelope.signedPayload;

    // 3. Namespace Matching (catalogId)
    if (remotePayload.catalogId != cachedPayload.catalogId) {
      return const CatalogRefreshEvaluationResult.rejected(
        rejectionReason:
            CatalogAcquisitionFailureReason.catalogIdentityMismatch,
        message:
            'Mismatch di namespace: il catalogId remoto non corrisponde a quello in cache.',
      );
    }

    // 4. Monotonic Revision Check (catalogRevision)
    if (remotePayload.catalogRevision < cachedPayload.catalogRevision) {
      return const CatalogRefreshEvaluationResult.rejected(
        rejectionReason:
            CatalogAcquisitionFailureReason.catalogRevisionDowngrade,
        message:
            'Tentativo di downgrade: la revisione remota è inferiore a quella in cache.',
      );
    }

    // 5. Gestione di pari revisione nello stesso namespace ma digest discordanti
    if (remotePayload.catalogRevision == cachedPayload.catalogRevision) {
      if (remoteCandidate.canonicalPayloadDigest !=
          cachedCandidate.canonicalPayloadDigest) {
        return const CatalogRefreshEvaluationResult.rejected(
          rejectionReason:
              CatalogAcquisitionFailureReason.catalogIdentityMismatch,
          message:
              'Conflitto di integrità: pari revisione di catalogo con digest del payload canonico discordanti.',
        );
      }
    }

    return const CatalogRefreshEvaluationResult.qualified();
  }
}
