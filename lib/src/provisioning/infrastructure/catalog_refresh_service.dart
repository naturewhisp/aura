import '../crypto/catalog_signature_verifier.dart';
import '../crypto/catalog_trust_store.dart';
import '../domain/catalog_acquisition_exceptions.dart';
import '../domain/catalog_acquisition_models.dart';
import '../domain/catalog_compatibility_evaluator.dart';
import '../domain/catalog_provider_contracts.dart';
import '../domain/catalog_refresh_policy.dart';
import '../domain/catalog_selection_policy.dart';
import '../domain/provisioning_clock.dart';
import '../domain/validated_catalog_candidate.dart';
import '../domain/validated_catalog_candidate_factory.dart';
import '../validation/catalog_validation_service.dart';
import 'bundled_catalog_provider.dart';
import 'cached_catalog_provider.dart';
import 'catalog_cache_repository.dart';
import 'remote_catalog_provider.dart';

/// Servizio applicativo di livello superiore per l'aggiornamento, il refresh e l'acquisizione del catalogo.
final class CatalogRefreshService {
  final CatalogCacheRepository _cacheRepository;
  final CatalogTrustStore _trustStore;
  final CatalogCompatibilityEvaluator _compatibilityEvaluator;
  final CatalogValidationService _validationService;
  final CatalogSignatureVerifier _signatureVerifier;
  final ValidatedCatalogCandidateFactory _candidateFactory;
  final BundledCatalogProvider _bundledProvider;
  final CachedCatalogProvider _cachedProvider;
  final RemoteCatalogProvider? _remoteProvider;
  final ProvisioningClock _clock;
  final String _applicationVersion;
  final bool _isProduction;

  CatalogRefreshService({
    required CatalogCacheRepository cacheRepository,
    required CatalogTrustStore trustStore,
    required CatalogCompatibilityEvaluator compatibilityEvaluator,
    required CatalogValidationService validationService,
    required CatalogSignatureVerifier signatureVerifier,
    required ValidatedCatalogCandidateFactory candidateFactory,
    required BundledCatalogProvider bundledProvider,
    required CachedCatalogProvider cachedProvider,
    RemoteCatalogProvider? remoteProvider,
    ProvisioningClock clock = const SystemProvisioningClock(),
    required String applicationVersion,
    bool isProduction = true,
  })  : _cacheRepository = cacheRepository,
        _trustStore = trustStore,
        _compatibilityEvaluator = compatibilityEvaluator,
        _validationService = validationService,
        _signatureVerifier = signatureVerifier,
        _candidateFactory = candidateFactory,
        _bundledProvider = bundledProvider,
        _cachedProvider = cachedProvider,
        _remoteProvider = remoteProvider,
        _clock = clock,
        _applicationVersion = applicationVersion,
        _isProduction = isProduction;

