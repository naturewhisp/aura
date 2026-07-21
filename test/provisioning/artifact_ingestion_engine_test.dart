import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:aura_core/aura_core.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

final class FakeProvisioningHttpClient implements ProvisioningHttpClient {
  final Map<String, List<int>> remoteFiles = {};

  @override
  Future<int> downloadFile({
    required String uri,
    required String targetPath,
    required int expectedSizeBytes,
    Duration timeout = const Duration(minutes: 5),
  }) async {
    if (!remoteFiles.containsKey(uri)) {
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.downloadFailed,
        message: 'URI remota non trovata nel mock.',
      );
    }
    final bytes = remoteFiles[uri]!;
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
        'Esegue l ingestione completa di un artefatto da remoteHttps con consenso e verifica SHA-256',
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
      );

      final result = await engine.ingestArtifact(
        request: request,
        manifest: manifest,
      );

      expect(result.status, equals(ProvisioningStatus.success));
      expect(result.installed, isTrue);
      expect(result.verified, isTrue);

      final installedFile = File(
        '${tempDir.path}\\app_managed\\runtimes\\llama-b3500\\b3500\\llama-server.exe',
      );
      expect(await installedFile.exists(), isTrue);
      expect(await installedFile.readAsString(), equals(artifactContent));
    });

    test('Rifiuta l ingestione da remoteHttps se manca il consenso al download',
        () async {
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
        operationId: 'op-ingest-2',
        catalogId: 'cat-test-1',
        artifactId: 'llama-b3500',
        downloadPolicy: ProvisioningDownloadPolicy.neverDownload,
        consent: null,
      );

      final result = await engine.ingestArtifact(
        request: request,
        manifest: manifest,
      );

      expect(result.status, equals(ProvisioningStatus.failed));
      expect(result.failureReason,
          equals(ProvisioningFailureReason.downloadNotAllowed));
    });

    test(
        'Rifiuta l ingestione se l hash SHA-256 del file scaricato non corrisponde',
        () async {
      const artifactContent = 'corrupted content';
      final contentBytes = utf8.encode(artifactContent);

      const uri = 'https://downloads.aura.local/corrupt.zip';
      httpClient.remoteFiles[uri] = contentBytes;

      final artifact = CatalogArtifact(
        artifactId: 'llama-b3500',
        artifactType: CatalogArtifactType.runtime,
        displayName: 'llama-server b3500',
        version: 'b3500',
        buildId: 'b3500',
        platform: 'windows',
        architecture: 'x64',
        fileName: 'corrupt.zip',
        license: 'MIT',
        sizeBytes: contentBytes.length,
        sha256: 'f' * 64, // hash deliberatamente errato
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
        expectedSizeBytes: contentBytes.length,
        operationId: 'op-ingest-3',
      );

      final request = ProvisioningRequest(
        operationId: 'op-ingest-3',
        catalogId: 'cat-test-1',
        artifactId: 'llama-b3500',
        downloadPolicy: ProvisioningDownloadPolicy.explicitConsent,
        consent: consent,
      );

      final result = await engine.ingestArtifact(
        request: request,
        manifest: manifest,
      );

      expect(result.status, equals(ProvisioningStatus.failed));
      expect(
          result.failureReason, equals(ProvisioningFailureReason.hashMismatch));
      expect(result.rollbackPerformed, isTrue);
    });
  });
}
