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
import 'lkg_catalog_metadata_repository.dart';
import 'remote_catalog_provider.dart';

/// Servizio applicativo di livello superiore per l'aggiornamento, il refresh e l'acquisizione del catalogo.
final class CatalogRefreshService {
  final CatalogCacheRepository _cacheRepository;
  final LkgCatalogMetadataRepository _lkgRepository;
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
    required LkgCatalogMetadataRepository lkgRepository,
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
        _lkgRepository = lkgRepository,
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

    final cacheReadResult = await _cacheRepository.readCache();
    final cachedRecord = cacheReadResult.record;

    final candidates = <ValidatedCatalogCandidate>[];

    // Contesto base per provider locali (bundled e cache)
    final baseContext = CatalogProviderContext(
      trustStore: _trustStore,
      compatibilityEvaluator: _compatibilityEvaluator,
      validationService: _validationService,
      signatureVerifier: _signatureVerifier,
      candidateFactory: _candidateFactory,
      nowUtc: nowUtc,
      applicationVersion: _applicationVersion,
      remoteTimeout: request.timeout ?? const Duration(seconds: 15),
      forceRefresh: request.forceRefresh,
    );

    // 1. Acquisizione candidato Bootstrap integrato
    final bundledResult = await _bundledProvider.getCandidate(baseContext);
    if (bundledResult.isSuccess && bundledResult.candidate != null) {
      candidates.add(bundledResult.candidate!);
      diagnostics['bundledRevision'] =
          bundledResult.candidate!.envelope.signedPayload.catalogRevision;
    }

    // 2. Acquisizione e validazione candidato Signed Cache locale
    final cachedResult = await _cachedProvider.getCandidate(baseContext);
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
      // Invia If-None-Match (cachedEtag) SOLO SE la cache locale ha prodotto un candidato candidato valido
      final remoteContext = CatalogProviderContext(
        trustStore: _trustStore,
        compatibilityEvaluator: _compatibilityEvaluator,
        validationService: _validationService,
        signatureVerifier: _signatureVerifier,
        candidateFactory: _candidateFactory,
        nowUtc: nowUtc,
        applicationVersion: _applicationVersion,
        remoteTimeout: request.timeout ?? const Duration(seconds: 15),
        cachedEtag: cachedCandidate != null ? cachedRecord?.etag : null,
        forceRefresh: request.forceRefresh,
      );

      var remoteResult = await remoteProvider.getCandidate(remoteContext);

      // Se riceve 304 ma per qualsiasi motivo cachedCandidate è nullo (guardia difensiva), esegue un GET incondizionato
      if (remoteResult.isNotModified && cachedCandidate == null) {
        final forcedContext = CatalogProviderContext(
          trustStore: _trustStore,
          compatibilityEvaluator: _compatibilityEvaluator,
          validationService: _validationService,
          signatureVerifier: _signatureVerifier,
          candidateFactory: _candidateFactory,
          nowUtc: nowUtc,
          applicationVersion: _applicationVersion,
          remoteTimeout: request.timeout ?? const Duration(seconds: 15),
          cachedEtag: null,
          forceRefresh: true,
        );
        remoteResult = await remoteProvider.getCandidate(forcedContext);
      }

      if (remoteResult.isNotModified) {
        diagnostics['remoteFetchStatus'] = 'notModified304';
        if (cachedCandidate != null) {
          diagnostics['remoteQualified'] = true;
          diagnostics['remoteRevision'] =
              cachedCandidate.envelope.signedPayload.catalogRevision;
        }
      } else if (remoteResult.isSuccess && remoteResult.candidate != null) {
        final remoteCandidate = remoteResult.candidate!;
        diagnostics['remoteFetchStatus'] = 'success';
        diagnostics['remoteRevision'] =
            remoteCandidate.envelope.signedPayload.catalogRevision;

        // Recupera i metadata LKG specifici per il catalogId remoto
        final lkgMetadata = await _lkgRepository.readMetadata(
          catalogId: remoteCandidate.envelope.signedPayload.catalogId,
        );

        // Valutazione anti-downgrade e freschezza del remoto rispetto alla cache ed allo stato LKG fidato del namespace
        final refreshEvaluation = CatalogRefreshPolicy.evaluateRemoteRefresh(
          remoteCandidate: remoteCandidate,
          cachedCandidate: cachedCandidate,
          lkgMetadata: lkgMetadata,
          nowUtc: nowUtc,
        );

        if (refreshEvaluation.isQualified) {
          diagnostics['remoteQualified'] = true;
          // Scrittura atomica del record di cache contenente l'envelope firmata, l'ETag ed la provenance (sourceUri)
          final newRecord = CachedCatalogRecord(
            envelope: remoteCandidate.envelope,
            etag: remoteResult.responseEtag,
            fetchedAtUtc: nowUtc,
            sourceUri: remoteResult.sourceUri,
          );
          await _cacheRepository.writeRecord(newRecord);

          // Persistenza dei metadata LKG fidati per-namespace per l'anti-downgrade permanente
          final newLkg = LkgCatalogMetadata(
            catalogId: remoteCandidate.envelope.signedPayload.catalogId,
            highestAcceptedRevision:
                remoteCandidate.envelope.signedPayload.catalogRevision,
            canonicalPayloadDigest: remoteCandidate.canonicalPayloadDigest,
            acceptedAtUtc: nowUtc,
          );
          await _lkgRepository.writeMetadata(newLkg);

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

    // Assicura che la revisione accettata in fase di selezione sia memorizzata nell'LKG per il relativo catalogId
    final selPayload = selected.envelope.signedPayload;
    final currentLkg = await _lkgRepository.readMetadata(
      catalogId: selPayload.catalogId,
    );
    if (currentLkg == null ||
        selPayload.catalogRevision > currentLkg.highestAcceptedRevision) {
      await _lkgRepository.writeMetadata(LkgCatalogMetadata(
        catalogId: selPayload.catalogId,
        highestAcceptedRevision: selPayload.catalogRevision,
        canonicalPayloadDigest: selected.canonicalPayloadDigest,
        acceptedAtUtc: nowUtc,
      ));
    }

    return CatalogAcquisitionResult(
      effectiveCatalog: selected.envelope.signedPayload.manifest,
      trustLevel: selected.trustLevel,
      catalogSource: selected.source,
      acquiredAt: nowUtc,
      diagnostics: diagnostics,
    );
  }
}
