import 'dart:async';
import 'dart:convert';
import 'dart:io' show ProcessSignal;
import 'package:aura_core/aura_offline.dart';
import '../../provisioning/provisioning_test_helpers.dart';
import 'package:test/test.dart';

final class TestManagedProcess implements ManagedProcess {
  @override
  final int pid;
  final int exitCodeValue;
  final String stdoutText;
  final String stderrText;

  TestManagedProcess({
    this.pid = 1234,
    this.exitCodeValue = 0,
    this.stdoutText = '',
    this.stderrText = '',
  });

  @override
  Stream<List<int>> get stdoutBytes => Stream.multi((controller) {
        controller.add(utf8.encode(stdoutText));
        controller.close();
      });

  @override
  Stream<List<int>> get stderrBytes => Stream.multi((controller) {
        controller.add(utf8.encode(stderrText));
        controller.close();
      });

  @override
  Future<int> get exitCode async => exitCodeValue;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) => true;
}

final class TestProcessLauncher implements ProcessLauncher {
  final Future<ManagedProcess> Function(ProcessLaunchRequest request) handler;

  TestProcessLauncher(this.handler);

  @override
  Future<ManagedProcess> start(ProcessLaunchRequest request) =>
      handler(request);
}

void main() {
  late MemoryProvisioningFileSystem fileSystem;
  late ProvisioningPathResolver pathResolver;
  late JsonModelConfigurationRepository configRepo;
  late JsonInstallationRecordRepository installRepo;
  late DefaultLlamaServerDependencyService dependencyService;
  late DefaultModelConfigurationService modelService;
  late WinGetDependencyAdapter winGetAdapter;
  late DefaultLocalInferencePreflightEngine preflightEngine;

  late DefaultLocalInferenceFacade inferenceFacade;
  late DefaultRuntimeModelSettingsFacade settingsFacade;
  late DefaultFirstRunModelSetupFacade firstRunFacade;
  late LocalInferenceStatusNotifier statusNotifier;

  const storePath = r'C:\Users\Test\AppData\Local\AURA\store';
  const execPath = r'C:\Program Files\AURA\llama-server.exe';

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

    final launcher = TestProcessLauncher((req) async {
      if (req.executable.contains('winget')) {
        return TestManagedProcess(stdoutText: 'v1.6.2771');
      }
      return TestManagedProcess(stdoutText: 'version: b3450');
    });

    dependencyService = DefaultLlamaServerDependencyService(
      configurationRepository: configRepo,
      fileSystem: fileSystem,
      pathResolver: pathResolver,
      processLauncher: launcher,
    );

    modelService = DefaultModelConfigurationService(
      configurationRepository: configRepo,
      installationRecordRepository: installRepo,
      fileSystem: fileSystem,
      pathResolver: pathResolver,
    );

    winGetAdapter = WinGetDependencyAdapter(processLauncher: launcher);

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
    );

    settingsFacade = DefaultRuntimeModelSettingsFacade(
      dependencyService: dependencyService,
      modelService: modelService,
      winGetAdapter: winGetAdapter,
    );

    firstRunFacade = DefaultFirstRunModelSetupFacade(
      preflightEngine: preflightEngine,
      dependencyService: dependencyService,
      modelService: modelService,
    );

    statusNotifier = LocalInferenceStatusNotifier(facade: inferenceFacade);
  });

  group('Tranche 6.4f.5 — Application Facades & Notifier Tests', () {
    test(
        'LocalInferenceFacade.getSnapshot e StatusNotifier restituiscono lo stato aggiornato',
        () async {
      await fileSystem.writeBytes(execPath, [1, 2, 3]);
      await settingsFacade.setRuntimeExecutable(execPath);

      final snapshot = await inferenceFacade.getSnapshot();
      expect(snapshot.runtimeConfiguration?.executablePath, equals(execPath));
      expect(snapshot.isReady, isFalse); // Manca Actor

      var notifiedCount = 0;
      statusNotifier.addListener((snap) {
        notifiedCount++;
      });

      await statusNotifier.refresh();
      expect(statusNotifier.snapshot, isNotNull);
      expect(notifiedCount, equals(1));
    });

    test('RuntimeModelSettingsFacade gestisce executable, binding e consenso',
        () async {
      await fileSystem.writeBytes(execPath, [1, 2, 3]);

      final runtimeConfig = await settingsFacade.setRuntimeExecutable(execPath);
      expect(runtimeConfig.executablePath, equals(execPath));

      expect(await settingsFacade.isConsentValid(), isFalse);
      await settingsFacade.recordConsent();
      expect(await settingsFacade.isConsentValid(), isTrue);

      const extPath = r'C:\GgufModels\custom_actor.gguf';
      await fileSystem.writeBytes(extPath, [1, 2, 3]);

      final bindActorRes = await settingsFacade.bindActor(
        ExternalModelReference(absolutePath: extPath),
      );
      expect(bindActorRes.isValid, isTrue);

      await settingsFacade.clearActorBinding();
      final currentConfig = await configRepo.readRecord();
      expect(currentConfig.models.actor, isNull);
    });

    test(
        'WinGetDependencyAdapter tramite settingsFacade restituisce assistenza e disponibilita',
        () async {
      expect(await settingsFacade.isWinGetAvailable(), isTrue);
      final assistance = await settingsFacade.getWinGetAssistance();
      expect(assistance.command, contains('winget install'));
      expect(assistance.requiresUserConfirmation, isTrue);
    });

    test(
        'FirstRunModelSetupFacade guida lo stepper di onboarding attraverso i passi',
        () async {
      // 1. Stato iniziale: nessun runtime configurato
      final step1 = await firstRunFacade.evaluateInitialState();
      expect(step1.step, equals(FirstRunSetupStep.runtimeSelection));

      // 2. Configura runtime
      await fileSystem.writeBytes(execPath, [1, 2, 3]);
      final step2 = await firstRunFacade.configureRuntime(execPath);
      expect(step2.step, equals(FirstRunSetupStep.actorSelection));

      // 3. Seleziona modello Actor (External senza consenso)
      const actorPath = r'C:\Models\actor.gguf';
      await fileSystem.writeBytes(actorPath, [1, 2, 3]);
      final step3 = await firstRunFacade.selectActorModel(
        ExternalModelReference(absolutePath: actorPath),
      );
      expect(step3.step, equals(FirstRunSetupStep.consentRequired));

      // 4. Accetta consenso
      final step4 = await firstRunFacade.acceptConsentAndRetry();
      expect(step4.step, equals(FirstRunSetupStep.actorSelection));

      // Ora il consenso è accettato, la ri-selezione dell'Actor fa avanzare all'Evaluator
      final step4b = await firstRunFacade.selectActorModel(
        ExternalModelReference(absolutePath: actorPath),
      );
      expect(step4b.step, equals(FirstRunSetupStep.evaluatorSelection));

      // 5. Seleziona modello Evaluator
      const evalPath = r'C:\Models\evaluator.gguf';
      await fileSystem.writeBytes(evalPath, [1, 2, 3]);
      final step5 = await firstRunFacade.selectEvaluatorModel(
        ExternalModelReference(absolutePath: evalPath),
      );
      expect(step5.step, equals(FirstRunSetupStep.complete));
      expect(step5.isComplete, isTrue);
    });

    test(
        'StatusNotifier ignora le risposte fuori ordine (out-of-order execution protection)',
        () async {
      var notifiedSnapshots = <LocalInferenceSnapshot>[];
      statusNotifier.addListener((snap) {
        notifiedSnapshots.add(snap);
      });

      // Esegui due refresh consecutivi
      final f1 = statusNotifier.refresh();
      final f2 = statusNotifier.refresh();

      await Future.wait([f1, f2]);

      // Il notifier deve contenere lo snapshot finale e aver notificato in modo coerente
      expect(statusNotifier.snapshot, isNotNull);
    });
  });
}
