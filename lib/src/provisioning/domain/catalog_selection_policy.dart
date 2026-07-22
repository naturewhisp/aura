import 'catalog_acquisition_exceptions.dart';
import 'catalog_acquisition_models.dart';
import 'validated_catalog_candidate.dart';

/// Stato dell'esito della selezione del catalogo candidato.
enum CatalogSelectionStatus {
  selected,
  allRejected,
  sameRevisionMismatch,
}

/// Esito dell'applicazione della policy di selezione del catalogo.
final class CatalogSelectionResult {
  final CatalogSelectionStatus status;
  final ValidatedCatalogCandidate? selectedCandidate;
  final CatalogAcquisitionFailureReason? conflictReason;
  final String? message;

  const CatalogSelectionResult.selected(this.selectedCandidate)
      : status = CatalogSelectionStatus.selected,
        conflictReason = null,
        message = null;

  const CatalogSelectionResult.allRejected({this.message})
      : status = CatalogSelectionStatus.allRejected,
        selectedCandidate = null,
        conflictReason =
            CatalogAcquisitionFailureReason.noCompatibleCatalogCandidate;

  const CatalogSelectionResult.sameRevisionMismatch({
    required this.conflictReason,
    required this.message,
  })  : status = CatalogSelectionStatus.sameRevisionMismatch,
        selectedCandidate = null;

  bool get hasSelection => status == CatalogSelectionStatus.selected;
}

/// Policy per la selezione deterministica del miglior candidato di catalogo tra quelli validati.
abstract final class CatalogSelectionPolicy {
  /// Seleziona il candidato ottimale dall'elenco dei [candidates] validati.
  ///
  /// In modalità produzione ([isProduction] = true), le sorgenti `localDevelopment` vengono scartate.
  /// L'ordinamento dei candidati idonei privilegia:
  /// 1. La massima `catalogRevision` del catalogo;
  /// 2. A parità di revisione, il ranking della sorgente (`remoteSigned` > `cachedSigned` > `bundledBootstrap`).
  static CatalogSelectionResult selectCandidate({
    required List<ValidatedCatalogCandidate> candidates,
    required bool isProduction,
  }) {
    // 1. Filtraggio dei candidati compatibili e idonei al profilo di esecuzione
    final eligible = candidates.where((c) {
      if (!c.compatibility.isCompatible) return false;
      if (isProduction && c.source == CatalogSource.localDevelopment)
        return false;
      return true;
    }).toList();

    if (eligible.isEmpty) {
      return const CatalogSelectionResult.allRejected(
        message: 'Nessun candidato di catalogo valido e compatibile trovato.',
      );
    }

    // 2. Controllo di coerenza per pari revisione e catalogId ma digest differenti
    final candidatesByCatalogRevision =
        <String, Map<int, List<ValidatedCatalogCandidate>>>{};
    for (final c in eligible) {
      final catId = c.envelope.signedPayload.catalogId;
      final rev = c.envelope.signedPayload.catalogRevision;
      candidatesByCatalogRevision
          .putIfAbsent(catId, () => {})
          .putIfAbsent(rev, () => [])
          .add(c);
    }

    for (final revEntry in candidatesByCatalogRevision.values) {
      for (final listInRev in revEntry.values) {
        if (listInRev.length > 1) {
          final firstDigest = listInRev.first.canonicalPayloadDigest;
          for (final c in listInRev) {
            if (c.canonicalPayloadDigest != firstDigest) {
              return CatalogSelectionResult.sameRevisionMismatch(
                conflictReason:
                    CatalogAcquisitionFailureReason.catalogIdentityMismatch,
                message:
                    'Rilevato conflitto per la revisione ${c.envelope.signedPayload.catalogRevision} del catalogo ${c.envelope.signedPayload.catalogId}: digest del payload discordanti.',
              );
            }
          }
        }
      }
    }

    // 3. Ordinamento deterministico:
    // Prima per catalogRevision decrescente (revisione più recente);
    // A parità di revisione, per ranking della sorgente.
    eligible.sort((a, b) {
      final revA = a.envelope.signedPayload.catalogRevision;
      final revB = b.envelope.signedPayload.catalogRevision;
      if (revA != revB) {
        return revB.compareTo(revA); // Decrescente
      }
      return b.source.rank.compareTo(a.source.rank); // Decrescente
    });

    return CatalogSelectionResult.selected(eligible.first);
  }
}
