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
    late JsonLkgCatalogMetadataRepository lkgRepository;
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
      lkgRepository = JsonLkgCatalogMetadataRepository(
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
        );

        expect(eval.isQualified, isFalse);
        expect(eval.rejectionReason,
            equals(CatalogAcquisitionFailureReason.catalogRevisionDowngrade));
      });

      test(
          'Rifiuta candidato remoto se inferiore a LKG metadata anche in assenza di cache (anti-downgrade LKG per-namespace)',
          () async {
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

        final lkg = LkgCatalogMetadata(
          catalogId: 'aura-official-catalog',
          highestAcceptedRevision: 25,
          canonicalPayloadDigest: 'abc123digest',
          acceptedAtUtc: nowUtc,
        );

        final eval = CatalogRefreshPolicy.evaluateRemoteRefresh(
          remoteCandidate: remoteRes.candidate!,
          cachedCandidate: null,
          lkgMetadata: lkg,
          nowUtc: nowUtc,
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
          'RemoteCatalogProvider recupera e convalida envelope remota via HTTP 200 ed estrae ETag e sourceUri',
          () async {
        final validEnvelope = createTestEnvelope(catalogRevision: 30);
        final jsonText = jsonEncode(validEnvelope.toJson());

        final mockClient = MockClient((request) async {
          if (request.url.toString() ==
              'https://catalog.aura-arena.org/v1/manifest.json') {
            return http.Response(jsonText, 200, headers: {
              'content-type': 'application/json',
              'etag': '"v30-hash"'
            });
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
        expect(result.responseEtag, equals('"v30-hash"'));
        expect(
            result.sourceUri,
            equals(
                Uri.parse('https://catalog.aura-arena.org/v1/manifest.json')));
        expect(result.candidate!.source, equals(CatalogSource.remoteSigned));
        expect(result.candidate!.envelope.signedPayload.catalogRevision,
            equals(30));
      });

      test(
          'RemoteCatalogProvider invia If-None-Match e gestisce HTTP 304 Not Modified',
          () async {
        String? receivedIfNoneMatch;

        final mockClient = MockClient((request) async {
          receivedIfNoneMatch = request.headers['If-None-Match'];
          return http.Response('', 304);
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
          cachedEtag: '"v30-hash"',
          forceRefresh: false,
        );

        final result = await provider.getCandidate(context);
        expect(result.isNotModified, isTrue);
        expect(receivedIfNoneMatch, equals('"v30-hash"'));
      });
    });

    group('CatalogRefreshService End-to-End Tests', () {
      test(
          'refreshCatalog omette If-None-Match quando la cache non produce un candidato valido',
          () async {
        String? receivedIfNoneMatch;
        final remoteEnvelope = createTestEnvelope(catalogRevision: 50);

        final mockClient = MockClient((request) async {
          receivedIfNoneMatch = request.headers['If-None-Match'];
          return http.Response(jsonEncode(remoteEnvelope.toJson()), 200);
        });

        // Scrive un record di cache con ETag ma envelope corrotta (non validabile)
        await fileSystem.createDirectory(pathResolver.cacheDirectory);
        await fileSystem.writeStringRecoverably(
          pathResolver.catalogCacheEnvelopePath,
          jsonEncode({
            'envelope': {
              'signed_payload': {'invalid': true},
              'signature': 'bad'
            },
            'etag': '"corrupted-etag"',
            'fetched_at': '2026-07-23T10:00:00Z'
          }),
        );

        final service = CatalogRefreshService(
          cacheRepository: cacheRepository,
          lkgRepository: lkgRepository,
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

        expect(receivedIfNoneMatch, isNull);
        expect(acquisition.catalogSource, equals(CatalogSource.remoteSigned));
        expect(acquisition.diagnostics['selectedCatalogRevision'], equals(50));
      });

      test(
          'refreshCatalog gestisce LKG per-namespace isolando catalogId differenti',
          () async {
        // Salva un LKG per 'aura-official-catalog' a rev 100
        await lkgRepository.writeMetadata(LkgCatalogMetadata(
          catalogId: 'aura-official-catalog',
          highestAcceptedRevision: 100,
          canonicalPayloadDigest: 'digest1',
          acceptedAtUtc: nowUtc,
        ));

        // Remoto restituisce un catalogo di un DIVERSO namespace 'aura-enterprise-catalog' a rev 4
        final remoteEnvelope = createTestEnvelope(
          catalogRevision: 4,
          catalogId: 'aura-enterprise-catalog',
        );
        final mockClient = MockClient((request) async {
          return http.Response(jsonEncode(remoteEnvelope.toJson()), 200);
        });

        final service = CatalogRefreshService(
          cacheRepository: cacheRepository,
          lkgRepository: lkgRepository,
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
          const CatalogRefreshRequest(
            offlineOnly: false,
            targetCatalogId: 'aura-enterprise-catalog',
          ),
        );

        // 'aura-enterprise-catalog' rev 4 non viene influenzato dall'LKG di 'aura-official-catalog' rev 100
        expect(acquisition.catalogSource, equals(CatalogSource.remoteSigned));
        expect(acquisition.diagnostics['selectedCatalogId'],
            equals('aura-enterprise-catalog'));
        expect(acquisition.diagnostics['selectedCatalogRevision'], equals(4));

        // Entrambi gli LKG rimangono memorizzati separatamente nel repository per-namespace
        final lkgOfficial = await lkgRepository.readMetadata(
            catalogId: 'aura-official-catalog');
        final lkgEnterprise = await lkgRepository.readMetadata(
            catalogId: 'aura-enterprise-catalog');

        expect(lkgOfficial!.highestAcceptedRevision, equals(100));
        expect(lkgEnterprise!.highestAcceptedRevision, equals(4));
      });
    });
  });
}
