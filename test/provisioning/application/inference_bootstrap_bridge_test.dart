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
      dataRootPath = '${tempDir.path}\\app_managed';
      bundledRootPath = '${tempDir.path}\\bundled';
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
      final fakeExe = File('$dataRootPath\\llama-server.exe');
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
      final fakeExe = File('$dataRootPath\\llama-server.exe');
      await fakeExe.writeAsString('fake binary');

      final fakeActor = File('$dataRootPath\\actor.gguf');
      await fakeActor.writeAsString('fake model actor');

      final fakeEvaluator = File('$dataRootPath\\evaluator.gguf');
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
          'computeExecutionBudget adatta i thread su CPU con core ridotti (8, 4, 2 core)',
          () {
        final budget8 = InferenceBootstrapBridge.computeExecutionBudget(
          acceleration: RuntimeAcceleration.cpu,
          totalProcessors: 8,
        );
        expect(budget8.gpuLayers, equals(0));
        expect(budget8.batchSize, equals(256));
        expect(budget8.actorThreads, equals(4));
        expect(budget8.evaluatorThreads, equals(2));

        final budget4 = InferenceBootstrapBridge.computeExecutionBudget(
          acceleration: RuntimeAcceleration.cpu,
          totalProcessors: 4,
        );
        expect(budget4.gpuLayers, equals(0));
        expect(budget4.batchSize, equals(256));
        expect(budget4.actorThreads, equals(2));
        expect(budget4.evaluatorThreads, equals(1));

        final budget2 = InferenceBootstrapBridge.computeExecutionBudget(
          acceleration: RuntimeAcceleration.cpu,
          totalProcessors: 2,
        );
        expect(budget2.gpuLayers, equals(0));
        expect(budget2.batchSize, equals(256));
        expect(budget2.actorThreads, equals(1));
        expect(budget2.evaluatorThreads, equals(1));
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
        final fakeExe = File('$dataRootPath\\llama-server.exe');
        await fakeExe.writeAsString('fake binary');
        final fakeActor = File('$dataRootPath\\actor.gguf');
        await fakeActor.writeAsString('fake model');
        final fakeEvaluator = File('$dataRootPath\\evaluator.gguf');
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
  });
}
