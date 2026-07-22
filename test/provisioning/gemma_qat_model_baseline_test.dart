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
  group('Gemma 4 12B QAT Q4_0 Model Baseline & Provisioning Integrity Tests -',
      () {
    late Directory tempDir;
    late ProvisioningPathResolver pathResolver;
    late JsonInstallationRecordRepository recordRepo;
    late JsonActivationStateRepository activationRepo;
    late FakeProvisioningHttpClient httpClient;
    late ArtifactIngestionEngine ingestionEngine;
    late InMemoryProvisioningLock lock;
    late ProvisioningCoordinator coordinator;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('aura_gemma_qat_test_');

      pathResolver = ProvisioningPathResolver(
        appManagedRoot: '${tempDir.path}\\app_managed',
        bundledRoot: '${tempDir.path}\\bundled',
      );

      final fileSystem = const LocalProvisioningFileSystem();
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

      lock = InMemoryProvisioningLock();

      coordinator = ProvisioningCoordinator(
        lock: lock,
        recordRepository: recordRepo,
        activationRepository: activationRepo,
        ingestionEngine: ingestionEngine,
        pathResolver: pathResolver,
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
        '1. Il catalogo manifest contiene Gemma QAT con metadati Reali senza placeholder',
        () {
      final manifest = CatalogManifest.initialDefault();
      final artifact = manifest.findArtifact('gemma-4-12b-it-qat-q4-0');

      expect(artifact, isNotNull);
      expect(artifact!.fileName, equals('gemma-4-12B-it-QAT-Q4_0.gguf'));
      expect(artifact.sizeBytes, equals(6975879008));
      expect(
          artifact.sha256,
          equals(
              'f568ac5de71c8fcac5d5794494388ad94db9e18b4368ca897e21b30d2448eeec'));
      expect(artifact.platform, equals('all'));
      expect(artifact.architecture, equals('all'));
      expect(artifact.downloadUri,
          contains('aaec3dd9d1012557147a627142759994d1fd8d37'));

      // Verifica che non ci siano placeholder come '1111111...' o '2222222...'
      for (final a in manifest.artifacts) {
        expect(a.sha256, isNot(contains('11111111')));
        expect(a.sha256, isNot(contains('22222222')));
      }
    });

    test(
        '2. Il default Actor nel ModelCatalog non dichiara capacità di reasoning o CoT',
        () {
      final catalog = ModelCatalog.initialDefault();
      final gemmaQat = catalog.findModel('gemma-4-12b-it-qat-q4-0');

      expect(gemmaQat, isNotNull);
      expect(gemmaQat!.recommendedAgents, contains('actor'));
      expect(gemmaQat.capabilities, isNot(contains('high_logic_reasoning')));
      expect(gemmaQat.capabilities, contains('instruction_following'));
    });

    test('3. Risoluzione tramite alias logici stabili (LogicalModelIds)', () {
      final catalog = ModelCatalog.initialDefault();

      final actorModelId =
          catalog.resolveLogicalModelId(LogicalModelIds.defaultActor);
      expect(actorModelId, equals('gemma-4-12b-it-qat-q4-0'));

      final primaryAlias =
          catalog.resolveLogicalModelId(LogicalModelIds.primaryActorAlias);
      expect(primaryAlias, equals('gemma-4-12b-it-qat-q4-0'));

      final evaluatorModelId =
          catalog.resolveLogicalModelId(LogicalModelIds.defaultEvaluator);
      expect(evaluatorModelId, equals('mistralai/ministral-3-3b'));
    });

    test('4. Supporto wildcard (platform: all) durante l ingestion fisica',
        () async {
      const mockContent = 'Gemma QAT binary GGUF mock header and model weights';
      final mockBytes = utf8.encode(mockContent);

      final manifest = CatalogManifest.initialDefault();
      final artifact = manifest.findArtifact('gemma-4-12b-it-qat-q4-0')!;

      final testArtifact = artifact.copyWith(
        sizeBytes: mockBytes.length,
        sha256: sha256.convert(mockBytes).toString().toLowerCase(),
      );

      httpClient.remoteFiles[artifact.downloadUri!] = mockBytes;

      final testManifest = CatalogManifest(
        schemaVersion: '1.0',
        catalogId: 'cat-test',
        generatedAt: '2026-07-22T18:00:00.000Z',
        artifacts: [testArtifact],
      );

      final consent = DownloadConsent.grantedFor(
        artifactId: 'gemma-4-12b-it-qat-q4-0',
        sourceUri: artifact.downloadUri!,
        expectedSizeBytes: mockBytes.length,
        operationId: 'op-prov-wildcard',
      );

      final request = ProvisioningRequest(
        operationId: 'op-prov-wildcard',
        catalogId: 'cat-test',
        artifactId: 'gemma-4-12b-it-qat-q4-0',
        downloadPolicy: ProvisioningDownloadPolicy.explicitConsent,
        consent: consent,
        expectedPlatform: 'windows',
        expectedArchitecture: 'x64',
      );

      final result = await coordinator.provisionArtifact(
        request: request,
        manifest: testManifest,
      );

      expect(result.status, equals(ProvisioningStatus.success));
      expect(result.installed, isTrue);

      final record = await coordinator.getInstallationRecord();
      final descriptor = record.findInstallation(result.installationId!);
      expect(descriptor, isNotNull);
      expect(
          descriptor!.relativeInstallPath,
          equals(
              'models/gemma-4-12b-it-qat-q4-0/aaec3dd9d1012557147a627142759994d1fd8d37'));
    });

    test(
        '5. Multi-versioning: installationId come chiave primaria senza sovrascrivere altre revisioni',
        () {
      final desc1 = InstalledArtifactDescriptor(
        installationId: 'inst-gemma-v1',
        artifactId: 'gemma-4-12b-it-qat-q4-0',
        artifactType: CatalogArtifactType.model,
        displayName: 'Gemma QAT v1',
        version: 'rev1',
        buildId: 'rev1',
        platform: 'all',
        architecture: 'all',
        relativeInstallPath: 'models/gemma/rev1',
        installedAt: '2026-07-22T10:00:00Z',
        verifiedAt: '2026-07-22T10:00:00Z',
        sizeBytes: 6000000000,
        sha256: 'abc111',
        sourceKind: CatalogArtifactSourceKind.remoteHttps,
        status: InstallationStatus.verified,
      );

      final desc2 = InstalledArtifactDescriptor(
        installationId: 'inst-gemma-v2',
        artifactId: 'gemma-4-12b-it-qat-q4-0',
        artifactType: CatalogArtifactType.model,
        displayName: 'Gemma QAT v2',
        version: 'rev2',
        buildId: 'rev2',
        platform: 'all',
        architecture: 'all',
        relativeInstallPath: 'models/gemma/rev2',
        installedAt: '2026-07-22T12:00:00Z',
        verifiedAt: '2026-07-22T12:00:00Z',
        sizeBytes: 6975879008,
        sha256: 'abc222',
        sourceKind: CatalogArtifactSourceKind.remoteHttps,
        status: InstallationStatus.verified,
      );

      var record = InstallationRecord.empty(updatedAt: '2026-07-22T10:00:00Z');
      record = record.upsertArtifact(desc1);
      record = record.upsertArtifact(desc2);

      final installations =
          record.findInstallationsForArtifact('gemma-4-12b-it-qat-q4-0');
      expect(installations.length, equals(2));

      final latest =
          record.findLatestVerifiedInstallation('gemma-4-12b-it-qat-q4-0');
      expect(latest, isNotNull);
      expect(latest!.installationId, equals('inst-gemma-v2'));
    });

    test(
        '6. Attivazione per installationId con esito tipizzato ActivationFailureReason',
        () async {
      const mockContent = 'Gemma QAT model content';
      final mockBytes = utf8.encode(mockContent);

      final manifest = CatalogManifest.initialDefault();
      final artifact = manifest.findArtifact('gemma-4-12b-it-qat-q4-0')!;

      final testArtifact = artifact.copyWith(
        sizeBytes: mockBytes.length,
        sha256: sha256.convert(mockBytes).toString().toLowerCase(),
      );

      httpClient.remoteFiles[artifact.downloadUri!] = mockBytes;

      final testManifest = CatalogManifest(
        schemaVersion: '1.0',
        catalogId: 'cat-test',
        generatedAt: '2026-07-22T18:00:00.000Z',
        artifacts: [testArtifact],
      );

      final consent = DownloadConsent.grantedFor(
        artifactId: 'gemma-4-12b-it-qat-q4-0',
        sourceUri: artifact.downloadUri!,
        expectedSizeBytes: mockBytes.length,
        operationId: 'op-prov-act',
      );

      final request = ProvisioningRequest(
        operationId: 'op-prov-act',
        catalogId: 'cat-test',
        artifactId: 'gemma-4-12b-it-qat-q4-0',
        downloadPolicy: ProvisioningDownloadPolicy.explicitConsent,
        consent: consent,
        expectedPlatform: 'windows',
        expectedArchitecture: 'x64',
      );

      final provRes = await coordinator.provisionArtifact(
        request: request,
        manifest: testManifest,
      );

      final actRes = await coordinator.activateInstallation(
        installationId: provRes.installationId!,
        operationId: 'op-act-1',
        modelRole: ModelActivationRole.actor,
      );

      expect(actRes.success, isTrue);

      final state = await coordinator.getActivationState();
      expect(state.activeModelInstallationId, equals(provRes.installationId));
    });
  });
}
