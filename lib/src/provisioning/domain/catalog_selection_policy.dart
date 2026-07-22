import 'catalog_acquisition_exceptions.dart';
import 'catalog_acquisition_models.dart';
import 'validated_catalog_candidate.dart';

/// Stato dell'esito della selezione tra candidati di catalogo.
enum CatalogSelectionStatus {
  selected,
  allRejected,
  sameRevisionMismatch,
  noCandidates,
}

/// DTO contenente l'esito della selezione tra candidati di catalogo.
final class CatalogSelectionResult {
  final ValidatedCatalogCandidate? selectedCandidate;
  final CatalogSelectionStatus status;
  final CatalogAcquisitionFailureReason? conflictReason;
  final List<ValidatedCatalogCandidate> rejectedCandidates;

  const CatalogSelectionResult({
    this.selectedCandidate,
    required this.status,
    this.conflictReason,
    this.rejectedCandidates = const [],
  });

  bool get hasSelection =>
      status == CatalogSelectionStatus.selected && selectedCandidate != null;
}

/// Policy di selezione deterministica tra candidati di catalogo validati.
abstract final class CatalogSelectionPolicy {
  /// Valuta ed ordina i [candidates] selezionando il catalogo con priorità più elevata.
  static CatalogSelectionResult selectCandidate({
    required List<ValidatedCatalogCandidate> candidates,
    bool isProduction = true,
  }) {
    if (candidates.isEmpty) {
      return const CatalogSelectionResult(
        status: CatalogSelectionStatus.noCandidates,
      );
    }

    final validCandidates = <ValidatedCatalogCandidate>[];
    final rejected = <ValidatedCatalogCandidate>[];

    for (final candidate in candidates) {
      // 1. Esclusione di localDevelopment nei contesti di produzione
      if (isProduction && candidate.source == CatalogSource.localDevelopment) {
        rejected.add(candidate);
        continue;
      }

      // 2. Filtro incompatibili
      if (!candidate.compatibility.isCompatible) {
        rejected.add(candidate);
        continue;
      }

      validCandidates.add(candidate);
    }

    if (validCandidates.isEmpty) {
      return CatalogSelectionResult(
        status: CatalogSelectionStatus.allRejected,
        rejectedCandidates: rejected,
      );
    }

    // 3. Controllo dello stesso catalogId namespace ed eventuale mismatch di payload a pari revisione
    final candidatesByNamespace = <String, List<ValidatedCatalogCandidate>>{};
    for (final cand in validCandidates) {
      candidatesByNamespace.putIfAbsent(cand.catalogId, () => []).add(cand);
    }

    for (final entry in candidatesByNamespace.entries) {
      final list = entry.value;
      final revisionMap = <int, ValidatedCatalogCandidate>{};

      for (final cand in list) {
        final existing = revisionMap[cand.catalogRevision];
        if (existing != null) {
          // Se la stessa revisione ha digest di payload differenti nello stesso catalogId -> Mismatch!
          if (existing.canonicalPayloadDigest != cand.canonicalPayloadDigest) {
            return CatalogSelectionResult(
              status: CatalogSelectionStatus.sameRevisionMismatch,
              conflictReason:
                  CatalogAcquisitionFailureReason.catalogIdentityMismatch,
              rejectedCandidates: validCandidates,
            );
          }
        } else {
          revisionMap[cand.catalogRevision] = cand;
        }
      }
    }

    // 4. Ranking deterministico dei candidati validi:
    // Priorità sorgente: remoteSigned (3) > cachedSigned (2) > bundledBootstrap (1) > localDevelopment (0)
    // A parità di sorgente: catalogRevision decrescente (più recente)
    validCandidates.sort((a, b) {
      final sourceRankA = _getSourceRank(a.source);
      final sourceRankB = _getSourceRank(b.source);
      if (sourceRankA != sourceRankB) {
        return sourceRankB.compareTo(sourceRankA);
      }
      return b.catalogRevision.compareTo(a.catalogRevision);
    });

    final selected = validCandidates.first;
    return CatalogSelectionResult(
      selectedCandidate: selected,
      status: CatalogSelectionStatus.selected,
      rejectedCandidates: rejected,
    );
  }

  static int _getSourceRank(CatalogSource source) {
    switch (source) {
      case CatalogSource.remoteSigned:
        return 3;
      case CatalogSource.cachedSigned:
        return 2;
      case CatalogSource.bundledBootstrap:
        return 1;
      case CatalogSource.localDevelopment:
        return 0;
    }
  }
}
