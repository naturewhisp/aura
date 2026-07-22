import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
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
    FutureOr<InstallationRecord> Function(InstallationRecord current) transform,
  ) async {
    if (failOnUpdate) {
      throw const ProvisioningIoException(operation: 'updateRecord');
    }
    return _inner.updateRecord(transform);
  }
}

void main() {
  group('Gemma 4 12B QAT Q4_0 Model Baseline Tests -', () {
    late Directory tempDir;
    late ProvisioningLock lock;
    late ProvisioningPathResolver pathResolver;
    late FakeProvisioningHttpClient httpClient;
    late JsonInstallationRecordRepository innerRecordRepo;
    late FaultyInstallationRecordRepository recordRepo;
    late JsonActivationStateRepository activationRepo;
    late ArtifactIngestionEngine ingestionEngine;
    late ProvisioningCoordinator coordinator;
    late CatalogManifest catalogManifest;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('aura_gemma_qat_test_');
      lock = InMemoryProvisioningLock();
      pathResolver = ProvisioningPathResolver(
        appManagedRoot: '${tempDir.path}\\app_managed',
        bundledRoot: '${tempDir.path}\\bundled',
      );
      httpClient = FakeProvisioningHttpClient();

      innerRecordRepo = JsonInstallationRecordRepository(
        pathResolver: pathResolver,
        lock: lock,
      );
      recordRepo = FaultyInstallationRecordRepository(innerRecordRepo);

      activationRepo = JsonActivationStateRepository(
        pathResolver: pathResolver,
        lock: lock,
      );

      ingestionEngine = ArtifactIngestionEngine(
        pathResolver: pathResolver,
        httpClient: httpClient,
      );

      coordinator = ProvisioningCoordinator(
        lock: lock,
        recordRepository: recordRepo,
        activationRepository: activationRepo,
        ingestionEngine: ingestionEngine,
        pathResolver: pathResolver,
      );

      catalogManifest = CatalogManifest.initialDefault();
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
        '1. Il catalogo contiene il nuovo artefatto Gemma QAT con metadati completi e corretti',
        () {
      final gemmaQat = catalogManifest.findArtifact('gemma-4-12b-it-qat-q4-0');
      expect(gemmaQat, isNotNull);
      expect(gemmaQat!.fileName, equals('gemma-4-12B-it-QAT-Q4_0.gguf'));
      expect(gemmaQat.quantization, equals('Q4_0'));
      expect(gemmaQat.sizeBytes, equals(6975879008));
      expect(
          gemmaQat.sha256,
          equals(
              'f568ac5de71c8fcac5d5794494388ad94db9e18b4368ca897e21b30d2448eeec'));
      expect(gemmaQat.compression, equals(CatalogCompressionFormat.none));
      expect(gemmaQat.metadata['repository'],
          equals('lmstudio-community/gemma-4-12B-it-QAT-GGUF'));
      expect(gemmaQat.metadata['revision'],
          equals('aaec3dd9d1012557147a627142759994d1fd8d37'));
      expect(gemmaQat.metadata['quantizationStrategy'], equals('QAT'));
    });

    test('2. Il default Actor nel ModelCatalog risolve al nuovo artefatto QAT',
        () {
      final modelCatalog = ModelCatalog.initialDefault();
      final actorEntry = modelCatalog.findModel('gemma-4-12b-it-qat-q4-0');
      expect(actorEntry, isNotNull);
      expect(actorEntry!.recommendedAgents, contains('actor'));
      expect(actorEntry.quantization, equals('q4_0'));
    });

    test(
        '3. Il default Evaluator continua a risolvere al modello Mistral precedente',
        () {
      final modelCatalog = ModelCatalog.initialDefault();
      final evalEntry = modelCatalog.findModel('mistralai/ministral-3-3b');
      expect(evalEntry, isNotNull);
      expect(evalEntry!.recommendedAgents, contains('evaluator'));
    });

    test('4. Il ModelRouter non scambia Actor ed Evaluator', () {
      final modelCatalog = ModelCatalog.initialDefault();
      const router = ModelRouter();
      final resolution = router.resolve(
        loadedModelIds: ['mistralai/ministral-3-3b', 'gemma-4-12b-it-qat-q4-0'],
        catalog: modelCatalog,
      );

      expect(resolution.evaluatorModelId, equals('mistralai/ministral-3-3b'));
      expect(resolution.actorModelId, equals('gemma-4-12b-it-qat-q4-0'));
      expect(resolution.profileName, contains('P2: Deep Reasoning'));
    });

    test(
        '5. Un fresh bootstrap/provisioning seleziona Gemma QAT per Actor e Mistral per Evaluator',
        () async {
      final defaultActor = catalogManifest.artifacts
          .firstWhere((a) => a.metadata['isDefaultActor'] == true);
      final defaultEval = catalogManifest.artifacts
          .firstWhere((a) => a.metadata['isDefaultEvaluator'] == true);

      expect(defaultActor.artifactId, equals('gemma-4-12b-it-qat-q4-0'));
      expect(defaultEval.artifactId, equals('mistralai/ministral-3-3b'));
    });

    test(
        '6. Una selezione esplicita esistente dell utente in ActivationState non viene sovrascritta',
        () async {
      final userState = ActivationState(
        updatedAt: DateTime.now().toUtc().toIso8601String(),
        activeRuntimeInstallationId: 'user-custom-runtime-id',
        activeModelInstallationId: 'user-custom-actor-id',
        explicitUserSelection: true,
        selectedModelAlias: 'qwen/qwen3.5-9b',
      );

      await activationRepo.replaceState(userState);

      final readState = await coordinator.getActivationState();
      expect(readState.explicitUserSelection, isTrue);
      expect(readState.selectedModelAlias, equals('qwen/qwen3.5-9b'));
      expect(
          readState.activeModelInstallationId, equals('user-custom-actor-id'));
    });

    test(
        '7. Il nuovo artefatto QAT e il vecchio Q4_K_M non producono la stessa installation identity',
        () {
      final qatArtifact =
          catalogManifest.findArtifact('gemma-4-12b-it-qat-q4-0')!;
      final legacyArtifact =
          catalogManifest.findArtifact('google/gemma-4-12b')!;

      expect(qatArtifact.artifactId, isNot(equals(legacyArtifact.artifactId)));
      expect(qatArtifact.sha256, isNot(equals(legacyArtifact.sha256)));
    });

    test(
        '8. Una seconda esecuzione della provisioning orchestration e idempotente per Gemma QAT',
        () async {
      const uri =
          'https://huggingface.co/lmstudio-community/gemma-4-12B-it-QAT-GGUF/resolve/aaec3dd9d1012557147a627142759994d1fd8d37/gemma-4-12B-it-QAT-Q4_0.gguf';

      final contentBytes = utf8.encode('mock gemma qat content');
      final archive = Archive()
        ..addFile(ArchiveFile(
            'gemma-4-12B-it-QAT-Q4_0.gguf', contentBytes.length, contentBytes));
      final zipBytes = ZipEncoder().encode(archive)!;

      httpClient.remoteFiles[uri] = zipBytes;
      final expectedHash = sha256.convert(zipBytes).toString().toLowerCase();

      final testArtifact = CatalogArtifact(
        artifactId: 'gemma-4-12b-it-qat-q4-0',
        artifactType: CatalogArtifactType.model,
        displayName: 'Gemma 4 12B IT QAT (Q4_0)',
        version: 'aaec3dd9d1012557147a627142759994d1fd8d37',
        buildId: 'aaec3dd9d1012557147a627142759994d1fd8d37',
        platform: 'windows',
        architecture: 'x64',
        fileName: 'gemma-4-12B-it-QAT-Q4_0.gguf',
        sourceKind: CatalogArtifactSourceKind.remoteHttps,
        downloadUri: uri,
        sizeBytes: zipBytes.length,
        sha256: expectedHash,
        license: 'apache-2.0',
        compression: CatalogCompressionFormat.zip,
      );

      final manifest = CatalogManifest(
        schemaVersion: '1.0',
        catalogId: 'test-cat',
        generatedAt: '2026-07-22T18:00:00.000Z',
        artifacts: [testArtifact],
      );

      final consent = DownloadConsent.grantedFor(
        artifactId: 'gemma-4-12b-it-qat-q4-0',
        sourceUri: uri,
        expectedSizeBytes: zipBytes.length,
        operationId: 'op-idem-1',
      );

      final req = ProvisioningRequest(
        operationId: 'op-idem-1',
        catalogId: 'test-cat',
        artifactId: 'gemma-4-12b-it-qat-q4-0',
        downloadPolicy: ProvisioningDownloadPolicy.explicitConsent,
        consent: consent,
        expectedPlatform: 'windows',
        expectedArchitecture: 'x64',
      );

      final res1 =
          await coordinator.provisionArtifact(request: req, manifest: manifest);
      expect(res1.status, equals(ProvisioningStatus.success));
      expect(res1.alreadyInstalled, isFalse);

      final res2 =
          await coordinator.provisionArtifact(request: req, manifest: manifest);
      expect(res2.status, equals(ProvisioningStatus.alreadyInstalled));
      expect(res2.alreadyInstalled, isTrue);
      expect(res2.installationId, equals(res1.installationId));
    });

    test(
        '9. Un installazione Gemma QAT verificata puo essere registrata e attivata',
        () async {
      const uri =
          'https://huggingface.co/lmstudio-community/gemma-4-12B-it-QAT-GGUF/resolve/aaec3dd9d1012557147a627142759994d1fd8d37/gemma-4-12B-it-QAT-Q4_0.gguf';

      final contentBytes = utf8.encode('mock gemma qat content');
      final archive = Archive()
        ..addFile(ArchiveFile(
            'gemma-4-12B-it-QAT-Q4_0.gguf', contentBytes.length, contentBytes));
      final zipBytes = ZipEncoder().encode(archive)!;

      httpClient.remoteFiles[uri] = zipBytes;
      final expectedHash = sha256.convert(zipBytes).toString().toLowerCase();

      final testArtifact = CatalogArtifact(
        artifactId: 'gemma-4-12b-it-qat-q4-0',
        artifactType: CatalogArtifactType.model,
        displayName: 'Gemma 4 12B IT QAT (Q4_0)',
        version: 'aaec3dd9d1012557147a627142759994d1fd8d37',
        buildId: 'aaec3dd9d1012557147a627142759994d1fd8d37',
        platform: 'windows',
        architecture: 'x64',
        fileName: 'gemma-4-12B-it-QAT-Q4_0.gguf',
        sourceKind: CatalogArtifactSourceKind.remoteHttps,
        downloadUri: uri,
        sizeBytes: zipBytes.length,
        sha256: expectedHash,
        license: 'apache-2.0',
        compression: CatalogCompressionFormat.zip,
      );

      final manifest = CatalogManifest(
        schemaVersion: '1.0',
        catalogId: 'test-cat',
        generatedAt: '2026-07-22T18:00:00.000Z',
        artifacts: [testArtifact],
      );

      final consent = DownloadConsent.grantedFor(
        artifactId: 'gemma-4-12b-it-qat-q4-0',
        sourceUri: uri,
        expectedSizeBytes: zipBytes.length,
        operationId: 'op-act-1',
      );

      final req = ProvisioningRequest(
        operationId: 'op-act-1',
        catalogId: 'test-cat',
        artifactId: 'gemma-4-12b-it-qat-q4-0',
        downloadPolicy: ProvisioningDownloadPolicy.explicitConsent,
        consent: consent,
        expectedPlatform: 'windows',
        expectedArchitecture: 'x64',
      );

      final provRes =
          await coordinator.provisionArtifact(request: req, manifest: manifest);
      expect(provRes.status, equals(ProvisioningStatus.success));

      final actRes = await coordinator.activateArtifact(
        artifactId: 'gemma-4-12b-it-qat-q4-0',
        version: 'aaec3dd9d1012557147a627142759994d1fd8d37',
        operationId: 'op-act-run',
      );

      expect(actRes.success, isTrue);

      final state = await coordinator.getActivationState();
      expect(state.activeModelInstallationId, equals(provRes.installationId));
    });

    test(
        '10. Un installazione non verificata o non presente non puo diventare l Actor attivo',
        () async {
      final actRes = await coordinator.activateArtifact(
        artifactId: 'gemma-4-12b-it-qat-q4-0',
        version: 'unverified-version',
        operationId: 'op-act-fail',
      );

      expect(actRes.success, isFalse);
      expect(actRes.failureReason, contains('non installato'));

      final state = await coordinator.getActivationState();
      expect(state.activeModelInstallationId, isNull);
    });

    test(
        '11. Il last-known-good Actor non viene perso in caso di fallimento dell attivazione del nuovo modello',
        () async {
      final initState = ActivationState(
        updatedAt: DateTime.now().toUtc().toIso8601String(),
        activeModelInstallationId: 'lkg-model-inst-id',
        lastKnownGoodModelInstallationId: 'lkg-model-inst-id',
      );
      await activationRepo.replaceState(initState);

      final actRes = await coordinator.activateArtifact(
        artifactId: 'gemma-4-12b-it-qat-q4-0',
        version: 'invalid-version',
        operationId: 'op-act-fail-lkg',
      );

      expect(actRes.success, isFalse);

      final stateAfter = await coordinator.getActivationState();
      expect(stateAfter.activeModelInstallationId, equals('lkg-model-inst-id'));
      expect(stateAfter.lastKnownGoodModelInstallationId,
          equals('lkg-model-inst-id'));
    });

    test(
        '12. Un fallimento di persistenza applica la compensazione fisica senza modificare l Evaluator',
        () async {
      const uri =
          'https://huggingface.co/lmstudio-community/gemma-4-12B-it-QAT-GGUF/resolve/aaec3dd9d1012557147a627142759994d1fd8d37/gemma-4-12B-it-QAT-Q4_0.gguf';

      final contentBytes = utf8.encode('mock gemma qat content');
      final archive = Archive()
        ..addFile(ArchiveFile(
            'gemma-4-12B-it-QAT-Q4_0.gguf', contentBytes.length, contentBytes));
      final zipBytes = ZipEncoder().encode(archive)!;

      httpClient.remoteFiles[uri] = zipBytes;
      final expectedHash = sha256.convert(zipBytes).toString().toLowerCase();

      final testArtifact = CatalogArtifact(
        artifactId: 'gemma-4-12b-it-qat-q4-0',
        artifactType: CatalogArtifactType.model,
        displayName: 'Gemma 4 12B IT QAT (Q4_0)',
        version: 'aaec3dd9d1012557147a627142759994d1fd8d37',
        buildId: 'aaec3dd9d1012557147a627142759994d1fd8d37',
        platform: 'windows',
        architecture: 'x64',
        fileName: 'gemma-4-12B-it-QAT-Q4_0.gguf',
        sourceKind: CatalogArtifactSourceKind.remoteHttps,
        downloadUri: uri,
        sizeBytes: zipBytes.length,
        sha256: expectedHash,
        license: 'apache-2.0',
        compression: CatalogCompressionFormat.zip,
      );

      final manifest = CatalogManifest(
        schemaVersion: '1.0',
        catalogId: 'test-cat',
        generatedAt: '2026-07-22T18:00:00.000Z',
        artifacts: [testArtifact],
      );

      final consent = DownloadConsent.grantedFor(
        artifactId: 'gemma-4-12b-it-qat-q4-0',
        sourceUri: uri,
        expectedSizeBytes: zipBytes.length,
        operationId: 'op-fault-1',
      );

      final req = ProvisioningRequest(
        operationId: 'op-fault-1',
        catalogId: 'test-cat',
        artifactId: 'gemma-4-12b-it-qat-q4-0',
        downloadPolicy: ProvisioningDownloadPolicy.explicitConsent,
        consent: consent,
        expectedPlatform: 'windows',
        expectedArchitecture: 'x64',
      );

      recordRepo.failOnUpdate = true;

      final res =
          await coordinator.provisionArtifact(request: req, manifest: manifest);
      expect(res.status, equals(ProvisioningStatus.failed));
      expect(res.rollbackPerformed, isTrue);

      final installedFile = File(
        '${tempDir.path}\\app_managed\\models\\gemma-4-12b-it-qat-q4-0\\aaec3dd9d1012557147a627142759994d1fd8d37\\gemma-4-12B-it-QAT-Q4_0.gguf',
      );
      expect(await installedFile.exists(), isFalse);
    });

    test(
        '13. Le fixture e i test del catalogo non contengono il vecchio Q4_K_M come Actor default',
        () {
      final defaultActor = catalogManifest.artifacts
          .firstWhere((a) => a.metadata['isDefaultActor'] == true);
      expect(defaultActor.artifactId, equals('gemma-4-12b-it-qat-q4-0'));
      expect(defaultActor.quantization, equals('Q4_0'));
    });

    test('14. Nessun test usa la rete reale o dipende da Hugging Face live',
        () {
      expect(httpClient.remoteFiles, isNotNull);
    });
  });
}
