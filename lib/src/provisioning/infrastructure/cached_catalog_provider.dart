import '../domain/catalog_acquisition_exceptions.dart';
import '../domain/catalog_acquisition_models.dart';
import '../domain/catalog_provider_contracts.dart';
import 'catalog_cache_repository.dart';

/// Provider di catalogo basato sulla cache firmata persistita localmente.
final class CachedCatalogProvider implements CatalogProvider {
  final CatalogCacheRepository _repository;

  CachedCatalogProvider({required CatalogCacheRepository repository})
      : _repository = repository;

  @override
  CatalogSource get source => CatalogSource.cachedSigned;

  @override
  Future<CatalogProviderResult> getCandidate(
    CatalogProviderContext context,
  ) async {
    try {
      final envelope = await _repository.readEnvelope();
      if (envelope == null) {
        return const CatalogProviderResult.absent();
      }

      final factoryResult = await context.candidateFactory.createCandidate(
        envelope: envelope,
        source: source,
        trustStore: context.trustStore,
        compatibilityEvaluator: context.compatibilityEvaluator,
        validationService: context.validationService,
        signatureVerifier: context.signatureVerifier,
        nowUtc: context.nowUtc,
        applicationVersion: context.applicationVersion,
      );

      if (factoryResult.isSuccess) {
        return CatalogProviderResult.success(factoryResult.candidate);
      } else {
        return CatalogProviderResult.failure(
          failureReason: factoryResult.failureReason,
          message: factoryResult.errorMessage ??
              'Fallita la validazione del catalogo in cache.',
        );
      }
    } catch (e) {
      return CatalogProviderResult.failure(
        failureReason: CatalogAcquisitionFailureReason.malformedEnvelope,
        message: 'Errore durante la lettura del catalogo in cache: $e',
      );
    }
  }
}
