import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:aura_core/aura_core.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

final class FakeProvisioningHttpClient implements ProvisioningHttpClient {
  final Map<String, List<int>> remoteFiles = {};

  @override
  Future<void> close() async {}

  @override
  Future<int> downloadFile({
    required String uri,
    required String targetPath,
    required int expectedSizeBytes,
    ProvisioningCancellationToken? cancellationToken,
    RedirectHostPolicy redirectHostPolicy = RedirectHostPolicy.sameHostOnly,
    Set<String> allowedRedirectHosts = const {},
    Duration timeout = const Duration(minutes: 5),
  }) async {
    cancellationToken?.throwIfCancelled();

    if (!remoteFiles.containsKey(uri)) {
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.downloadFailed,
        message: 'URI remota non trovata nel mock.',
      );
    }
    final bytes = remoteFiles[uri]!;

    if (bytes.length != expectedSizeBytes) {
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.sizeMismatch,
        message: 'Dimensione non corrispondente.',
      );
    }

    final file = File(targetPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
    return bytes.length;
  }
}

void main() {
  group('ArtifactIngestionEngine Tests -', () {
    late Directory tempDir;
    late ProvisioningPathResolver pathResolver;
    late FakeProvisioningHttpClient httpClient;
    late ArtifactIngestionEngine engine;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('aura_ingest_test_');
      pathResolver = ProvisioningPathResolver(
        appManagedRoot: '${tempDir.path}\\app_managed',
        bundledRoot: '${tempDir.path}\\bundled',
      );
      httpClient = FakeProvisioningHttpClient();
      engine = ArtifactIngestionEngine(
        pathResolver: pathResolver,
        httpClient: httpClient,
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
        'Esegue l ingestione completa di un artefatto da remoteHttps con consenso e pulisce lo staging',
        () async {
      const artifactContent = 'llama-server binary simulated content';
      final contentBytes = utf8.encode(artifactContent);

      final archive = Archive()
        ..addFile(
            ArchiveFile('llama-server.exe', contentBytes.length, contentBytes));
      final zipBytes = ZipEncoder().encode(archive)!;

      const uri = 'https://downloads.aura.local/llama-server-b3500.zip';
      httpClient.remoteFiles[uri] = zipBytes;

      final expectedHash = sha256.convert(zipBytes).toString().toLowerCase();

      final artifact = CatalogArtifact(
        artifactId: 'llama-b3500',
        artifactType: CatalogArtifactType.runtime,
        displayName: 'llama-server b3500',
        version: 'b3500',
        buildId: 'b3500',
        platform: 'windows',
        architecture: 'x64',
        fileName: 'llama-server-b3500.zip',
        license: 'MIT',
        sizeBytes: zipBytes.length,
        sha256: expectedHash,
        compression: CatalogCompressionFormat.zip,
        sourceKind: CatalogArtifactSourceKind.remoteHttps,
        downloadUri: uri,
      );

      final manifest = CatalogManifest(
        schemaVersion: '1.0',
        catalogId: 'cat-test-1',
        generatedAt: '2026-07-21T21:00:00.000Z',
        artifacts: [artifact],
      );

      final consent = DownloadConsent.grantedFor(
        artifactId: 'llama-b3500',
        sourceUri: uri,
        expectedSizeBytes: zipBytes.length,
        operationId: 'op-ingest-1',
      );

      final request = ProvisioningRequest(
        operationId: 'op-ingest-1',
        catalogId: 'cat-test-1',
        artifactId: 'llama-b3500',
        downloadPolicy: ProvisioningDownloadPolicy.explicitConsent,
        consent: consent,
        expectedPlatform: 'windows',
        expectedArchitecture: 'x64',
      );

      final result = await engine.ingestArtifact(
        request: request,
        manifest: manifest,
      );

      expect(result.status, equals(ProvisioningStatus.success));
      expect(result.installed, isTrue);
      expect(result.verified, isTrue);
      expect(result.installationId, isNull);
      expect(result.cleanupSucceeded, isTrue);

      final installedFile = File(
        '${tempDir.path}\\app_managed\\runtimes\\llama-b3500\\b3500\\llama-server.exe',
      );
      expect(await installedFile.exists(), isTrue);

      final stagingDir =
          Directory('${tempDir.path}\\app_managed\\staging\\op-ingest-1');
      expect(await stagingDir.exists(), isFalse);
    });

    test(
        'Rifiuta l ingestione se la piattaforma o l architettura non corrispondono',
        () async {
      final artifact = CatalogArtifact(
        artifactId: 'llama-b3500',
        artifactType: CatalogArtifactType.runtime,
        displayName: 'llama-server b3500',
        version: 'b3500',
        buildId: 'b3500',
        platform: 'linux',
        architecture: 'arm64',
        fileName: 'llama-server.exe',
        license: 'MIT',
        sizeBytes: 100,
        sha256: 'a' * 64,
        sourceKind: CatalogArtifactSourceKind.remoteHttps,
        downloadUri: 'https://downloads.aura.local/llama.zip',
      );

      final manifest = CatalogManifest(
        schemaVersion: '1.0',
        catalogId: 'cat-test-1',
        generatedAt: '2026-07-21T21:00:00.000Z',
        artifacts: [artifact],
      );

      final request = ProvisioningRequest(
        operationId: 'op-mismatch-1',
        catalogId: 'cat-test-1',
        artifactId: 'llama-b3500',
        expectedPlatform: 'windows',
        expectedArchitecture: 'x64',
      );

      final result = await engine.ingestArtifact(
        request: request,
        manifest: manifest,
      );

      expect(result.status, equals(ProvisioningStatus.failed));
      expect(result.failureReason,
          equals(ProvisioningFailureReason.unsupportedPlatform));
    });

    test(
        'Supporta l annullamento coordinato tramite ProvisioningCancellationToken',
        () async {
      final token = DefaultProvisioningCancellationToken();
      token.cancel();

      final artifact = CatalogArtifact(
        artifactId: 'llama-b3500',
        artifactType: CatalogArtifactType.runtime,
        displayName: 'llama-server b3500',
        version: 'b3500',
        buildId: 'b3500',
        platform: 'windows',
        architecture: 'x64',
        fileName: 'llama-server.exe',
        license: 'MIT',
        sizeBytes: 100,
        sha256: 'a' * 64,
        sourceKind: CatalogArtifactSourceKind.remoteHttps,
        downloadUri: 'https://downloads.aura.local/llama.zip',
      );

      final manifest = CatalogManifest(
        schemaVersion: '1.0',
        catalogId: 'cat-test-1',
        generatedAt: '2026-07-21T21:00:00.000Z',
        artifacts: [artifact],
      );

      final consent = DownloadConsent.grantedFor(
        artifactId: 'llama-b3500',
        sourceUri: 'https://downloads.aura.local/llama.zip',
        expectedSizeBytes: 100,
        operationId: 'op-cancel-1',
      );

      final request = ProvisioningRequest(
        operationId: 'op-cancel-1',
        catalogId: 'cat-test-1',
        artifactId: 'llama-b3500',
        downloadPolicy: ProvisioningDownloadPolicy.explicitConsent,
        consent: consent,
        expectedPlatform: 'windows',
        expectedArchitecture: 'x64',
      );

      final result = await engine.ingestArtifact(
        request: request,
        manifest: manifest,
        cancellationToken: token,
      );

      expect(result.status, equals(ProvisioningStatus.failed));
      expect(result.failureReason,
          equals(ProvisioningFailureReason.operationCancelled));
    });
  });
}
