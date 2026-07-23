import 'dart:convert';
import 'dart:typed_data';
import 'package:aura_core/aura_offline.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import '../provisioning_test_helpers.dart';

void main() {
  group('Tranche 6.4b — Catalog Providers, Signed Cache & Refresh Tests', () {
    late MemoryProvisioningFileSystem fileSystem;
    late ProvisioningPathResolver pathResolver;
    late InMemoryProvisioningLock lock;
    late JsonCatalogCacheRepository cacheRepository;
    late CatalogTrustStore trustStore;
    late CatalogCompatibilityEvaluator compatibilityEvaluator;
    late CatalogValidationService validationService;
    late MockCatalogSignatureVerifier signatureVerifier;
    late DefaultValidatedCatalogCandidateFactory candidateFactory;

    late CatalogManifest defaultManifest;
    late DateTime nowUtc;
    const String appVersion = '1.0.0';

    setUp(() {
      fileSystem = MemoryProvisioningFileSystem();
      pathResolver = ProvisioningPathResolver(
        appManagedRoot: r'C:\AURA\app_managed',
        bundledRoot: r'C:\AURA\bundled',
      );
      lock = InMemoryProvisioningLock();
      cacheRepository = JsonCatalogCacheRepository(
        pathResolver: pathResolver,
        lock: lock,
        fileSystem: fileSystem,
      );
      trustStore = InMemoryCatalogTrustStore.fromKeys([
        CatalogPublicKey(
          keyId: 'aura-release-key-2026-01',
          algorithm: 'ed25519-v1',
          rawKeyBytes: Uint8List(32),
        ),
      ]);
      compatibilityEvaluator = const DefaultCatalogCompatibilityEvaluator();
      validationService = CatalogValidationService();
      signatureVerifier = const MockCatalogSignatureVerifier();
      candidateFactory = const DefaultValidatedCatalogCandidateFactory();

      defaultManifest = CatalogManifest.initialDefault();
      nowUtc = DateTime.parse('2026-07-23T12:00:00Z');
    });

    CatalogEnvelope createTestEnvelope({
      int catalogRevision = 1,
      String? expiresAt,
      String catalogId = 'aura-official-catalog',
    }) {
      final signedPayload = CatalogSignedPayload(
        schemaVersion: '1.0',
        signatureAlgorithm: 'ed25519-v1',
        keyId: 'aura-release-key-2026-01',
        catalogId: catalogId,
        catalogVersion: '1.0.0',
        catalogRevision: catalogRevision,
        issuedAt: '2026-07-22T00:00:00Z',
        expiresAt: expiresAt ?? '2026-08-22T00:00:00Z',
        manifest: defaultManifest,
      );
      final dummySig = base64.encode(Uint8List(64));
      return CatalogEnvelope(
        signedPayload: signedPayload,
        signature: dummySig,
      );
    }

    group('CatalogRefreshPolicy Tests', () {
      test('Accetta candidato remoto qualificato se non vi e alcuna cache',
          () async {
        final remoteEnvelope = createTestEnvelope(catalogRevision: 10);
        final remoteRes = await candidateFactory.createCandidate(
          envelope: remoteEnvelope,
          source: CatalogSource.remoteSigned,
          trustStore: trustStore,
          compatibilityEvaluator: compatibilityEvaluator,
          validationService: validationService,
          signatureVerifier: signatureVerifier,
          nowUtc: nowUtc,
          applicationVersion: appVersion,
        );

        final eval = CatalogRefreshPolicy.evaluateRemoteRefresh(
          remoteCandidate: remoteRes.candidate!,
          cachedCandidate: null,
          nowUtc: nowUtc,
          applicationVersion: appVersion,
        );

        expect(eval.isQualified, isTrue);
      });

      test(
          'Rifiuta candidato remoto se il catalogRevision e inferiore a quello in cache (anti-downgrade)',
          () async {
        final cachedRes = await candidateFactory.createCandidate(
          envelope: createTestEnvelope(catalogRevision: 20),
          source: CatalogSource.cachedSigned,
          trustStore: trustStore,
          compatibilityEvaluator: compatibilityEvaluator,
          validationService: validationService,
          signatureVerifier: signatureVerifier,
          nowUtc: nowUtc,
          applicationVersion: appVersion,
        );

        final remoteRes = await candidateFactory.createCandidate(
          envelope: createTestEnvelope(catalogRevision: 15),
          source: CatalogSource.remoteSigned,
          trustStore: trustStore,
          compatibilityEvaluator: compatibilityEvaluator,
          validationService: validationService,
          signatureVerifier: signatureVerifier,
          nowUtc: nowUtc,
          applicationVersion: appVersion,
        );

        final eval = CatalogRefreshPolicy.evaluateRemoteRefresh(
          remoteCandidate: remoteRes.candidate!,
          cachedCandidate: cachedRes.candidate!,
          nowUtc: nowUtc,
          applicationVersion: appVersion,
        );

        expect(eval.isQualified, isFalse);
        expect(eval.rejectionReason,
            equals(CatalogAcquisitionFailureReason.catalogRevisionDowngrade));
      });

      test(
          'Rifiuta candidato remoto con catalogId discordante (namespace mismatch)',
          () async {
        final cachedRes = await candidateFactory.createCandidate(
          envelope: createTestEnvelope(
              catalogRevision: 10, catalogId: 'aura-official-catalog'),
          source: CatalogSource.cachedSigned,
          trustStore: trustStore,
          compatibilityEvaluator: compatibilityEvaluator,
          validationService: validationService,
          signatureVerifier: signatureVerifier,
          nowUtc: nowUtc,
          applicationVersion: appVersion,
        );

        final remoteRes = await candidateFactory.createCandidate(
          envelope: createTestEnvelope(
              catalogRevision: 15, catalogId: 'aura-other-catalog'),
          source: CatalogSource.remoteSigned,
          trustStore: trustStore,
          compatibilityEvaluator: compatibilityEvaluator,
          validationService: validationService,
          signatureVerifier: signatureVerifier,
          nowUtc: nowUtc,
          applicationVersion: appVersion,
        );

        final eval = CatalogRefreshPolicy.evaluateRemoteRefresh(
          remoteCandidate: remoteRes.candidate!,
          cachedCandidate: cachedRes.candidate!,
          nowUtc: nowUtc,
          applicationVersion: appVersion,
        );

        expect(eval.isQualified, isFalse);
        expect(eval.rejectionReason,
            equals(CatalogAcquisitionFailureReason.catalogIdentityMismatch));
      });

      test(
          'Rifiuta catalogo remoto scaduto oltre il margine di clock skew (300s)',
          () async {
        final expiredEnvelope = createTestEnvelope(
          catalogRevision: 10,
          expiresAt:
              '2026-07-23T11:50:00Z', // 10 minuti prima di nowUtc (12:00)
        );

        final remoteRes = await candidateFactory.createCandidate(
          envelope: expiredEnvelope,
          source: CatalogSource.remoteSigned,
          trustStore: trustStore,
          compatibilityEvaluator: compatibilityEvaluator,
          validationService: validationService,
          signatureVerifier: signatureVerifier,
          nowUtc: nowUtc,
          applicationVersion: appVersion,
        );

        expect(remoteRes.isSuccess, isFalse);
        expect(remoteRes.failureReason,
            equals(CatalogAcquisitionFailureReason.catalogExpired));
      });
    });

    group('Catalog Providers Tests', () {
      test(
          'BundledCatalogProvider genera sempre un candidato valido con sorgente bundledBootstrap',
          () async {
        final provider = BundledCatalogProvider(manifest: defaultManifest);
        final context = CatalogProviderContext(
          trustStore: trustStore,
          compatibilityEvaluator: compatibilityEvaluator,
          validationService: validationService,
          signatureVerifier: signatureVerifier,
          candidateFactory: candidateFactory,
          nowUtc: nowUtc,
          applicationVersion: appVersion,
        );

        final result = await provider.getCandidate(context);
        expect(result.isSuccess, isTrue);
        expect(
            result.candidate!.source, equals(CatalogSource.bundledBootstrap));
        expect(result.candidate!.trustLevel,
            equals(CatalogTrustLevel.bootstrapDeclared));
      });

      test(
          'CachedCatalogProvider restituisce absent se la cache non e presente, success se e valida',
          () async {
        final provider = CachedCatalogProvider(repository: cacheRepository);
        final context = CatalogProviderContext(
          trustStore: trustStore,
          compatibilityEvaluator: compatibilityEvaluator,
          validationService: validationService,
          signatureVerifier: signatureVerifier,
          candidateFactory: candidateFactory,
          nowUtc: nowUtc,
          applicationVersion: appVersion,
        );

        var result = await provider.getCandidate(context);
        expect(result.isAbsent, isTrue);

        // Scrive envelope in cache
        final env = createTestEnvelope(catalogRevision: 5);
        await cacheRepository.writeEnvelope(env);

        result = await provider.getCandidate(context);
        expect(result.isSuccess, isTrue);
        expect(result.candidate!.source, equals(CatalogSource.cachedSigned));
        expect(result.candidate!.envelope.signedPayload.catalogRevision,
            equals(5));
      });

      test(
          'RemoteCatalogProvider recupera e convalida envelope remota via HTTP 200',
          () async {
        final validEnvelope = createTestEnvelope(catalogRevision: 30);
        final jsonText = jsonEncode(validEnvelope.toJson());

        final mockClient = MockClient((request) async {
          if (request.url.toString() ==
              'https://catalog.aura-arena.org/v1/manifest.json') {
            return http.Response(jsonText, 200,
                headers: {'content-type': 'application/json'});
          }
          return http.Response('Not Found', 404);
        });

        final provider = RemoteCatalogProvider(
          catalogUrl: 'https://catalog.aura-arena.org/v1/manifest.json',
          httpClient: mockClient,
        );

        final context = CatalogProviderContext(
          trustStore: trustStore,
          compatibilityEvaluator: compatibilityEvaluator,
          validationService: validationService,
          signatureVerifier: signatureVerifier,
          candidateFactory: candidateFactory,
          nowUtc: nowUtc,
          applicationVersion: appVersion,
        );

        final result = await provider.getCandidate(context);
        expect(result.isSuccess, isTrue);
        expect(result.candidate!.source, equals(CatalogSource.remoteSigned));
        expect(result.candidate!.envelope.signedPayload.catalogRevision,
            equals(30));
      });

      test(
          'RemoteCatalogProvider gestisce risposte HTTP di errore senza sollevare eccezioni non gestite',
          () async {
        final mockClient = MockClient((request) async {
          return http.Response('Internal Server Error', 500);
        });

        final provider = RemoteCatalogProvider(
          catalogUrl: 'https://catalog.aura-arena.org/v1/manifest.json',
          httpClient: mockClient,
        );

        final context = CatalogProviderContext(
          trustStore: trustStore,
          compatibilityEvaluator: compatibilityEvaluator,
          validationService: validationService,
          signatureVerifier: signatureVerifier,
          candidateFactory: candidateFactory,
          nowUtc: nowUtc,
          applicationVersion: appVersion,
        );

        final result = await provider.getCandidate(context);
        expect(result.isFailure, isTrue);
        expect(result.failureReason,
            equals(CatalogAcquisitionFailureReason.remoteFetchFailed));
      });
    });

    group('CatalogRefreshService End-to-End Tests', () {
      test(
          'refreshCatalog in modalita offlineOnly usa il candidato bootstrap o cached senza contattare il server remoto',
          () async {
        final bundledProvider =
            BundledCatalogProvider(manifest: defaultManifest);
        final cachedProvider =
            CachedCatalogProvider(repository: cacheRepository);

        final service = CatalogRefreshService(
          cacheRepository: cacheRepository,
          trustStore: trustStore,
          compatibilityEvaluator: compatibilityEvaluator,
          validationService: validationService,
          signatureVerifier: signatureVerifier,
          candidateFactory: candidateFactory,
          bundledProvider: bundledProvider,
          cachedProvider: cachedProvider,
          remoteProvider: null,
          clock: MemoryProvisioningClock(nowUtc),
          applicationVersion: appVersion,
        );

        final acquisition = await service.refreshCatalog(
          const CatalogRefreshRequest(offlineOnly: true),
        );

        expect(
            acquisition.catalogSource, equals(CatalogSource.bundledBootstrap));
        expect(acquisition.trustLevel,
            equals(CatalogTrustLevel.bootstrapDeclared));
        expect(acquisition.effectiveCatalog.catalogId,
            equals(defaultManifest.catalogId));
      });

      test(
          'refreshCatalog in modalita online aggiorna la cache e seleziona il catalogo remoto con revisione superiore',
          () async {
        // Scrive un vecchio catalogo in cache (rev 5)
        await cacheRepository
            .writeEnvelope(createTestEnvelope(catalogRevision: 5));

        // Remoto restituisce una nuova revisione valida (rev 50)
        final remoteEnvelope = createTestEnvelope(catalogRevision: 50);
        final mockClient = MockClient((request) async {
          return http.Response(jsonEncode(remoteEnvelope.toJson()), 200);
        });

        final bundledProvider =
            BundledCatalogProvider(manifest: defaultManifest);
        final cachedProvider =
            CachedCatalogProvider(repository: cacheRepository);
        final remoteProvider = RemoteCatalogProvider(
          catalogUrl: 'https://catalog.aura-arena.org/v1/manifest.json',
          httpClient: mockClient,
        );

        final service = CatalogRefreshService(
          cacheRepository: cacheRepository,
          trustStore: trustStore,
          compatibilityEvaluator: compatibilityEvaluator,
          validationService: validationService,
          signatureVerifier: signatureVerifier,
          candidateFactory: candidateFactory,
          bundledProvider: bundledProvider,
          cachedProvider: cachedProvider,
          remoteProvider: remoteProvider,
          clock: MemoryProvisioningClock(nowUtc),
          applicationVersion: appVersion,
        );

        final acquisition = await service.refreshCatalog(
          const CatalogRefreshRequest(offlineOnly: false),
        );

        expect(acquisition.catalogSource, equals(CatalogSource.remoteSigned));
        expect(acquisition.trustLevel,
            equals(CatalogTrustLevel.signatureVerified));
        expect(acquisition.diagnostics['selectedCatalogRevision'], equals(50));

        // Verifica che l'envelope sia stata scritta atomicamente nella cache locale
        final updatedCache = await cacheRepository.readEnvelope();
        expect(updatedCache, isNotNull);
        expect(updatedCache!.signedPayload.catalogRevision, equals(50));
      });

      test(
          'refreshCatalog rifiuta il remoto se tenta un downgrade e mantiene il catalogo in cache',
          () async {
        // Cache locale possiede la revisione 100
        await cacheRepository
            .writeEnvelope(createTestEnvelope(catalogRevision: 100));

        // Remoto restituisce una revisione inferiore (rev 10)
        final mockClient = MockClient((request) async {
          return http.Response(
              jsonEncode(createTestEnvelope(catalogRevision: 10).toJson()),
              200);
        });

        final service = CatalogRefreshService(
          cacheRepository: cacheRepository,
          trustStore: trustStore,
          compatibilityEvaluator: compatibilityEvaluator,
          validationService: validationService,
          signatureVerifier: signatureVerifier,
          candidateFactory: candidateFactory,
          bundledProvider: BundledCatalogProvider(manifest: defaultManifest),
          cachedProvider: CachedCatalogProvider(repository: cacheRepository),
          remoteProvider: RemoteCatalogProvider(
            catalogUrl: 'https://catalog.aura-arena.org/v1/manifest.json',
            httpClient: mockClient,
          ),
          clock: MemoryProvisioningClock(nowUtc),
          applicationVersion: appVersion,
        );

        final acquisition = await service.refreshCatalog(
          const CatalogRefreshRequest(offlineOnly: false),
        );

        // Il catalogo effettivo selezionato rimane la cache locale (rev 100)
        expect(acquisition.catalogSource, equals(CatalogSource.cachedSigned));
        expect(acquisition.diagnostics['selectedCatalogRevision'], equals(100));
        expect(acquisition.diagnostics['remoteQualified'], isFalse);
        expect(acquisition.diagnostics['remoteRejectionReason'],
            equals('catalogRevisionDowngrade'));

        // La cache rimane inalterata a rev 100
        final cacheEnvelope = await cacheRepository.readEnvelope();
        expect(cacheEnvelope!.signedPayload.catalogRevision, equals(100));
      });
    });
  });
}
