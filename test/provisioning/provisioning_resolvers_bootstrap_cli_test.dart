import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:aura_core/aura_offline.dart';
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
  group('Phase 6.3e - Resolvers, Bootstrap Service & CLI Runner Tests', () {
    late Directory tempDir;
    late ProvisioningPathResolver pathResolver;
    late ProvisioningFileSystem fileSystem;
    late JsonInstallationRecordRepository recordRepo;
    late JsonActivationStateRepository activationRepo;
    late FakeProvisioningHttpClient httpClient;
    late ArtifactIngestionEngine ingestionEngine;
    late InMemoryProvisioningLock lock;
    late ProvisioningCoordinator coordinator;
    late InstalledArtifactVerifier verifier;
    late ModelCatalog catalog;

    late ModelResolver modelResolver;
    late RuntimeResolver runtimeResolver;
    late ProvisioningBootstrapService bootstrapService;
    late ProvisioningCliRunner cliRunner;

    late CatalogArtifact sampleModelArtifact;
    late CatalogManifest sampleManifest;
    late List<int> modelBytes;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('aura_63e_test_');

      pathResolver = ProvisioningPathResolver(
        appManagedRoot: '${tempDir.path}\\app_managed',
        bundledRoot: '${tempDir.path}\\bundled',
      );

      fileSystem = const LocalProvisioningFileSystem();
      lock = InMemoryProvisioningLock();

      recordRepo = JsonInstallationRecordRepository(
        pathResolver: pathResolver,
        lock: lock,
        fileSystem: fileSystem,
      );

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

      verifier = LocalInstalledArtifactVerifier(fileSystem: fileSystem);

      coordinator = ProvisioningCoordinator(
        lock: lock,
        recordRepository: recordRepo,
        activationRepository: activationRepo,
        ingestionEngine: ingestionEngine,
        pathResolver: pathResolver,
        fileSystem: fileSystem,
        verifier: verifier,
      );

      catalog = ModelCatalog.initialDefault();

      modelResolver = ModelResolver(
        catalog: catalog,
        recordRepository: recordRepo,
        activationRepository: activationRepo,
        pathResolver: pathResolver,
        verifier: verifier,
      );

      runtimeResolver = RuntimeResolver(
        recordRepository: recordRepo,
        activationRepository: activationRepo,
        pathResolver: pathResolver,
        verifier: verifier,
      );

      bootstrapService = ProvisioningBootstrapService(
        pathResolver: pathResolver,
        recordRepository: recordRepo,
        activationRepository: activationRepo,
        modelResolver: modelResolver,
        runtimeResolver: runtimeResolver,
        fileSystem: fileSystem,
      );

      cliRunner = ProvisioningCliRunner(
        bootstrapService: bootstrapService,
        coordinator: coordinator,
        recordRepository: recordRepo,
      );

      const mockGguifContent = 'GGUF v3 simulated binary content for Gemma QAT';
      modelBytes = utf8.encode(mockGguifContent);
      const uri = 'https://downloads.aura.local/gemma-4-12b-qat.gguf';
      httpClient.remoteFiles[uri] = modelBytes;

      final hashStr = sha256.convert(modelBytes).toString().toLowerCase();

      sampleModelArtifact = CatalogArtifact(
        artifactId: 'gemma-4-12b-it-qat-q4-0',
        artifactType: CatalogArtifactType.model,
        displayName: 'Gemma 4 12B QAT',
        version: 'v1.0',
        buildId: 'b1',
        platform: 'all',
        architecture: 'all',
        fileName: 'gemma-4-12B-it-QAT-Q4_0.gguf',
        license: 'Apache-2.0',
        sizeBytes: modelBytes.length,
        sha256: hashStr,
        compression: CatalogCompressionFormat.none,
        sourceKind: CatalogArtifactSourceKind.remoteHttps,
        downloadUri: uri,
        metadata: const {'role': 'actor', 'isDefaultActor': true},
      );

      sampleManifest = CatalogManifest(
        schemaVersion: '1.0',
        catalogId: 'cat-63e',
        generatedAt: '2026-07-22T19:00:00.000Z',
        artifacts: [sampleModelArtifact],
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('1. ModelResolver risolve l installazione attiva integrabile',
        () async {
      final consent = DownloadConsent.grantedFor(
        artifactId: 'gemma-4-12b-it-qat-q4-0',
        sourceUri: 'https://downloads.aura.local/gemma-4-12b-qat.gguf',
        expectedSizeBytes: modelBytes.length,
        operationId: 'op-63e-1',
      );

      final request = ProvisioningRequest(
        operationId: 'op-63e-1',
        catalogId: 'cat-63e',
        artifactId: 'gemma-4-12b-it-qat-q4-0',
        downloadPolicy: ProvisioningDownloadPolicy.explicitConsent,
        consent: consent,
        expectedPlatform: 'windows',
        expectedArchitecture: 'x64',
      );

      final provRes = await coordinator.provisionArtifact(
        request: request,
        manifest: sampleManifest,
      );
      expect(provRes.status, equals(ProvisioningStatus.success));

      final actRes = await coordinator.activateInstallation(
        installationId: provRes.installationId!,
        operationId: 'op-act-63e',
      );
      expect(actRes.isSuccess, isTrue);

      final res = await modelResolver.resolveModel('actor.default');
      expect(res.isSuccess, isTrue);
      expect(res.payload!.installationId, equals(provRes.installationId));
      expect(res.payload!.isFallbackUsed, isFalse);
      expect(res.payload!.absoluteModelPath,
          contains('gemma-4-12B-it-QAT-Q4_0.gguf'));
    });

    test(
        '2. ModelResolver attiva il fallback su lastKnownGood se l installazione attiva e corrotta',
        () async {
      final consent = DownloadConsent.grantedFor(
        artifactId: 'gemma-4-12b-it-qat-q4-0',
        sourceUri: 'https://downloads.aura.local/gemma-4-12b-qat.gguf',
        expectedSizeBytes: modelBytes.length,
        operationId: 'op-63e-fallback',
      );

      final request = ProvisioningRequest(
        operationId: 'op-63e-fallback',
        catalogId: 'cat-63e',
        artifactId: 'gemma-4-12b-it-qat-q4-0',
        downloadPolicy: ProvisioningDownloadPolicy.explicitConsent,
        consent: consent,
        expectedPlatform: 'windows',
        expectedArchitecture: 'x64',
      );

      final provRes1 = await coordinator.provisionArtifact(
        request: request,
        manifest: sampleManifest,
      );
      await coordinator.activateInstallation(
        installationId: provRes1.installationId!,
        operationId: 'act-1',
      );

      // Simula una nuova installazione e la imposta come attiva
      // Poi simula la corruzione eliminando il file della nuova installazione
      final stateBefore = await activationRepo.readState();
      await activationRepo.replaceState(
        stateBefore.copyWith(
          activeModelInstallationId: 'inst-corrupted-active',
          lastKnownGoodModelInstallationId: provRes1.installationId,
        ),
      );

      final res = await modelResolver.resolveModel('actor.default');
      expect(res.isSuccess, isTrue);
      expect(res.payload!.installationId, equals(provRes1.installationId));
      expect(res.payload!.isFallbackUsed, isTrue);
      expect(res.payload!.fallbackSource, equals('lastKnownGood'));
    });

    test(
        '3. ProvisioningBootstrapService crea le directory e riconcilia lo stato all avvio',
        () async {
      final bootRes = await bootstrapService.bootstrap();
      expect(bootRes.diagnostics['appManagedRoot'],
          equals(pathResolver.appManagedRoot));
      expect(Directory('${tempDir.path}\\app_managed\\models').existsSync(),
          isTrue);
      expect(Directory('${tempDir.path}\\app_managed\\runtimes').existsSync(),
          isTrue);
      expect(Directory('${tempDir.path}\\app_managed\\records').existsSync(),
          isTrue);
      expect(Directory('${tempDir.path}\\app_managed\\activation').existsSync(),
          isTrue);
    });

    test(
        '4. ProvisioningCliRunner formatta correttamente i comandi diagnostici e di gestione',
        () async {
      final statusRes = await cliRunner.status();
      expect(statusRes.command, equals('status'));
      expect(statusRes.toFormattedJson(), contains('appManagedRoot'));

      final listCatRes = cliRunner.listCatalog(sampleManifest);
      expect(listCatRes.success, isTrue);
      expect(listCatRes.toFormattedJson(), contains('gemma-4-12b-it-qat-q4-0'));

      final listInstRes = await cliRunner.listInstalled();
      expect(listInstRes.success, isTrue);
      expect(listInstRes.command, equals('list-installed'));
    });
  });
}
