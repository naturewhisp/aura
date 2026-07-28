import 'dart:convert';

import 'package:aura_core/aura_offline.dart';
import '../provisioning_test_helpers.dart';
import 'package:test/test.dart';

void main() {
  group('Tranche 6.4f.7 — LocalInferenceCliRunner Tests', () {
    late MemoryProvisioningFileSystem fileSystem;
    late ProvisioningPathResolver pathResolver;
    late JsonModelConfigurationRepository configRepo;
    late JsonInstallationRecordRepository installRepo;
    late DefaultLlamaServerDependencyService dependencyService;
    late DefaultModelConfigurationService modelService;
    late DefaultLocalInferencePreflightEngine preflightEngine;

    late DefaultLocalInferenceFacade inferenceFacade;
    late DefaultRuntimeModelSettingsFacade settingsFacade;
    late DefaultFirstRunModelSetupFacade firstRunFacade;
    late LocalInferenceCliRunner cliRunner;

    setUp(() {
      fileSystem = MemoryProvisioningFileSystem();
      pathResolver = ProvisioningPathResolver(
        appManagedRoot: r'C:\AppRoot',
        bundledRoot: r'C:\Program Files\AURA',
      );

      configRepo = JsonModelConfigurationRepository(
        storeDirectoryPath: r'C:\AppRoot',
        fileSystem: fileSystem,
        lock: InMemoryProvisioningLock(),
      );

      installRepo = JsonInstallationRecordRepository(
        pathResolver: pathResolver,
        fileSystem: fileSystem,
        lock: InMemoryProvisioningLock(),
      );

      dependencyService = DefaultLlamaServerDependencyService(
        configurationRepository: configRepo,
        fileSystem: fileSystem,
        pathResolver: pathResolver,
      );

      modelService = DefaultModelConfigurationService(
        configurationRepository: configRepo,
        installationRecordRepository: installRepo,
        fileSystem: fileSystem,
        pathResolver: pathResolver,
      );

      preflightEngine = DefaultLocalInferencePreflightEngine(
        configurationRepository: configRepo,
        installationRecordRepository: installRepo,
        dependencyService: dependencyService,
        fileSystem: fileSystem,
        pathResolver: pathResolver,
      );

      inferenceFacade = DefaultLocalInferenceFacade(
        preflightEngine: preflightEngine,
        dependencyService: dependencyService,
        modelConfigurationService: modelService,
        installationRecordRepository: installRepo,
      );

      settingsFacade = DefaultRuntimeModelSettingsFacade(
        dependencyService: dependencyService,
        modelService: modelService,
        winGetAdapter: WinGetDependencyAdapter(),
      );

      firstRunFacade = DefaultFirstRunModelSetupFacade(
        preflightEngine: preflightEngine,
        dependencyService: dependencyService,
        modelService: modelService,
      );

      cliRunner = LocalInferenceCliRunner(
        inferenceFacade: inferenceFacade,
        settingsFacade: settingsFacade,
        firstRunFacade: firstRunFacade,
      );
    });

    group('Comando aura runtime', () {
      test('runtime status non configurato restituisce exit code 3', () async {
        final res = await cliRunner.runRuntimeCommand(['status']);
        expect(res.exitCode, equals(3));
        expect(res.outputText, contains('Runtime non configurato'));
      });

      test('runtime status --json restituisce JSON strutturato', () async {
        final res =
            await cliRunner.runRuntimeCommand(['status'], jsonOutput: true);
        expect(res.exitCode, equals(3));
        final json = jsonDecode(res.outputText) as Map<String, dynamic>;
        expect(json['ok'], isFalse);
        expect(json['code'], equals('runtime_unconfigured'));
      });

      test('runtime set imposta percorso valido', () async {
        const path = r'C:\llama.cpp\llama-server.exe';
        fileSystem.writeBytes(path, [1, 2, 3]);

        final res = await cliRunner.runRuntimeCommand(['set', path]);
        expect(res.exitCode, equals(0));
        expect(res.outputText, contains('Eseguibile llama-server configurato'));

        final statusRes = await cliRunner.runRuntimeCommand(['status']);
        expect(statusRes.exitCode, equals(0));
        expect(statusRes.outputText, contains(path));
      });

      test('runtime clear rimuove configurazione', () async {
        const path = r'C:\llama.cpp\llama-server.exe';
        fileSystem.writeBytes(path, [1, 2, 3]);
        await cliRunner.runRuntimeCommand(['set', path]);

        final clearRes = await cliRunner.runRuntimeCommand(['clear']);
        expect(clearRes.exitCode, equals(0));

        final statusRes = await cliRunner.runRuntimeCommand(['status']);
        expect(statusRes.exitCode, equals(3));
      });
    });

    group('Comando aura model', () {
      test('model status incompleto restituisce exit code 3', () async {
        final res = await cliRunner.runModelCommand(['status']);
        expect(res.exitCode, equals(3));
        expect(res.outputText, contains('NON CONFIGURATO'));
      });

      test('model list ordina deterministicamente i modelli gestiti', () async {
        final currentRecord = await installRepo.readRecord();
        final updatedRecord = currentRecord.copyWith(
          installedArtifacts: [
            InstalledArtifactDescriptor(
              installationId: 'inst-b',
              artifactId: 'model-b',
              displayName: 'Beta Model',
              version: '1.0.0',
              buildId: 'b1',
              platform: 'windows',
              architecture: 'x64',
              relativeInstallPath: r'models\beta\beta.gguf',
              artifactType: CatalogArtifactType.model,
              sourceKind: CatalogArtifactSourceKind.remoteHttps,
              sizeBytes: 1024,
              sha256: 'sha-b',
              installedAt: DateTime.now().toIso8601String(),
              status: InstallationStatus.verified,
              verifiedAt: DateTime.now().toIso8601String(),
            ),
            InstalledArtifactDescriptor(
              installationId: 'inst-a',
              artifactId: 'model-a',
              displayName: 'Alpha Model',
              version: '2.0.0',
              buildId: 'b2',
              platform: 'windows',
              architecture: 'x64',
              relativeInstallPath: r'models\alpha\alpha.gguf',
              artifactType: CatalogArtifactType.model,
              sourceKind: CatalogArtifactSourceKind.remoteHttps,
              sizeBytes: 2048,
              sha256: 'sha-a',
              installedAt: DateTime.now().toIso8601String(),
              status: InstallationStatus.verified,
              verifiedAt: DateTime.now().toIso8601String(),
            ),
          ],
        );
        await installRepo.writeRecord(updatedRecord);

        final res = await cliRunner.runModelCommand(['list'], jsonOutput: true);
        expect(res.exitCode, equals(0));

        final json = jsonDecode(res.outputText) as Map<String, dynamic>;
        expect(json['count'], equals(2));
        final models = json['models'] as List;
        expect(models[0]['displayName'], equals('Alpha Model'));
        expect(models[1]['displayName'], equals('Beta Model'));
      });

      test(
          'model bind --role actor --external senza consenso restituisce exit code 6',
          () async {
        const modelPath = r'C:\Models\actor.gguf';
        fileSystem.writeBytes(modelPath, [10, 20]);

        final res = await cliRunner.runModelCommand(
          ['bind', '--role', 'actor', '--external', modelPath],
          jsonOutput: true,
        );

        expect(res.exitCode, equals(6));
        final json = jsonDecode(res.outputText) as Map<String, dynamic>;
        expect(json['code'], equals('external_model_consent_required'));
        expect(json['role'], equals('actor'));
      });

      test('model consent accept registra il consenso e permette il binding',
          () async {
        const modelPath = r'C:\Models\actor.gguf';
        fileSystem.writeBytes(modelPath, [10, 20]);

        final acceptRes =
            await cliRunner.runModelCommand(['consent', 'accept']);
        expect(acceptRes.exitCode, equals(0));

        final bindRes = await cliRunner.runModelCommand(
          ['bind', '--role', 'actor', '--external', modelPath],
        );
        expect(bindRes.exitCode, equals(0));
      });

      test('model bind con argomenti confliggenti restituisce exit code 2',
          () async {
        final res = await cliRunner.runModelCommand(
          [
            'bind',
            '--role',
            'actor',
            '--managed',
            'id1',
            '--external',
            r'C:\path.gguf'
          ],
        );
        expect(res.exitCode, equals(2));
        expect(res.outputText, contains('simultaneamente'));
      });

      test('model clear --role actor rimuove l\'associazione', () async {
        const modelPath = r'C:\Models\actor.gguf';
        fileSystem.writeBytes(modelPath, [10, 20]);
        await cliRunner.runModelCommand(['consent', 'accept']);
        await cliRunner.runModelCommand(
            ['bind', '--role', 'actor', '--external', modelPath]);

        final clearRes =
            await cliRunner.runModelCommand(['clear', '--role', 'actor']);
        expect(clearRes.exitCode, equals(0));

        final statusRes =
            await cliRunner.runModelCommand(['status'], jsonOutput: true);
        final json = jsonDecode(statusRes.outputText) as Map<String, dynamic>;
        expect(json['actor'], isNull);
      });
    });

    group('Comando aura preflight', () {
      test('preflight quick senza configurazione restituisce errore tipizzato',
          () async {
        final res =
            await cliRunner.runPreflightCommand(['quick'], jsonOutput: true);
        expect(res.exitCode, equals(4)); // runtime missing
        final json = jsonDecode(res.outputText) as Map<String, dynamic>;
        expect(json['ok'], isFalse);
        expect(json['code'], equals('runtimeNotConfigured'));
      });

      test('preflight probe esegue la verifica dinamica', () async {
        final res = await cliRunner.runPreflightCommand(['probe']);
        expect(res.exitCode, equals(4));
        expect(res.outputText, contains('PREFLIGHT FAILED [RUNTIMEPROBE]'));
      });
    });
  });
}
