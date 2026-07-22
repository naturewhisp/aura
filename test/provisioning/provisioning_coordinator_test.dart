import 'dart:async';
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

/// Helper repository per simularne il fallimento in fase di aggiornamento transazionale.
final class FaultyInstallationRecordRepository
    implements InstallationRecordRepository {
  final JsonInstallationRecordRepository _inner;
  bool failOnUpdate = false;

  FaultyInstallationRecordRepository(this._inner);

  @override
  Future<InstallationRecord> readRecord() => _inner.readRecord();

  @override
  Future<InstallationRecord> replaceRecord(InstallationRecord record) =>
      _inner.replaceRecord(record);

  @override
  Future<InstallationRecord> writeRecord(InstallationRecord record) =>
      _inner.writeRecord(record);

  @override
  Future<InstallationRecord> updateRecord(
      FutureOr<InstallationRecord> Function(InstallationRecord current)
          transform) async {
    if (failOnUpdate) {
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.installationRecordWriteFailed,
        message: 'Simulato fallimento di I/O nel registro.',
      );
    }
    return _inner.updateRecord(transform);
  }
}

void main() {
  group('ProvisioningCoordinator Tests -', () {
    late Directory tempDir;
    late ProvisioningPathResolver pathResolver;
    late JsonInstallationRecordRepository rawRecordRepo;
    late FaultyInstallationRecordRepository recordRepo;
    late JsonActivationStateRepository activationRepo;
    late FakeProvisioningHttpClient httpClient;
    late ArtifactIngestionEngine ingestionEngine;
    late InMemoryProvisioningLock lock;
    late ProvisioningCoordinator coordinator;

    late List<int> zipBytes;
    late CatalogArtifact sampleArtifact;
    late CatalogManifest sampleManifest;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('aura_coordinator_test_');

      pathResolver = ProvisioningPathResolver(
        appManagedRoot: '${tempDir.path}\\app_managed',
        bundledRoot: '${tempDir.path}\\bundled',
      );

      final fileSystem = const LocalProvisioningFileSystem();
      lock = InMemoryProvisioningLock();

      rawRecordRepo = JsonInstallationRecordRepository(
        pathResolver: pathResolver,
        lock: lock,
        fileSystem: fileSystem,
      );
      recordRepo = FaultyInstallationRecordRepository(rawRecordRepo);

      activationRepo = JsonActivationStateRepository(
        pathResolver: pathResolver,
        lock: lock,
        fileSystem: fileSystem,
      );

      httpClient = FakeProvisioningHttpClient();
      ingestionEngine = ArtifactIngestionEngine(
        pathResolver: pathResolver,
        httpClient: httpClient,
        fileSystem: fileSystem,
      );

      coordinator = ProvisioningCoordinator(
        lock: lock,
        recordRepository: recordRepo,
        activationRepository: activationRepo,
        ingestionEngine: ingestionEngine,
        pathResolver: pathResolver,
        fileSystem: fileSystem,
      );

      const artifactContent = 'llama-server binary simulated content';
      final contentBytes = utf8.encode(artifactContent);
      final archive = Archive()
        ..addFile(
            ArchiveFile('llama-server.exe', contentBytes.length, contentBytes));
      zipBytes = ZipEncoder().encode(archive)!;

      const uri = 'https://downloads.aura.local/llama-server-b3500.zip';
      httpClient.remoteFiles[uri] = zipBytes;

      final expectedHash = sha256.convert(zipBytes).toString().toLowerCase();

      sampleArtifact = CatalogArtifact(
        artifactId: 'llama-b3500',
        artifactType: CatalogArtifactType.runtime,
        displayName: 'llama-server b3500',
        version: 'b3500',
        buildId: 'b3500',
        platform: 'all',
        architecture: 'all',
        fileName: 'llama-server-b3500.zip',
        license: 'MIT',
        sizeBytes: zipBytes.length,
        sha256: expectedHash,
        compression: CatalogCompressionFormat.zip,
        sourceKind: CatalogArtifactSourceKind.remoteHttps,
        downloadUri: uri,
      );

      sampleManifest = CatalogManifest(
        schemaVersion: '1.0',
        catalogId: 'cat-test-63d',
        generatedAt: '2026-07-22T18:00:00.000Z',
        artifacts: [sampleArtifact],
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
        'Esegue il provisioning completo: ingestione fisica, path relativo, generazione installationId e persistenza record',
        () async {
      final consent = DownloadConsent.grantedFor(
        artifactId: 'llama-b3500',
        sourceUri: 'https://downloads.aura.local/llama-server-b3500.zip',
        expectedSizeBytes: zipBytes.length,
        operationId: 'op-prov-1',
      );

      final request = ProvisioningRequest(
        operationId: 'op-prov-1',
        catalogId: 'cat-test-63d',
        artifactId: 'llama-b3500',
        downloadPolicy: ProvisioningDownloadPolicy.explicitConsent,
        consent: consent,
        expectedPlatform: 'windows',
        expectedArchitecture: 'x64',
      );

      final result = await coordinator.provisionArtifact(
        request: request,
        manifest: sampleManifest,
      );

      expect(result.status, equals(ProvisioningStatus.success));
      expect(result.installed, isTrue);
      expect(result.alreadyInstalled, isFalse);
      expect(result.installationId, isNotNull);
      expect(result.installationId, startsWith('inst-llama-b3500-b3500-'));

      final record = await coordinator.getInstallationRecord();
      final descriptor = record.findInstallation(result.installationId!);
      expect(descriptor, isNotNull);
      expect(descriptor!.status, equals(InstallationStatus.verified));
      expect(
          descriptor.relativeInstallPath, equals('runtimes/llama-b3500/b3500'));

      final installedFile = File(
        '${tempDir.path}\\app_managed\\runtimes\\llama-b3500\\b3500\\llama-server.exe',
      );
      expect(await installedFile.exists(), isTrue);
    });

    test(
        'Ritorna già installato (idempotenza) se il record è verified ed i file fisici/hash sono integri',
        () async {
      final consent = DownloadConsent.grantedFor(
        artifactId: 'llama-b3500',
        sourceUri: 'https://downloads.aura.local/llama-server-b3500.zip',
        expectedSizeBytes: zipBytes.length,
        operationId: 'op-prov-idemp',
      );

      final request = ProvisioningRequest(
        operationId: 'op-prov-idemp',
        catalogId: 'cat-test-63d',
        artifactId: 'llama-b3500',
        downloadPolicy: ProvisioningDownloadPolicy.explicitConsent,
        consent: consent,
        expectedPlatform: 'windows',
        expectedArchitecture: 'x64',
      );

      final res1 = await coordinator.provisionArtifact(
        request: request,
        manifest: sampleManifest,
      );

      final res2 = await coordinator.provisionArtifact(
        request: request,
        manifest: sampleManifest,
      );

      expect(res2.status, equals(ProvisioningStatus.alreadyInstalled));
      expect(res2.alreadyInstalled, isTrue);
      expect(res2.installationId, equals(res1.installationId));
    });

    test(
        'Rifiuta path assoluti o con traversal in resolveAppManagedRelativePath',
        () {
      expect(
        () =>
            pathResolver.resolveAppManagedRelativePath('C:\\Windows\\System32'),
        throwsA(isA<ProvisioningException>()),
      );

      expect(
        () => pathResolver.resolveAppManagedRelativePath('..\\..\\secret.txt'),
        throwsA(isA<ProvisioningException>()),
      );
    });

    test('Rifiuta la rimozione diretta di un installazione attualmente attiva',
        () async {
      final consent = DownloadConsent.grantedFor(
        artifactId: 'llama-b3500',
        sourceUri: 'https://downloads.aura.local/llama-server-b3500.zip',
        expectedSizeBytes: zipBytes.length,
        operationId: 'op-prov-actrem',
      );

      final request = ProvisioningRequest(
        operationId: 'op-prov-actrem',
        catalogId: 'cat-test-63d',
        artifactId: 'llama-b3500',
        downloadPolicy: ProvisioningDownloadPolicy.explicitConsent,
        consent: consent,
        expectedPlatform: 'windows',
        expectedArchitecture: 'x64',
      );

      final provRes = await coordinator.provisionArtifact(
        request: request,
        manifest: sampleManifest,
      );

      await coordinator.activateInstallation(
        installationId: provRes.installationId!,
        operationId: 'op-act-1',
      );

      final remRes = await coordinator.removeInstallation(
        installationId: provRes.installationId!,
        operationId: 'op-rem-active',
      );

      expect(remRes.status, equals(ProvisioningStatus.failed));
      expect(remRes.failureReason,
          equals(ProvisioningFailureReason.installationConflict));
    });
  });
}
