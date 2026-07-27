@Tags(['network', 'on-demand'])
@Timeout.none
library;

import 'dart:io';

import 'package:aura_core/aura_offline.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void main() {
  final runOnDemand =
      Platform.environment['AURA_RUN_STAGING_INGESTION_TESTS'] == '1';

  group('Tranche 6.4d — On-Demand Staging Ingestion Integration Test', () {
    test(
        'Ingests, verifies SHA-256 in single-pass and registers Qwen test model in managed store',
        () async {
      if (!runOnDemand) {
        print(
            '[ON-DEMAND TEST SKIPPED] Set AURA_RUN_STAGING_INGESTION_TESTS=1 to run real ingestion integration test.');
        return;
      }

      final allowDestructive =
          Platform.environment['AURA_ALLOW_DESTRUCTIVE_LOCAL_TESTS'] == '1';

      late String appManagedRoot;
      Directory? tempTestDir;

      if (allowDestructive) {
        final localAppData = Platform.environment['LOCALAPPDATA'] ??
            r'C:\Users\dendo\AppData\Local';
        appManagedRoot = '$localAppData\\AURA';
      } else {
        tempTestDir = Directory.systemTemp.createTempSync('AURA-integration-');
        appManagedRoot = tempTestDir.path;
      }

      try {
        final fileSystem = const LocalProvisioningFileSystem();
        final pathResolver = ProvisioningPathResolver(
          appManagedRoot: appManagedRoot,
          bundledRoot: '$appManagedRoot\\bundled',
        );
        final clock = const SystemProvisioningClock();
        final lock = InMemoryProvisioningLock();

        final checkpointRepo = JsonDownloadCheckpointRepository(
          fileSystem: fileSystem,
          pathResolver: pathResolver,
          lock: lock,
        );

        final recordRepo = JsonInstallationRecordRepository(
          fileSystem: fileSystem,
          pathResolver: pathResolver,
          lock: lock,
          clock: clock,
        );

        final activationRepo = JsonActivationStateRepository(
          fileSystem: fileSystem,
          pathResolver: pathResolver,
          lock: lock,
          clock: clock,
        );

        final httpClient = http.Client();
        final downloadEngine = DefaultArtifactDownloadEngine(
          httpClient: httpClient,
          fileSystem: fileSystem,
          pathResolver: pathResolver,
          checkpointRepository: checkpointRepo,
          concurrencyController:
              DownloadConcurrencyController(maxConcurrentDownloads: 1),
          clock: clock,
        );

        final ingestionEngine = SinglePassArtifactIngestionEngine(
          fileSystem: fileSystem,
          pathResolver: pathResolver,
          clock: clock,
        );

        final coordinator = ProvisioningCoordinator(
          lock: lock,
          recordRepository: recordRepo,
          activationRepository: activationRepo,
          ingestionEngine: ArtifactIngestionEngine(
            pathResolver: pathResolver,
            httpClient: HttpProvisioningHttpClient(client: httpClient),
            fileSystem: fileSystem,
          ),
          pathResolver: pathResolver,
          fileSystem: fileSystem,
          clock: clock,
        );

        final importInspector = ArtifactImportInspector(fileSystem: fileSystem);

        final provisioningService = ModelProvisioningService(
          downloadEngine: downloadEngine,
          ingestionEngine: ingestionEngine,
          coordinator: coordinator,
          importInspector: importInspector,
          checkpointRepository: checkpointRepo,
          clock: clock,
        );

        // Modello di test ufficiale Qwen 2.5 0.5B (398 MB)
        final testArtifact = CatalogArtifact(
          artifactId: 'qwen2.5-0.5b-instruct-download-test-q4_0',
          artifactType: CatalogArtifactType.model,
          displayName: 'Qwen 2.5 0.5B Instruct Download Test (Q4_0)',
          version: '2.5.0',
          buildId: 'q4_0-test-v1',
          platform: 'all',
          architecture: 'gguf',
          fileName: 'Qwen2.5-0.5B-Instruct-Q4_0.gguf',
          sourceKind: CatalogArtifactSourceKind.remoteHttps,
          downloadUri:
              'https://huggingface.co/bartowski/Qwen2.5-0.5B-Instruct-GGUF/resolve/41ba88dbac95fed2528c92514c131d73eb5a174b/Qwen2.5-0.5B-Instruct-Q4_0.gguf',
          sizeBytes: 352972352,
          sha256:
              'c8cd5f37dd1235fb010c45316d4ff8af875e1a4e0ff368b4bf6cacb9053d4919',
          license: 'apache-2.0',
        );

        final candidate = ValidatedCatalogCandidate(
          envelope: CatalogEnvelope(
            signedPayload: CatalogSignedPayload(
              schemaVersion: '1.0',
              signatureAlgorithm: 'ed25519-v1',
              keyId: 'aura-catalog-development-2026-01',
              catalogId: 'aura-official-development',
              catalogVersion: '1.0.0',
              catalogRevision: 1,
              issuedAt: '2026-07-27T16:40:48.339506Z',
              expiresAt: '2026-10-25T16:40:48.339506Z',
              manifest: CatalogManifest(
                schemaVersion: '1.0',
                catalogId: 'aura-official-development',
                generatedAt: '2026-07-27T16:40:48.339506Z',
                artifacts: [testArtifact],
              ),
            ),
            signature: 'dummy-test-signature',
          ),
          source: CatalogSource.remoteSigned,
          trustLevel: CatalogTrustLevel.signatureVerified,
          compatibility: const CatalogCompatibilityResult(
            status: CatalogCompatibilityStatus.compatible,
            message: 'OK',
          ),
          canonicalPayloadDigest: 'dummy-digest',
        );

        final request = ProvisioningRequest(
          operationId: 'op-on-demand-test-64d',
          catalogId: 'aura-official-development',
          artifactId: testArtifact.artifactId,
          expectedPlatform: 'all',
          expectedArchitecture: 'gguf',
          downloadPolicy: ProvisioningDownloadPolicy.explicitConsent,
          consent: DownloadConsent.grantedFor(
            artifactId: testArtifact.artifactId,
            sourceUri: testArtifact.downloadUri!,
            expectedSizeBytes: testArtifact.sizeBytes,
            operationId: 'op-on-demand-test-64d',
          ),
        );

        final result = await provisioningService.provisionRemoteModel(
          request: request,
          candidate: candidate,
          artifact: testArtifact,
        );

        expect(result.isSuccess, isTrue);
        expect(result.status, equals(ProvisioningStatus.success));
        expect(result.verified, isTrue);

        final installedPath =
            pathResolver.resolveInstalledArtifactPath(testArtifact);
        expect(await fileSystem.directoryExists(installedPath), isTrue);

        final installedFile = '$installedPath\\${testArtifact.fileName}';
        expect(await fileSystem.fileExists(installedFile), isTrue);

        httpClient.close();
      } finally {
        if (!allowDestructive &&
            tempTestDir != null &&
            tempTestDir.existsSync()) {
          tempTestDir.deleteSync(recursive: true);
        }
      }
    });
  });
}
