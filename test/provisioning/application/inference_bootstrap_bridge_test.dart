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
  });
}
