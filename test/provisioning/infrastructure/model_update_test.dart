import 'package:test/test.dart';
import 'package:aura_core/aura_offline.dart';

import '../provisioning_test_helpers.dart';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('Phase 6.4e — Model Update Infrastructure Tests', () {
    late MemoryProvisioningFileSystem fileSystem;
    late ProvisioningPathResolver pathResolver;
    late MemoryProvisioningClock clock;
    late InMemoryProvisioningLock lock;
    late JsonInstallationRecordRepository recordRepository;
    late JsonActivationStateRepository activationRepository;
    late ProvisioningCoordinator coordinator;
    late ModelProvisioningService provisioningService;

    final baseTime = DateTime.parse('2026-07-28T10:00:00Z');

    setUp(() async {
      fileSystem = MemoryProvisioningFileSystem();
      pathResolver = ProvisioningPathResolver(
        appManagedRoot: r'C:\AURA\app_managed',
        bundledRoot: r'C:\AURA\bundled',
      );
      clock = MemoryProvisioningClock(baseTime);
      lock = InMemoryProvisioningLock();

      recordRepository = JsonInstallationRecordRepository(
        fileSystem: fileSystem,
        pathResolver: pathResolver,
        lock: lock,
        clock: clock,
      );
      activationRepository = JsonActivationStateRepository(
        fileSystem: fileSystem,
        pathResolver: pathResolver,
        lock: lock,
        clock: clock,
      );

      final verifier = LocalInstalledArtifactVerifier(fileSystem: fileSystem);
      final mockClient = MockClient((_) async => http.Response('', 200));

      final checkpointRepository = JsonDownloadCheckpointRepository(
        fileSystem: fileSystem,
        pathResolver: pathResolver,
        lock: lock,
      );

      final downloadEngine = DefaultArtifactDownloadEngine(
        pathResolver: pathResolver,
        httpClient: mockClient,
        fileSystem: fileSystem,
        checkpointRepository: checkpointRepository,
        concurrencyController: DownloadConcurrencyController(),
        clock: clock,
      );

      coordinator = ProvisioningCoordinator(
        lock: lock,
        recordRepository: recordRepository,
        activationRepository: activationRepository,
        pathResolver: pathResolver,
        fileSystem: fileSystem,
        verifier: verifier,
        ingestionEngine: ArtifactIngestionEngine(
          pathResolver: pathResolver,
          httpClient: HttpProvisioningHttpClient(client: mockClient),
          fileSystem: fileSystem,
        ),
        clock: clock,
      );

      final env = ProvisioningEnvironment(
        downloadEngine: downloadEngine,
        coordinator: coordinator,
        fileSystem: fileSystem,
        pathResolver: pathResolver,
        checkpointRepository: checkpointRepository,
        clock: clock,
      );

      provisioningService = ModelProvisioningService(environment: env);
    });

    test(
        'updateModel restituisce alreadyLatest se l\'installazione esistente è già la più recente',
        () async {
      final initialDesc = InstalledArtifactDescriptor(
        installationId: 'inst_v2',
        artifactId: 'actor-mod',
        artifactType: CatalogArtifactType.model,
        displayName: 'Actor Model',
        platform: 'any',
        architecture: 'any',
        sourceKind: CatalogArtifactSourceKind.remoteHttps,
        version: '2.0.0',
        buildId: 'b2',
        sizeBytes: 100,
        sha256: 'abc',
        relativeInstallPath: r'models\actor-mod\2.0.0-b2',
        installedAt: '2026-07-28T10:00:00Z',
        status: InstallationStatus.verified,
        verifiedAt: '2026-07-28T10:00:00Z',
      );

      var record = InstallationRecord.empty(updatedAt: '2026-07-28T10:00:00Z');
      record = record.upsertArtifact(initialDesc);
      await recordRepository.writeRecord(record);

      final candidateArtifact = CatalogArtifact(
        artifactId: 'actor-mod',
        artifactType: CatalogArtifactType.model,
        displayName: 'Actor Model',
        version: '1.9.0',
        buildId: 'b1',
        platform: 'any',
        architecture: 'any',
        fileName: 'model.gguf',
        sourceKind: CatalogArtifactSourceKind.remoteHttps,
        downloadUri: 'https://example.com/model.gguf',
        sizeBytes: 100,
        sha256: 'abc',
        license: 'MIT',
      );

      final manifest = CatalogManifest(
        schemaVersion: '1.0',
        catalogId: 'cat_1',
        generatedAt: '2026-07-28T10:00:00Z',
        artifacts: [candidateArtifact],
      );

      final candidate = ValidatedCatalogCandidate(
        envelope: CatalogEnvelope(
          signedPayload: CatalogSignedPayload(
            schemaVersion: '1.0',
            signatureAlgorithm: 'Ed25519',
            keyId: 'key1',
            catalogId: 'cat_1',
            catalogVersion: '1.0',
            catalogRevision: 1,
            issuedAt: '2026-07-28T10:00:00Z',
            expiresAt: '2026-08-28T10:00:00Z',
            manifest: manifest,
          ),
          signature: 'abc',
        ),
        source: CatalogSource.remoteSigned,
        trustLevel: CatalogTrustLevel.signatureVerified,
        compatibility: const CatalogCompatibilityResult(
          status: CatalogCompatibilityStatus.compatible,
        ),
        canonicalPayloadDigest: 'abc',
      );

      final updateReq = UpdateModelRequest(
        operationId: 'op_update_1',
        artifactId: 'actor-mod',
        candidate: candidate,
      );

      final res = await provisioningService.updateModel(request: updateReq);

      expect(res.status, equals(ModelUpdateStatus.alreadyLatest));
    });
  });
}