  /// Esegue la procedura di acquisizione, aggiornamento e selezione del catalogo idoneo.
  Future<CatalogAcquisitionResult> refreshCatalog(
    CatalogRefreshRequest request,
  ) async {
    final nowUtc = _clock.nowUtc();
    final diagnostics = <String, dynamic>{
      'forceRefresh': request.forceRefresh,
      'offlineOnly': request.offlineOnly,
      'targetCatalogId': request.targetCatalogId,
      'applicationVersion': _applicationVersion,
      'isProduction': _isProduction,
    };

    final context = CatalogProviderContext(
      trustStore: _trustStore,
      compatibilityEvaluator: _compatibilityEvaluator,
      validationService: _validationService,
      signatureVerifier: _signatureVerifier,
      candidateFactory: _candidateFactory,
      nowUtc: nowUtc,
      applicationVersion: _applicationVersion,
    );

    final candidates = <ValidatedCatalogCandidate>[];

    // 1. Acquisizione candidato Bootstrap integrato
    final bundledResult = await _bundledProvider.getCandidate(context);
    if (bundledResult.isSuccess && bundledResult.candidate != null) {
      candidates.add(bundledResult.candidate!);
      diagnostics['bundledRevision'] =
          bundledResult.candidate!.envelope.signedPayload.catalogRevision;
    }

    // 2. Acquisizione candidato Signed Cache locale
    final cachedResult = await _cachedProvider.getCandidate(context);
    ValidatedCatalogCandidate? cachedCandidate;
    if (cachedResult.isSuccess && cachedResult.candidate != null) {
      cachedCandidate = cachedResult.candidate;
      candidates.add(cachedCandidate!);
      diagnostics['cachedRevision'] =
          cachedCandidate.envelope.signedPayload.catalogRevision;
    }

    // 3. Acquisizione e verifica candidato Remoto (se non offlineOnly)
    final remoteProvider = _remoteProvider;
    if (!request.offlineOnly && remoteProvider != null) {
      final remoteResult = await remoteProvider.getCandidate(context);
      if (remoteResult.isSuccess && remoteResult.candidate != null) {
        final remoteCandidate = remoteResult.candidate!;
        diagnostics['remoteFetchStatus'] = 'success';
        diagnostics['remoteRevision'] =
            remoteCandidate.envelope.signedPayload.catalogRevision;

        // Valutazione anti-downgrade e freschezza del remoto rispetto alla cache
        final refreshEvaluation = CatalogRefreshPolicy.evaluateRemoteRefresh(
          remoteCandidate: remoteCandidate,
          cachedCandidate: cachedCandidate,
          nowUtc: nowUtc,
          applicationVersion: _applicationVersion,
          compatibilityEvaluator: _compatibilityEvaluator,
        );

        if (refreshEvaluation.isQualified) {
          diagnostics['remoteQualified'] = true;
          // Scrittura atomica dell'envelope remota nella cache firmata locale
          await _cacheRepository.writeEnvelope(remoteCandidate.envelope);
          candidates.add(remoteCandidate);
        } else {
          diagnostics['remoteQualified'] = false;
          diagnostics['remoteRejectionReason'] =
              refreshEvaluation.rejectionReason?.name;
          diagnostics['remoteRejectionMessage'] = refreshEvaluation.message;
        }
      } else {
        diagnostics['remoteFetchStatus'] = 'failed';
        diagnostics['remoteFailureReason'] = remoteResult.failureReason?.name;
        diagnostics['remoteErrorMessage'] = remoteResult.message;
      }
    } else {
      diagnostics['remoteFetchStatus'] =
          request.offlineOnly ? 'skippedOfflineOnly' : 'noRemoteProvider';
    }

    // 4. Selezione deterministica del miglior candidato tramite CatalogSelectionPolicy
    final selectionResult = CatalogSelectionPolicy.selectCandidate(
      candidates: candidates,
      targetCatalogId: request.targetCatalogId,
      isProduction: _isProduction,
    );

    if (!selectionResult.hasSelection ||
        selectionResult.selectedCandidate == null) {
      throw CatalogAcquisitionException(
        selectionResult.message ??
            'Impossibile selezionare un catalogo valido e compatibile.',
        failureReason: selectionResult.conflictReason ??
            CatalogAcquisitionFailureReason.noCompatibleCatalogCandidate,
      );
    }

    final selected = selectionResult.selectedCandidate!;
    diagnostics['selectedSource'] = selected.source.name;
    diagnostics['selectedTrustLevel'] = selected.trustLevel.name;
    diagnostics['selectedCatalogId'] =
        selected.envelope.signedPayload.catalogId;
    diagnostics['selectedCatalogRevision'] =
        selected.envelope.signedPayload.catalogRevision;

    return CatalogAcquisitionResult(
      effectiveCatalog: selected.envelope.signedPayload.manifest,
      trustLevel: selected.trustLevel,
      catalogSource: selected.source,
      acquiredAt: nowUtc,
      diagnostics: diagnostics,
    );
  }
}
