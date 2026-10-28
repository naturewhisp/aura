import 'dart:io';

import 'package:aura_core/aura_offline.dart';
import 'package:test/test.dart';

void main() {
  group('InferenceBootstrapBridge', () {
    late Directory tempDir;
    late String dataRootPath;
    late String bundledRootPath;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('aura_bridge_test_');
      final sep = Platform.pathSeparator;
      dataRootPath = '${tempDir.path}${sep}app_managed';
      bundledRootPath = '${tempDir.path}${sep}bundled';
      await Directory(dataRootPath).create(recursive: true);
      await Directory(bundledRootPath).create(recursive: true);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
        'resolve restituisce InvalidResolution quando nessun runtime è configurato',
        () async {
      final bridge = InferenceBootstrapBridge(
        environmentFactory: () => AuraCliEnvironment(
          appManagedRoot: dataRootPath,
          bundledRoot: bundledRootPath,
        ),
      );

      final resolution = await bridge.resolve();

      expect(resolution, isA<InvalidResolution>());
      final invalid = resolution as InvalidResolution;
      expect(
        invalid.reason,
        equals(InferenceBootstrapFailureReason.incompleteModelConfiguration),
      );
      expect(invalid.sanitizedMessage, contains('llama-server'));
    });

    test(
        'resolve restituisce InvalidResolution se i modelli non sono associati',
        () async {
      // Scrive una configurazione runtime valida ma senza modelli
      final configRepo = JsonModelConfigurationRepository(
        storeDirectoryPath: dataRootPath,
        fileSystem: const LocalProvisioningFileSystem(),
        lock: FileBasedProvisioningLock(lockDirectory: dataRootPath),
      );

      // Crea un file eseguibile finto
      final fakeExe =
          File('$dataRootPath${Platform.pathSeparator}llama-server.exe');
      await fakeExe.writeAsString('fake binary');

      await configRepo.replaceRecord(
        ModelConfigurationRecord(
          schemaVersion: 1,
          runtime: LlamaServerConfiguration(
            executablePath: fakeExe.path,
            validationStatus: LlamaServerValidationStatus.valid,
          ),
        ),
      );

      final bridge = InferenceBootstrapBridge(
        environmentFactory: () => AuraCliEnvironment(
          appManagedRoot: dataRootPath,
          bundledRoot: bundledRootPath,
        ),
      );

      final resolution = await bridge.resolve();

      expect(resolution, isA<InvalidResolution>());
      final invalid = resolution as InvalidResolution;
      expect(
        invalid.reason,
        equals(InferenceBootstrapFailureReason.incompleteModelConfiguration),
      );
    });

    test(
        'resolve restituisce ManagedDualResolution quando runtime e modelli actor/evaluator sono configurati',
        () async {
      final sep = Platform.pathSeparator;
      final fakeExe = File('$dataRootPath${sep}llama-server.exe');
      await fakeExe.writeAsString('fake binary');

      final fakeActor = File('$dataRootPath${sep}actor.gguf');
      await fakeActor.writeAsString('fake model actor');

      final fakeEvaluator = File('$dataRootPath${sep}evaluator.gguf');
      await fakeEvaluator.writeAsString('fake model evaluator');

      final configRepo = JsonModelConfigurationRepository(
        storeDirectoryPath: dataRootPath,
        fileSystem: const LocalProvisioningFileSystem(),
        lock: FileBasedProvisioningLock(lockDirectory: dataRootPath),
      );

      await configRepo.replaceRecord(
        ModelConfigurationRecord(
          schemaVersion: 1,
          runtime: LlamaServerConfiguration(
            executablePath: fakeExe.path,
            validationStatus: LlamaServerValidationStatus.valid,
          ),
          models: ModelRoleConfiguration(
            actor: ExternalModelReference(absolutePath: fakeActor.path),
            evaluator: ExternalModelReference(absolutePath: fakeEvaluator.path),
          ),
          externalModelConsent: ExternalModelConsent.now(),
        ),
      );

      final bridge = InferenceBootstrapBridge(
        environmentFactory: () => AuraCliEnvironment(
          appManagedRoot: dataRootPath,
          bundledRoot: bundledRootPath,
        ),
      );

      final resolution = await bridge.resolve();

      expect(resolution, isA<ManagedDualResolution>());
      final dual = resolution as ManagedDualResolution;
      expect(dual.topology.actor.role, equals(InferenceModelRole.actor));
      expect(dual.topology.actor.serverConfiguration.executablePath,
          equals(fakeExe.path));
      expect(dual.topology.actor.serverConfiguration.modelPath,
          equals(fakeActor.path));
      expect(
          dual.topology.evaluator.role, equals(InferenceModelRole.evaluator));
      expect(dual.topology.evaluator.serverConfiguration.modelPath,
          equals(fakeEvaluator.path));
    });

    group('CPU-Only & Execution Budgeting Optimization', () {
      test(
          'computeExecutionBudget riserva 2 core per il sistema su CPU a 16 core e imposta gpuLayers a 0',
          () {
        final budget = InferenceBootstrapBridge.computeExecutionBudget(
          acceleration: RuntimeAcceleration.cpu,
          totalProcessors: 16,
        );

        expect(budget.gpuLayers, equals(0));
        expect(budget.batchSize, equals(256));
        expect(budget.actorThreads, equals(8));
        expect(budget.evaluatorThreads, equals(6));
        expect(budget.actorThreads + budget.evaluatorThreads, equals(14));
        expect(
            budget.actorStartupTimeout, equals(const Duration(seconds: 120)));
        expect(budget.evaluatorStartupTimeout,
            equals(const Duration(seconds: 90)));
      });

      test(
          'computeExecutionBudget adatta i thread secondo le fasce esplicite (>=6, 4-5, <=3 core)',
          () {
        // Fascia >= 6 core: riserva 2 core
        final budget8 = InferenceBootstrapBridge.computeExecutionBudget(
          acceleration: RuntimeAcceleration.cpu,
          totalProcessors: 8,
        );
        expect(budget8.gpuLayers, equals(0));
        expect(budget8.batchSize, equals(256));
        expect(budget8.actorThreads, equals(4));
        expect(budget8.evaluatorThreads, equals(2));

        final budget6 = InferenceBootstrapBridge.computeExecutionBudget(
          acceleration: RuntimeAcceleration.cpu,
          totalProcessors: 6,
        );
        expect(budget6.actorThreads, equals(2));
        expect(budget6.evaluatorThreads, equals(2));

        // Fascia 4..5 core: riserva 1 core
        final budget5 = InferenceBootstrapBridge.computeExecutionBudget(
          acceleration: RuntimeAcceleration.cpu,
          totalProcessors: 5,
        );
        expect(budget5.actorThreads, equals(2));
        expect(budget5.evaluatorThreads, equals(2));

        final budget4 = InferenceBootstrapBridge.computeExecutionBudget(
          acceleration: RuntimeAcceleration.cpu,
          totalProcessors: 4,
        );
        expect(budget4.actorThreads, equals(2));
        expect(budget4.evaluatorThreads, equals(1));

        // Fascia <= 3 core: modalità vincolata (constrained, intentional minimal oversubscription)
        final budget3 = InferenceBootstrapBridge.computeExecutionBudget(
          acceleration: RuntimeAcceleration.cpu,
          totalProcessors: 3,
        );
        expect(budget3.actorThreads, equals(1));
        expect(budget3.evaluatorThreads, equals(1));

        final budget2 = InferenceBootstrapBridge.computeExecutionBudget(
          acceleration: RuntimeAcceleration.cpu,
          totalProcessors: 2,
        );
        expect(budget2.actorThreads, equals(1));
        expect(budget2.evaluatorThreads, equals(1));

        final budget1 = InferenceBootstrapBridge.computeExecutionBudget(
          acceleration: RuntimeAcceleration.cpu,
          totalProcessors: 1,
        );
        expect(budget1.actorThreads, equals(1));
        expect(budget1.evaluatorThreads, equals(1));
      });

      test(
          'computeExecutionBudget su GPU CUDA/Vulkan imposta gpuLayers a 99 e batchSize null',
          () {
        final budgetCuda = InferenceBootstrapBridge.computeExecutionBudget(
          acceleration: RuntimeAcceleration.cuda,
          totalProcessors: 16,
        );
        expect(budgetCuda.gpuLayers, equals(99));
        expect(budgetCuda.batchSize, isNull);
        expect(budgetCuda.actorThreads, equals(4));
        expect(budgetCuda.evaluatorThreads, equals(2));
        expect(budgetCuda.actorStartupTimeout,
            equals(const Duration(seconds: 60)));
        expect(budgetCuda.evaluatorStartupTimeout,
            equals(const Duration(seconds: 45)));

        final budgetVulkan = InferenceBootstrapBridge.computeExecutionBudget(
          acceleration: RuntimeAcceleration.vulkan,
          totalProcessors: 8,
        );
        expect(budgetVulkan.gpuLayers, equals(99));
        expect(budgetVulkan.batchSize, isNull);
        expect(budgetVulkan.actorThreads, equals(4));
        expect(budgetVulkan.evaluatorThreads, equals(2));
      });

      test(
          'resolve applica parametri CPU-only completi quando il runtime configurato è CPU',
          () async {
        final sep = Platform.pathSeparator;
        final fakeExe = File('$dataRootPath${sep}llama-server.exe');
        await fakeExe.writeAsString('fake binary');
        final fakeActor = File('$dataRootPath${sep}actor.gguf');
        await fakeActor.writeAsString('fake model');
        final fakeEvaluator = File('$dataRootPath${sep}evaluator.gguf');
        await fakeEvaluator.writeAsString('fake model');

        final configRepo = JsonModelConfigurationRepository(
          storeDirectoryPath: dataRootPath,
          fileSystem: const LocalProvisioningFileSystem(),
          lock: FileBasedProvisioningLock(lockDirectory: dataRootPath),
        );

        await configRepo.replaceRecord(
          ModelConfigurationRecord(
            schemaVersion: 1,
            runtime: LlamaServerConfiguration(
              executablePath: fakeExe.path,
              validationStatus: LlamaServerValidationStatus.valid,
              acceleration: RuntimeAcceleration.cpu,
            ),
            models: ModelRoleConfiguration(
              actor: ExternalModelReference(absolutePath: fakeActor.path),
              evaluator:
                  ExternalModelReference(absolutePath: fakeEvaluator.path),
            ),
            externalModelConsent: ExternalModelConsent.now(),
          ),
        );

        final bridge = InferenceBootstrapBridge(
          environmentFactory: () => AuraCliEnvironment(
            appManagedRoot: dataRootPath,
            bundledRoot: bundledRootPath,
          ),
        );

        final resolution = await bridge.resolve();
        expect(resolution, isA<ManagedDualResolution>());
        final dual = resolution as ManagedDualResolution;

        // Verifica configurazione CPU-only
        expect(dual.topology.actor.serverConfiguration.gpuLayers, equals(0));
        expect(
            dual.topology.evaluator.serverConfiguration.gpuLayers, equals(0));
        expect(dual.topology.actor.serverConfiguration.batchSize, equals(256));
        expect(
            dual.topology.evaluator.serverConfiguration.batchSize, equals(256));
        expect(dual.topology.actor.serverConfiguration.threads, isNotNull);
        expect(dual.topology.evaluator.serverConfiguration.threads, isNotNull);
        expect(dual.topology.actor.serverConfiguration.startupTimeout,
            equals(const Duration(seconds: 120)));
        expect(dual.topology.evaluator.serverConfiguration.startupTimeout,
            equals(const Duration(seconds: 90)));
      });
    });

    group('Osservazioni di runtime per la provenance', () {
      test(
          'resolve espone accelerazione effettiva, build llama.cpp e context size espliciti',
          () async {
        final sep = Platform.pathSeparator;
        final fakeExe = File('$dataRootPath${sep}llama-server.exe');
        await fakeExe.writeAsString('fake binary');
        final fakeActor = File('$dataRootPath${sep}actor.gguf');
        await fakeActor.writeAsString('fake model');
        final fakeEvaluator = File('$dataRootPath${sep}evaluator.gguf');
        await fakeEvaluator.writeAsString('fake model');

        final configRepo = JsonModelConfigurationRepository(
          storeDirectoryPath: dataRootPath,
          fileSystem: const LocalProvisioningFileSystem(),
          lock: FileBasedProvisioningLock(lockDirectory: dataRootPath),
        );

        await configRepo.replaceRecord(
          ModelConfigurationRecord(
            schemaVersion: 1,
            runtime: LlamaServerConfiguration(
              executablePath: fakeExe.path,
              validationStatus: LlamaServerValidationStatus.valid,
              acceleration: RuntimeAcceleration.cpu,
              detectedVersion: 'b6543',
            ),
            models: ModelRoleConfiguration(
              actor: ExternalModelReference(absolutePath: fakeActor.path),
              evaluator:
                  ExternalModelReference(absolutePath: fakeEvaluator.path),
            ),
            externalModelConsent: ExternalModelConsent.now(),
          ),
        );

        final bridge = InferenceBootstrapBridge(
          environmentFactory: () => AuraCliEnvironment(
            appManagedRoot: dataRootPath,
            bundledRoot: bundledRootPath,
          ),
        );

        final dual = await bridge.resolve() as ManagedDualResolution;

        expect(dual.runtimeAcceleration, equals(RuntimeAcceleration.cpu));
        expect(dual.llamaCppBuild, equals('b6543'));
        expect(dual.topology.actor.serverConfiguration.contextSize,
            equals(InferenceBootstrapBridge.actorContextSize));
        expect(dual.topology.evaluator.serverConfiguration.contextSize,
            equals(InferenceBootstrapBridge.evaluatorContextSize));
        // Modelli esterni: nessuna provenance di catalogo né quantizzazione presunta.
        expect(dual.topology.actor.serverConfiguration.provenance, isNull);
      });

      test(
          'la quantizzazione dei modelli managed è attribuita solo per SHA-256 coincidente col catalogo',
          () async {
        final sep = Platform.pathSeparator;
        final env = AuraCliEnvironment(
          appManagedRoot: dataRootPath,
          bundledRoot: bundledRootPath,
        );
        final services = LocalInferenceServiceProvider.create(environment: env);

        final fakeExe = File('$dataRootPath${sep}llama-server.exe');
        await fakeExe.writeAsString('fake binary');

        final catalogActor = CatalogManifest.initialDefault()
            .artifacts
            .firstWhere((a) => a.quantization == 'Q4_0');
        final now = DateTime.now().toUtc().toIso8601String();

        InstalledArtifactDescriptor descriptor(
          String installationId,
          String relativePath,
          String sha256,
        ) =>
            InstalledArtifactDescriptor(
              installationId: installationId,
              artifactId: installationId,
              displayName: installationId,
              version: '1.0.0',
              buildId: 'b1',
              platform: 'all',
              architecture: 'all',
              relativeInstallPath: relativePath,
              entryFileName: 'model.gguf',
              artifactType: CatalogArtifactType.model,
              sourceKind: CatalogArtifactSourceKind.remoteHttps,
              sizeBytes: 4,
              sha256: sha256,
              status: InstallationStatus.verified,
              verifiedAt: now,
              installedAt: now,
            );

        await services.installationRecordRepository.replaceRecord(
          InstallationRecord(
            updatedAt: now,
            installedArtifacts: [
              descriptor(
                  'inst_actor', 'models${sep}actor', catalogActor.sha256),
              descriptor('inst_eval', 'models${sep}eval', 'a' * 64),
            ],
          ),
        );
        for (final rel in ['models${sep}actor', 'models${sep}eval']) {
          final dir = services.pathResolver.resolveAppManagedRelativePath(rel);
          await Directory(dir).create(recursive: true);
          await File('$dir${sep}model.gguf').writeAsBytes([1, 2, 3, 4]);
        }

        final configRepo = JsonModelConfigurationRepository(
          storeDirectoryPath: dataRootPath,
          fileSystem: const LocalProvisioningFileSystem(),
          lock: FileBasedProvisioningLock(lockDirectory: dataRootPath),
        );
        await configRepo.replaceRecord(
          ModelConfigurationRecord(
            schemaVersion: 1,
            runtime: LlamaServerConfiguration(
              executablePath: fakeExe.path,
              validationStatus: LlamaServerValidationStatus.valid,
            ),
            models: ModelRoleConfiguration(
              actor: ManagedModelReference(installationId: 'inst_actor'),
              evaluator: ManagedModelReference(installationId: 'inst_eval'),
            ),
          ),
        );

        final dual = await InferenceBootstrapBridge(services: services)
            .resolve() as ManagedDualResolution;

        final actorProvenance =
            dual.topology.actor.serverConfiguration.provenance!;
        expect(actorProvenance.quantization, equals('Q4_0'));
        expect(actorProvenance.expectedSha256, equals(catalogActor.sha256));

        final evaluatorProvenance =
            dual.topology.evaluator.serverConfiguration.provenance!;
        expect(evaluatorProvenance.quantization, isNull);
      });
    });
  });
}
