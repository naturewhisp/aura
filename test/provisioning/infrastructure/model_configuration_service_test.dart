import 'package:aura_core/aura_offline.dart';
import '../../provisioning/provisioning_test_helpers.dart';
import 'package:test/test.dart';

void main() {
  late MemoryProvisioningFileSystem fileSystem;
  late ProvisioningPathResolver pathResolver;
  late JsonModelConfigurationRepository configRepo;
  late JsonInstallationRecordRepository installRepo;
  late DefaultModelConfigurationService service;

  const storePath = r'C:\Users\Test\AppData\Local\AURA\store';

  setUp(() {
    fileSystem = MemoryProvisioningFileSystem();
    pathResolver = ProvisioningPathResolver(
      appManagedRoot: storePath,
      bundledRoot: r'C:\Program Files\AURA',
    );

    configRepo = JsonModelConfigurationRepository(
      storeDirectoryPath: storePath,
      fileSystem: fileSystem,
      lock: InMemoryProvisioningLock(),
    );

    installRepo = JsonInstallationRecordRepository(
      pathResolver: pathResolver,
      fileSystem: fileSystem,
      lock: InMemoryProvisioningLock(),
    );

    service = DefaultModelConfigurationService(
      configurationRepository: configRepo,
      installationRecordRepository: installRepo,
      fileSystem: fileSystem,
      pathResolver: pathResolver,
    );
  });

  group('Tranche 6.4f.3 — DefaultModelConfigurationService Tests', () {
    test(
        'bindActorModel con ManagedModelReference controlla l\'InstallationRecord e risolve relativeInstallPath',
        () async {
      const instId = 'inst_actor_99';
      const relPath = r'models\aura-actor-v1\1.0.0-b1';
      final record = InstallationRecord(
        updatedAt: DateTime.now().toUtc().toIso8601String(),
        installedArtifacts: [
          InstalledArtifactDescriptor(
            installationId: instId,
            artifactId: 'aura-actor-v1',
            displayName: 'Aura Actor Model',
            version: '1.0.0',
            buildId: 'b1',
            platform: 'windows',
            architecture: 'x64',
            relativeInstallPath: relPath,
            entryFileName: 'model.gguf',
            artifactType: CatalogArtifactType.model,
            sourceKind: CatalogArtifactSourceKind.remoteHttps,
            sizeBytes: 1024,
            sha256: 'abc',
            status: InstallationStatus.verified,
            verifiedAt: DateTime.now().toUtc().toIso8601String(),
            installedAt: DateTime.now().toUtc().toIso8601String(),
          ),
        ],
      );

      await installRepo.replaceRecord(record);
      final expectedPath = pathResolver.resolveAppManagedRelativePath(relPath);
      await fileSystem.writeBytes(
        '$expectedPath\\model.gguf',
        [1, 2, 3],
      );

      final result = await service.bindActorModel(
        ManagedModelReference(installationId: instId),
      );

      expect(result.isValid, isTrue);

      final current = await service.readRecord();
      expect(
        current.models.actor,
        equals(ManagedModelReference(installationId: instId)),
      );
    });

    test(
        'bindActorModel con ManagedModelReference rifiuta un artefatto che non è di tipo model',
        () async {
      const instId = 'inst_runtime_1';
      final record = InstallationRecord(
        updatedAt: DateTime.now().toUtc().toIso8601String(),
        installedArtifacts: [
          InstalledArtifactDescriptor(
            installationId: instId,
            artifactId: 'llama-server',
            displayName: 'Llama Server Runtime',
            version: '1.0.0',
            buildId: 'b1',
            platform: 'windows',
            architecture: 'x64',
            relativeInstallPath: r'runtimes\llama-server',
            entryFileName: 'llama-server.exe',
            artifactType: CatalogArtifactType.runtime,
            sourceKind: CatalogArtifactSourceKind.remoteHttps,
            sizeBytes: 1024,
            sha256: 'abc',
            status: InstallationStatus.verified,
            verifiedAt: DateTime.now().toUtc().toIso8601String(),
            installedAt: DateTime.now().toUtc().toIso8601String(),
          ),
        ],
      );

      await installRepo.replaceRecord(record);

      final result = await service.bindActorModel(
        ManagedModelReference(installationId: instId),
      );

      expect(result.isValid, isFalse);
      expect(result.errorMessage, contains('non è un modello'));
    });

    test(
        'bindActorModel con ExternalModelReference richiede il consenso informato',
        () async {
      const extPath = r'C:\GgufModels\custom_actor.gguf';
      await fileSystem.writeBytes(extPath, [1, 2, 3]);

      // Senza consenso
      final resultNoConsent = await service.bindActorModel(
        ExternalModelReference(absolutePath: extPath),
      );

      expect(resultNoConsent.isValid, isFalse);

      // Registriamo il consenso informato
      await service.recordExternalModelConsent();

      // Ora il binding deve avere successo
      final resultWithConsent = await service.bindActorModel(
        ExternalModelReference(absolutePath: extPath),
      );

      expect(resultWithConsent.isValid, isTrue);

      final current = await service.readRecord();
      expect(
        current.models.actor,
        equals(ExternalModelReference(absolutePath: extPath)),
      );
    });

    test(
        'bindEvaluatorModel rifiuta file esterni inesistenti o senza estensione .gguf',
        () async {
      await service.recordExternalModelConsent();

      final resultInvalidExt = await service.bindEvaluatorModel(
        ExternalModelReference(absolutePath: r'C:\Models\test.txt'),
      );
      expect(resultInvalidExt.isValid, isFalse);

      final resultMissing = await service.bindEvaluatorModel(
        ExternalModelReference(absolutePath: r'C:\Models\missing.gguf'),
      );
      expect(resultMissing.isValid, isFalse);
    });

    test(
        'scanExternalModelCandidates elenca i file .gguf non ricorsivamente nella directory',
        () async {
      await fileSystem.writeBytes(
          r'C:\Users\Test\AppData\Local\AURA\store\model1.gguf', [1, 2]);
      await fileSystem.writeBytes(
          r'C:\Users\Test\AppData\Local\AURA\store\model2.GGUF', [3, 4, 5]);
      await fileSystem.writeBytes(
          r'C:\Users\Test\AppData\Local\AURA\store\readme.txt', [6]);

      final candidates = await service.scanExternalModelCandidates();
      expect(candidates.length, equals(2));
      expect(candidates.map((c) => c.fileName), contains('model1.gguf'));
      expect(candidates.map((c) => c.fileName), contains('model2.GGUF'));
    });

    test('clearActorBinding e clearEvaluatorBinding azzerano i riferimenti',
        () async {
      const extPath = r'C:\GgufModels\custom_actor.gguf';
      await fileSystem.writeBytes(extPath, [1, 2, 3]);
      await service.recordExternalModelConsent();

      await service
          .bindActorModel(ExternalModelReference(absolutePath: extPath));
      expect((await service.readRecord()).models.actor, isNotNull);

      await service.clearActorBinding();
      expect((await service.readRecord()).models.actor, isNull);
    });
  });
}
