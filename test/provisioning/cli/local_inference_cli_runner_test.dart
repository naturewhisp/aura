import 'dart:convert';

import 'package:aura_core/aura_offline.dart';
import '../provisioning_test_helpers.dart';
import 'package:test/test.dart';

final class ExceptionThrowingLocalInferenceFacade
    implements LocalInferenceFacade {
  @override
  Future<LocalInferenceSnapshot> getSnapshot() {
    throw Exception('Simulated database access failure in getSnapshot');
  }

  @override
  Future<LocalInferencePreflightResult> runPreflight(
      {required PreflightDepth depth}) {
    throw Exception('Simulated failure in runPreflight');
  }

  @override
  Future<LlamaServerDetectionResult> detectRuntime() {
    throw Exception('Simulated failure in detectRuntime');
  }

  @override
  Future<List<ExternalModelCandidate>> scanExternalCandidates(
      {String? customPath}) {
    throw Exception('Simulated failure in scanExternalCandidates');
  }

  @override
  Future<List<InstalledArtifactDescriptor>> listManagedModels() {
    throw Exception('Simulated failure in listManagedModels');
  }
}

final class ExceptionThrowingSettingsFacade
    implements RuntimeModelSettingsFacade {
  @override
  Future<LlamaServerConfiguration> setRuntimeExecutable(String path) {
    throw Exception('Simulated error in setRuntimeExecutable');
  }

  @override
  Future<void> clearRuntimeExecutable() {
    throw Exception('Simulated error in clearRuntimeExecutable');
  }

  @override
  Future<ModelBindingValidationResult> bindActor(ConfiguredModelReference ref) {
    throw Exception('Simulated error in bindActor');
  }

  @override
  Future<void> clearActorBinding() {
    throw Exception('Simulated error in clearActorBinding');
  }

  @override
  Future<ModelBindingValidationResult> bindEvaluator(
      ConfiguredModelReference ref) {
    throw Exception('Simulated error in bindEvaluator');
  }

  @override
  Future<void> clearEvaluatorBinding() {
    throw Exception('Simulated error in clearEvaluatorBinding');
  }

  @override
  Future<ExternalModelConsent> recordConsent() {
    throw Exception('Simulated error in recordConsent');
  }

  @override
  Future<bool> isConsentValid() {
    throw Exception('Simulated error in isConsentValid');
  }

  @override
  Future<InstallationAssistance> getWinGetAssistance(
      {String? customPackageId}) {
    throw Exception('Simulated error in getWinGetAssistance');
  }

  @override
  Future<bool> isWinGetAvailable() {
    throw Exception('Simulated error in isWinGetAvailable');
  }
}

void main() {
  group('Tranche 6.4f.7-fix — LocalInferenceCliRunner Extended Tests', () {
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
        expect(json['exitCode'], equals(3));
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

      test('runtime set rifiuta argomenti extra posizionali con exit code 2',
          () async {
        final res = await cliRunner
            .runRuntimeCommand(['set', r'C:\llama.exe', 'extra']);
        expect(res.exitCode, equals(2));
        expect(res.outputText, contains('Troppi argomenti'));
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
          'model bind --role actor --external senza consenso restituisce exit code 6 via ModelBindingFailure.consentRequired',
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

      test(
          'model bind con argomenti confliggenti o flag duplicati restituisce exit code 2',
          () async {
        final conflictRes = await cliRunner.runModelCommand(
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
        expect(conflictRes.exitCode, equals(2));
        expect(conflictRes.outputText, contains('simultaneamente'));

        final dupRes = await cliRunner.runModelCommand(
          [
            'bind',
            '--role',
            'actor',
            '--role',
            'evaluator',
            '--managed',
            'id1'
          ],
        );
        expect(dupRes.exitCode, equals(2));
        expect(dupRes.outputText, contains('più di una volta'));
      });

      test('model bind con valore mancante dopo flag restituisce exit code 2',
          () async {
        final res = await cliRunner.runModelCommand(['bind', '--role']);
        expect(res.exitCode, equals(2));
        expect(res.outputText, contains('Valore mancante'));
      });

      test('model bind con flag non riconosciuto restituisce exit code 2',
          () async {
        final res = await cliRunner
            .runModelCommand(['bind', '--role', 'actor', '--unknown', 'val']);
        expect(res.exitCode, equals(2));
        expect(res.outputText, contains('non riconosciuto'));
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
        expect(res.exitCode, equals(4));
        final json = jsonDecode(res.outputText) as Map<String, dynamic>;
        expect(json['ok'], isFalse);
        expect(json['code'], equals('runtimeNotConfigured'));
      });

      test(
          'preflight probe esegue la verifica dinamica direttamente via facade',
          () async {
        final res = await cliRunner.runPreflightCommand(['probe']);
        expect(res.exitCode, equals(4));
        expect(res.outputText, contains('PREFLIGHT FAILED [RUNTIMEPROBE]'));
      });
    });

    group('Gestione Eccezioni e Robustezza Runner (6.4f.7-fix Findings 2 & 3)',
        () {
      test('consent status cattura eccezioni interne e restituisce exit code 1',
          () async {
        final throwingRunner = LocalInferenceCliRunner(
          inferenceFacade: ExceptionThrowingLocalInferenceFacade(),
          settingsFacade: ExceptionThrowingSettingsFacade(),
          firstRunFacade: firstRunFacade,
        );

        final res = await throwingRunner
            .runModelCommand(['consent', 'status'], jsonOutput: true);
        expect(res.exitCode, equals(1));
        final json = jsonDecode(res.outputText) as Map<String, dynamic>;
        expect(json['ok'], isFalse);
        expect(json['code'], equals('consent_operation_failed'));
      });

      test('consent accept cattura eccezioni interne e restituisce exit code 1',
          () async {
        final throwingRunner = LocalInferenceCliRunner(
          inferenceFacade: inferenceFacade,
          settingsFacade: ExceptionThrowingSettingsFacade(),
          firstRunFacade: firstRunFacade,
        );

        final res = await throwingRunner
            .runModelCommand(['consent', 'accept'], jsonOutput: true);
        expect(res.exitCode, equals(1));
        final json = jsonDecode(res.outputText) as Map<String, dynamic>;
        expect(json['ok'], isFalse);
        expect(json['code'], equals('consent_operation_failed'));
      });

      test('tutti gli output JSON contengono ok, exitCode, code e message',
          () async {
        final res =
            await cliRunner.runRuntimeCommand(['status'], jsonOutput: true);
        final json = jsonDecode(res.outputText) as Map<String, dynamic>;
        expect(json.containsKey('ok'), isTrue);
        expect(json.containsKey('exitCode'), isTrue);
        expect(json.containsKey('code'), isTrue);
        expect(json.containsKey('message'), isTrue);
      });
    });
  });
}
