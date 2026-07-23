import '../domain/catalog_provider_contracts.dart';
import '../domain/catalog_selection_policy.dart';
import '../domain/validated_catalog_candidate.dart';

/// Esito tipizzato del coordinamento dell'acquisizione tra i provider della catena.
final class CatalogAcquisitionCoordinatorResult {
  final List<ValidatedCatalogCandidate> validCandidates;
  final CatalogSelectionResult selectionResult;

  const CatalogAcquisitionCoordinatorResult({
    required this.validCandidates,
    required this.selectionResult,
  });

  bool get hasSelection => selectionResult.hasSelection;
  ValidatedCatalogCandidate? get selectedCandidate =>
      selectionResult.selectedCandidate;
}

/// Coordinatore della catena di acquisizione e selezione del candidato di catalogo.
final class CatalogAcquisitionCoordinator {
  final List<CatalogProvider> _providers;

  CatalogAcquisitionCoordinator({
    required List<CatalogProvider> providers,
  }) : _providers = List.unmodifiable(providers);

  /// Esegue la catena di interrogazione dei provider in [providers] nell'ordine configurato.
  Future<CatalogAcquisitionCoordinatorResult> acquireCandidates({
    required CatalogProviderContext context,
    String? targetCatalogId,
    bool isProduction = true,
  }) async {
    final validCandidates = <ValidatedCatalogCandidate>[];

    for (final provider in _providers) {
      final result = await provider.getCandidate(context);
      if (result.isSuccess && result.candidate != null) {
        validCandidates.add(result.candidate!);
      }
    }

    final selectionResult = CatalogSelectionPolicy.selectCandidate(
      candidates: validCandidates,
      targetCatalogId: targetCatalogId,
      isProduction: isProduction,
    );

    return CatalogAcquisitionCoordinatorResult(
      validCandidates: validCandidates,
      selectionResult: selectionResult,
    );
  }
}
