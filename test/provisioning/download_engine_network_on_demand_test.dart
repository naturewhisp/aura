@Tags(['network', 'on-demand'])
@Timeout.none
library;

import 'dart:convert';
import 'dart:io';
import 'package:aura_core/aura_offline.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void main() {
  final isNetworkTestsEnabled =
      Platform.environment['AURA_RUN_NETWORK_TESTS'] == '1';

  group(
      'Tranche 6.4c — On-Demand Network Download Test (qwen2.5-0.5b-instruct-download-test-q4_0)',
      () {
    test(
        'Downloads real technical test artifact from Hugging Face official development catalog',
        timeout: Timeout.none, () async {
      if (!isNetworkTestsEnabled) {
        print(
            'INFO: Test di rete on-demand saltato perche AURA_RUN_NETWORK_TESTS != 1.');
        return;
      }

      // Legge l'envelope del catalogo di sviluppo compilato
      final catalogFile =
          File('build/catalog/aura-official-development.catalog.json');
      expect(await catalogFile.exists(), isTrue,
          reason: 'Il catalogo di sviluppo deve essere compilato.');

      final catalogJson =
          jsonDecode(await catalogFile.readAsString()) as Map<String, dynamic>;
      final envelope = CatalogEnvelope.fromJson(catalogJson);
      final manifest = envelope.signedPayload.manifest;

      // Trova il modello di test leggero
      final techTestArtifact = manifest.artifacts.firstWhere(
        (a) => a.artifactId == 'qwen2.5-0.5b-instruct-download-test-q4_0',
      );

      final tempDir = Directory(
          '${Directory.systemTemp.path}\\aura_network_test_on_demand');
      if (!await tempDir.exists()) {
        await tempDir.create(recursive: true);
      }
      final pathResolver = ProvisioningPathResolver(
        appManagedRoot: '${tempDir.path}\\app_managed',
        bundledRoot: '${tempDir.path}\\bundled',
      );

      final fileSystem = const LocalProvisioningFileSystem();
      final lock = InMemoryProvisioningLock();
      final checkpointRepository = JsonDownloadCheckpointRepository(
        pathResolver: pathResolver,
        lock: lock,
        fileSystem: fileSystem,
      );
      final concurrencyController =
          DownloadConcurrencyController(maxConcurrentDownloads: 1);

      final client = http.Client();
      try {
        final engine = DefaultArtifactDownloadEngine(
          httpClient: client,
          fileSystem: fileSystem,
          pathResolver: pathResolver,
          checkpointRepository: checkpointRepository,
          concurrencyController: concurrencyController,
        );

        final req = DownloadRequest(
          operationId: 'op-tech-test-download',
          artifactId: techTestArtifact.artifactId,
          sourceUri: Uri.parse(techTestArtifact.downloadUri!),
          expectedSizeBytes: techTestArtifact.sizeBytes,
        );

        final result = await engine.downloadArtifact(request: req);

        expect(result.isSuccess, isTrue);
        expect(result.stagingArtifact, isNotNull);
        expect(result.stagingArtifact!.sizeBytes,
            equals(techTestArtifact.sizeBytes));
        expect(result.stagingArtifact!.downloadComplete, isTrue);
        expect(result.stagingArtifact!.cryptographicallyVerified, isFalse);

        final stagedFile = File(result.stagingArtifact!.stagingPath);
        expect(await stagedFile.exists(), isTrue);
        expect(await stagedFile.length(), equals(techTestArtifact.sizeBytes));
      } finally {
        client.close();
        await tempDir.delete(recursive: true);
      }
    });
  });
}
