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

      lock = InMemoryProvisioningLock();

      coordinator = ProvisioningCoordinator(
        lock: lock,
        recordRepository: recordRepo,
        activationRepository: activationRepo,
        ingestionEngine: ingestionEngine,
        pathResolver: pathResolver,
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
        'Riconcilia e riesegue l ingestione se la directory fisica o i file sono stati cancellati',
        () async {
      final consent = DownloadConsent.grantedFor(
        artifactId: 'llama-b3500',
        sourceUri: 'https://downloads.aura.local/llama-server-b3500.zip',
        expectedSizeBytes: zipBytes.length,
        operationId: 'op-prov-rec',
      );

      final request = ProvisioningRequest(
        operationId: 'op-prov-rec',
        catalogId: 'cat-test-63d',
        artifactId: 'llama-b3500',
        downloadPolicy: ProvisioningDownloadPolicy.explicitConsent,
        consent: consent,
        expectedPlatform: 'windows',
        expectedArchitecture: 'x64',
      );

      await coordinator.provisionArtifact(
        request: request,
        manifest: sampleManifest,
      );

      final installedDir = Directory(
          '${tempDir.path}\\app_managed\\runtimes\\llama-b3500\\b3500');
      await installedDir.delete(recursive: true);

      final resReconciled = await coordinator.provisionArtifact(
        request: request,
        manifest: sampleManifest,
      );

      expect(resReconciled.status, equals(ProvisioningStatus.success));
      expect(resReconciled.alreadyInstalled, isFalse);
      expect(await installedDir.exists(), isTrue);
    });

    test(
        'Esegue la compensazione fisica verificando la rimozione dei file se l aggiornamento del record fallisce',
        () async {
      final consent = DownloadConsent.grantedFor(
        artifactId: 'llama-b3500',
        sourceUri: 'https://downloads.aura.local/llama-server-b3500.zip',
        expectedSizeBytes: zipBytes.length,
        operationId: 'op-prov-faulty',
      );

      final request = ProvisioningRequest(
        operationId: 'op-prov-faulty',
        catalogId: 'cat-test-63d',
        artifactId: 'llama-b3500',
        downloadPolicy: ProvisioningDownloadPolicy.explicitConsent,
        consent: consent,
        expectedPlatform: 'windows',
        expectedArchitecture: 'x64',
      );

      recordRepo.failOnUpdate = true;

      final res = await coordinator.provisionArtifact(
        request: request,
        manifest: sampleManifest,
      );

      expect(res.status, equals(ProvisioningStatus.failed));
      expect(res.rollbackPerformed, isTrue);

      final installedFile = File(
        '${tempDir.path}\\app_managed\\runtimes\\llama-b3500\\b3500\\llama-server.exe',
      );
      expect(await installedFile.exists(), isFalse);
    });

    test(
        'Attiva un installazione specifica per installationId e traccia lastKnownGood',
        () async {
      final consent = DownloadConsent.grantedFor(
        artifactId: 'llama-b3500',
        sourceUri: 'https://downloads.aura.local/llama-server-b3500.zip',
        expectedSizeBytes: zipBytes.length,
        operationId: 'op-prov-act',
      );

      final request = ProvisioningRequest(
        operationId: 'op-prov-act',
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

      final actRes = await coordinator.activateInstallation(
        installationId: provRes.installationId!,
        operationId: 'op-act-1',
      );

      expect(actRes.success, isTrue);
      expect(actRes.installationId, equals(provRes.installationId));

      final state = await coordinator.getActivationState();
      expect(state.activeRuntimeInstallationId, equals(provRes.installationId));
    });

    test(
        'Rifiuta l attivazione con ActivationFailureReason tipizzato se installationId non esiste',
        () async {
      final actRes = await coordinator.activateInstallation(
        installationId: 'inst-invalid-999',
        operationId: 'op-act-fail',
      );

      expect(actRes.success, isFalse);
      expect(actRes.failureReason,
          equals(ActivationFailureReason.installationNotFound));
    });

    test(
        'Rimuove correttamente un installazione specifica per installationId ed aggiorna registro e stato di attivazione',
        () async {
      final consent = DownloadConsent.grantedFor(
        artifactId: 'llama-b3500',
        sourceUri: 'https://downloads.aura.local/llama-server-b3500.zip',
        expectedSizeBytes: zipBytes.length,
        operationId: 'op-prov-rem',
      );

      final request = ProvisioningRequest(
        operationId: 'op-prov-rem',
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
        operationId: 'op-act-rem',
      );

      final remRes = await coordinator.removeInstallation(
        installationId: provRes.installationId!,
        operationId: 'op-rem-1',
      );

      expect(remRes.status, equals(ProvisioningStatus.success));

      final record = await coordinator.getInstallationRecord();
      expect(record.findInstallation(provRes.installationId!), isNotNull);
      expect(record.findInstallation(provRes.installationId!)!.status,
          equals(InstallationStatus.removed));

      final actState = await coordinator.getActivationState();
      expect(actState.activeRuntimeInstallationId, isNull);

      final installedFile = File(
        '${tempDir.path}\\app_managed\\runtimes\\llama-b3500\\b3500\\llama-server.exe',
      );
      expect(await installedFile.exists(), isFalse);
    });
  });
}
