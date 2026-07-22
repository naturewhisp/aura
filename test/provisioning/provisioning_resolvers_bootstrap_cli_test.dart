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
  group(
      'Phase 6.3e - Role-Aware Resolvers, Bootstrap Service & CLI Runner Tests',
      () {
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

    late CatalogArtifact actorArtifact;
    late CatalogArtifact evaluatorArtifact;
    late CatalogManifest sampleManifest;

    late List<int> actorBytes;
    late List<int> evaluatorBytes;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('aura_63e_role_test_');

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
        fileSystem: fileSystem,
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

      // Simula i byte ed i file per Actor ed Evaluator
      const actorContent = 'GGUF v3 Gemma 4 12B QAT content';
      actorBytes = utf8.encode(actorContent);
      const actorUri = 'https://downloads.aura.local/gemma-4-12b.gguf';
      httpClient.remoteFiles[actorUri] = actorBytes;

      const evalContent = 'GGUF v3 Ministral 3B content';
      evaluatorBytes = utf8.encode(evalContent);
      const evalUri = 'https://downloads.aura.local/ministral-3b.gguf';
      httpClient.remoteFiles[evalUri] = evaluatorBytes;

      actorArtifact = CatalogArtifact(
        artifactId: 'gemma-4-12b-it-qat-q4-0',
        artifactType: CatalogArtifactType.model,
        displayName: 'Gemma 4 12B QAT',
        version: 'v1.0',
        buildId: 'b1',
        platform: 'all',
        architecture: 'all',
        fileName: 'gemma-4-12B-it-QAT-Q4_0.gguf',
        license: 'Apache-2.0',
        sizeBytes: actorBytes.length,
        sha256: sha256.convert(actorBytes).toString().toLowerCase(),
        compression: CatalogCompressionFormat.none,
        sourceKind: CatalogArtifactSourceKind.remoteHttps,
        downloadUri: actorUri,
        metadata: const {'role': 'actor', 'isDefaultActor': true},
      );

      evaluatorArtifact = CatalogArtifact(
        artifactId: 'ministral-3b',
        artifactType: CatalogArtifactType.model,
        displayName: 'Ministral 3B Instruct',
        version: 'v1.0',
        buildId: 'b1',
        platform: 'all',
        architecture: 'all',
        fileName: 'ministral-3b.gguf',
        license: 'Apache-2.0',
        sizeBytes: evaluatorBytes.length,
        sha256: sha256.convert(evaluatorBytes).toString().toLowerCase(),
        compression: CatalogCompressionFormat.none,
        sourceKind: CatalogArtifactSourceKind.remoteHttps,
        downloadUri: evalUri,
        metadata: const {'role': 'evaluator', 'isDefaultEvaluator': true},
      );

      sampleManifest = CatalogManifest(
        schemaVersion: '1.0',
        catalogId: 'cat-63e-dual',
        generatedAt: '2026-07-22T19:00:00.000Z',
        artifacts: [actorArtifact, evaluatorArtifact],
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
        '1. ModelResolver risolve in modo separato e role-aware Actor ed Evaluator',
        () async {
      // Installa Actor
      final reqActor = ProvisioningRequest(
        operationId: 'op-act-inst',
        catalogId: 'cat-63e-dual',
        artifactId: 'gemma-4-12b-it-qat-q4-0',
        downloadPolicy: ProvisioningDownloadPolicy.explicitConsent,
        consent: DownloadConsent.grantedFor(
          artifactId: 'gemma-4-12b-it-qat-q4-0',
          sourceUri: 'https://downloads.aura.local/gemma-4-12b.gguf',
          expectedSizeBytes: actorBytes.length,
          operationId: 'op-act-inst',
        ),
        expectedPlatform: 'windows',
        expectedArchitecture: 'x64',
      );
      final resActorProv = await coordinator.provisionArtifact(
        request: reqActor,
        manifest: sampleManifest,
      );
      await coordinator.activateInstallation(
        installationId: resActorProv.installationId!,
        operationId: 'act-actor',
        modelRole: ModelActivationRole.actor,
      );

      // Risoluzione Actor
      final resolvedActor = await modelResolver.resolveModel('actor.default');
      expect(resolvedActor.isSuccess, isTrue);
      expect(resolvedActor.payload!.modelId, equals('gemma-4-12b-it-qat-q4-0'));

      // Risoluzione Evaluator quando non è ancora installato: NON deve restituire Gemma!
      final resolvedEvaluator =
          await modelResolver.resolveModel('evaluator.default');
      expect(resolvedEvaluator.isSuccess, isFalse);
    });

    test(
        '2. Attivazione esplicita per ruolo Actor ed Evaluator nel coordinatore',
        () async {
      // Installa Evaluator (Ministral)
      final reqEval = ProvisioningRequest(
        operationId: 'op-eval-inst',
        catalogId: 'cat-63e-dual',
        artifactId: 'ministral-3b',
        downloadPolicy: ProvisioningDownloadPolicy.explicitConsent,
        consent: DownloadConsent.grantedFor(
          artifactId: 'ministral-3b',
          sourceUri: 'https://downloads.aura.local/ministral-3b.gguf',
          expectedSizeBytes: evaluatorBytes.length,
          operationId: 'op-eval-inst',
        ),
        expectedPlatform: 'windows',
        expectedArchitecture: 'x64',
      );
      final resEvalProv = await coordinator.provisionArtifact(
        request: reqEval,
        manifest: sampleManifest,
      );

      // Tentativo di attivazione senza modelRole deve fallire con roleRequired
      final failAct = await coordinator.activateInstallation(
        installationId: resEvalProv.installationId!,
        operationId: 'op-act-norole',
      );
      expect(failAct.success, isFalse);
      expect(
          failAct.failureReason, equals(ActivationFailureReason.roleRequired));

      // Attivazione esplicita come Evaluator
      final succAct = await coordinator.activateInstallation(
        installationId: resEvalProv.installationId!,
        operationId: 'op-act-eval',
        modelRole: ModelActivationRole.evaluator,
      );
      expect(succAct.success, isTrue);

      final state = await coordinator.getActivationState();
      expect(state.activeEvaluatorModelInstallationId,
          equals(resEvalProv.installationId));
      expect(state.schemaVersion, equals('1.1'));

      // Protezione dalla rimozione dell'Evaluator attivo
      final remRes = await coordinator.removeInstallation(
        installationId: resEvalProv.installationId!,
        operationId: 'op-rem-eval',
      );
      expect(remRes.status, equals(ProvisioningStatus.failed));
      expect(remRes.failureReason,
          equals(ProvisioningFailureReason.installationConflict));
    });

    test('3. Serialization ActivationState.toJson non duplica i campi legacy',
        () {
      final state = ActivationState(
        schemaVersion: '1.1',
        updatedAt: DateTime.now().toUtc().toIso8601String(),
        activeActorModelInstallationId: 'inst-actor-1',
        activeEvaluatorModelInstallationId: 'inst-eval-1',
      );
      final jsonMap = state.toJson();

      expect(jsonMap['schemaVersion'], equals('1.1'));
      expect(jsonMap['activeActorModelInstallationId'], equals('inst-actor-1'));
      expect(
          jsonMap['activeEvaluatorModelInstallationId'], equals('inst-eval-1'));
      expect(jsonMap.containsKey('activeModelInstallationId'), isFalse);
      expect(jsonMap.containsKey('lastKnownGoodModelInstallationId'), isFalse);
    });

    test(
        '4. Bootstrap esige SIA Actor SIA Evaluator SIA Runtime per lo stato ready',
        () async {
      // Senza Evaluator e Runtime installati, il bootstrap restituisce failed
      final bootRes1 = await bootstrapService.bootstrap();
      expect(bootRes1.status, equals(ProvisioningBootstrapStatus.failed));
      expect(bootRes1.diagnostics['isActorValid'], isFalse);
      expect(bootRes1.diagnostics['isEvaluatorValid'], isFalse);
      expect(bootRes1.diagnostics['isRuntimeValid'], isFalse);
    });

    test(
        '5. RuntimeResolver verifica l effettiva presenza di llama-server.exe su disco',
        () async {
      // Crea un descrittore di runtime fittizio verified nel registro ma senza file su disco
      final rec = await recordRepo.readRecord();
      final fakeRuntime = InstalledArtifactDescriptor(
        installationId: 'inst-runtime-fake',
        artifactId: 'llama-b3500',
        artifactType: CatalogArtifactType.runtime,
        displayName: 'llama-server fake',
        version: 'b3500',
        buildId: 'b3500',
        platform: 'all',
        architecture: 'all',
        relativeInstallPath: 'runtimes/llama-b3500/b3500',
        entryFileName: null,
        installedAt: DateTime.now().toUtc().toIso8601String(),
        verifiedAt: DateTime.now().toUtc().toIso8601String(),
        sizeBytes: 100,
        sha256: 'abc',
        sourceKind: CatalogArtifactSourceKind.bundled,
        status: InstallationStatus.verified,
      );
      await recordRepo.writeRecord(rec.upsertArtifact(fakeRuntime));

      // Deve fallire se l'eseguibile llama-server.exe non esiste fisicamente nel path risolto
      final res = await runtimeResolver.resolveRuntime(
          requestedInstallationId: 'inst-runtime-fake');
      expect(res.isSuccess, isFalse);
    });

    test(
        '6. ProvisioningCliRunner e executable entry point rispondono ai comandi CLI',
        () async {
      final statusRes = await cliRunner.status();
      expect(statusRes.command, equals('status'));
      expect(statusRes.toFormattedJson(), contains('diagnostics'));

      final listCatRes = cliRunner.listCatalog(sampleManifest);
      expect(listCatRes.success, isTrue);
      expect(listCatRes.toFormattedJson(), contains('gemma-4-12b-it-qat-q4-0'));
      expect(listCatRes.toFormattedJson(), contains('ministral-3b'));

      final listInstRes = await cliRunner.listInstalled();
      expect(listInstRes.success, isTrue);
    });
  });
}
