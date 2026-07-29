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

/// Fake LocalInferenceFacade controllabile per testare le chiamate out-of-order del status notifier.
final class ControllableLocalInferenceFacade implements LocalInferenceFacade {
  final List<Completer<LocalInferenceSnapshot>> completers = [];

  @override
  Future<LocalInferenceSnapshot> getSnapshot() {
    final completer = Completer<LocalInferenceSnapshot>();
    completers.add(completer);
    return completer.future;
  }

  @override
  Future<LlamaServerDetectionResult> detectRuntime() async =>
      const LlamaServerDetectionResult();

  @override
  Future<LocalInferencePreflightResult> runPreflight(
          {required PreflightDepth depth}) async =>
      const LocalInferencePreflightResult.ready();

  @override
  Future<List<ExternalModelCandidate>> scanExternalCandidates(
          {String? customPath}) async =>
      const [];

  @override
  Future<List<InstalledArtifactDescriptor>> listManagedModels() async =>
      const [];

  @override
  Future<List<ProcessOwnershipRecord>> listManagedProcesses() async => const [];

  @override
  Future<List<ProcessOwnershipRecord>> cleanupStaleProcesses() async =>
      const [];
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

    final processOwnershipRegistry = ProcessOwnershipRegistry(
      pathResolver: pathResolver,
      lock: InMemoryProvisioningLock(),
    );

    inferenceFacade = DefaultLocalInferenceFacade(
      preflightEngine: preflightEngine,
      dependencyService: dependencyService,
      modelConfigurationService: modelService,
      installationRecordRepository: installRepo,
      processOwnershipRegistry: processOwnershipRegistry,
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

  group('Tranche 6.4f.5-fix — Application Facades & Notifier Tests', () {
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
        'FirstRunModelSetupFacade con retry effettivo e stateless dopo consenso',
        () async {
      // 1. Stato iniziale: nessun runtime configurato
      final step1 = await firstRunFacade.evaluateInitialState();
      expect(step1.step, equals(FirstRunSetupStep.runtimeSelection));

      // 2. Configura runtime
      await fileSystem.writeBytes(execPath, [1, 2, 3]);
      final step2 = await firstRunFacade.configureRuntime(execPath);
      expect(step2.step, equals(FirstRunSetupStep.actorSelection));

      // 3. Seleziona modello Actor (External senza consenso) -> va in consentRequired
      const actorPath = r'C:\Models\actor.gguf';
      await fileSystem.writeBytes(actorPath, [1, 2, 3]);
      final step3 = await firstRunFacade.selectActorModel(
        ExternalModelReference(absolutePath: actorPath),
      );
      expect(step3.step, equals(FirstRunSetupStep.consentRequired));

      // 4. Esegue il retry reale con consenso tramite acceptConsentAndRetry
      final step4 = await firstRunFacade.acceptConsentAndRetry(
        role: ModelActivationRole.actor,
        reference: ExternalModelReference(absolutePath: actorPath),
      );
      // Il binding ha successo e il flusso avanza ad evaluatorSelection!
      expect(step4.step, equals(FirstRunSetupStep.evaluatorSelection));

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
        'evaluateInitialState identifica simmetricamente Actor ed Evaluator in caso di fallimento',
        () async {
      await fileSystem.writeBytes(execPath, [1, 2, 3]);
      await settingsFacade.setRuntimeExecutable(execPath);

      // Actor configurato ma con installazione gestita mancante -> deve indicare actorSelection
      await configRepo.replaceRecord(
        ModelConfigurationRecord(
          schemaVersion: 1,
          runtime: const LlamaServerConfiguration(executablePath: execPath),
          models: ModelRoleConfiguration(
            actor: ManagedModelReference(installationId: 'missing_actor'),
          ),
        ),
      );

      final actorFailState = await firstRunFacade.evaluateInitialState();
      expect(actorFailState.step, equals(FirstRunSetupStep.actorSelection));
      expect(
        actorFailState.preflightResult?.affectedRole,
        equals(ModelActivationRole.actor),
      );

      // Actor valido, Evaluator gestito mancante -> deve indicare evaluatorSelection
      const actorInstId = 'inst_actor_ok';
      const actorRelPath = r'models\actor-ok';
      await installRepo.replaceRecord(
        InstallationRecord(
          updatedAt: DateTime.now().toUtc().toIso8601String(),
          installedArtifacts: [
            InstalledArtifactDescriptor(
              installationId: actorInstId,
              artifactId: 'aura-actor-v1',
              displayName: 'Aura Actor Model',
              version: '1.0.0',
              buildId: 'b1',
              platform: 'windows',
              architecture: 'x64',
              relativeInstallPath: actorRelPath,
              entryFileName: 'actor.gguf',
              artifactType: CatalogArtifactType.model,
              sourceKind: CatalogArtifactSourceKind.remoteHttps,
              sizeBytes: 1024,
              sha256: 'abc',
              status: InstallationStatus.verified,
              verifiedAt: DateTime.now().toUtc().toIso8601String(),
              installedAt: DateTime.now().toUtc().toIso8601String(),
            ),
          ],
        ),
      );
      final actorFullPath =
          '${pathResolver.resolveAppManagedRelativePath(actorRelPath)}\\actor.gguf';
      await fileSystem.writeBytes(actorFullPath, [1, 2, 3, 4]);

      await configRepo.replaceRecord(
        ModelConfigurationRecord(
          schemaVersion: 1,
          runtime: const LlamaServerConfiguration(executablePath: execPath),
          models: ModelRoleConfiguration(
            actor: ManagedModelReference(installationId: actorInstId),
            evaluator:
                ManagedModelReference(installationId: 'missing_evaluator'),
          ),
        ),
      );

      final evalFailState = await firstRunFacade.evaluateInitialState();
      expect(evalFailState.step, equals(FirstRunSetupStep.evaluatorSelection));
      expect(
        evalFailState.preflightResult?.affectedRole,
        equals(ModelActivationRole.evaluator),
      );
    });

    test(
        'StatusNotifier scarta le risposte fuori ordine tramite Completer controllate',
        () async {
      final controllableFacade = ControllableLocalInferenceFacade();
      final notifier = LocalInferenceStatusNotifier(facade: controllableFacade);

      final snapshotsNotified = <LocalInferenceSnapshot>[];
      notifier.addListener((snap) => snapshotsNotified.add(snap));

      // 1. Avvia refresh A (sequence 1)
      final futureA = notifier.refresh();
      expect(controllableFacade.completers.length, equals(1));

      // 2. Avvia refresh B (sequence 2)
      final futureB = notifier.refresh();
      expect(controllableFacade.completers.length, equals(2));

      final snapshotA = const LocalInferenceSnapshot(
        runtimeConfiguration: LlamaServerConfiguration(executablePath: 'A.exe'),
        modelConfiguration: ModelRoleConfiguration(),
        isConsentValid: false,
        lastPreflightResult: LocalInferencePreflightResult.ready(),
      );

      final snapshotB = const LocalInferenceSnapshot(
        runtimeConfiguration: LlamaServerConfiguration(executablePath: 'B.exe'),
        modelConfiguration: ModelRoleConfiguration(),
        isConsentValid: true,
        lastPreflightResult: LocalInferencePreflightResult.ready(),
      );

      // 3. Completa B prima di A
      controllableFacade.completers[1].complete(snapshotB);
      await futureB;

      expect(notifier.snapshot, equals(snapshotB));
      expect(snapshotsNotified.length, equals(1));
      expect(snapshotsNotified.first, equals(snapshotB));

      // 4. Completa A successivamente
      controllableFacade.completers[0].complete(snapshotA);
      await futureA;

      // Lo snapshot non deve essere sovrascritto da A, e nessun nuovo evento deve essere emesso
      expect(notifier.snapshot, equals(snapshotB));
      expect(snapshotsNotified.length, equals(1));
    });

    test(
        'evaluateInitialState e runFinalPreflight gestiscono il fallimento del probe finale',
        () async {
      // Launcher che fallisce il probe processuale
      final failingLauncher = TestProcessLauncher((req) async {
        return TestManagedProcess(exitCodeValue: 1, stderrText: 'CUDA error');
      });

      final failingDependencyService = DefaultLlamaServerDependencyService(
        configurationRepository: configRepo,
        fileSystem: fileSystem,
        pathResolver: pathResolver,
        processLauncher: failingLauncher,
      );

      final failingEngine = DefaultLocalInferencePreflightEngine(
        configurationRepository: configRepo,
        installationRecordRepository: installRepo,
        dependencyService: failingDependencyService,
        fileSystem: fileSystem,
        pathResolver: pathResolver,
      );

      final failingFirstRunFacade = DefaultFirstRunModelSetupFacade(
        preflightEngine: failingEngine,
        dependencyService: failingDependencyService,
        modelService: modelService,
      );

      await fileSystem.writeBytes(execPath, [1, 2, 3]);

      const actorInstId = 'inst_actor_ok';
      const actorRelPath = r'models\actor-ok';
      await installRepo.replaceRecord(
        InstallationRecord(
          updatedAt: DateTime.now().toUtc().toIso8601String(),
          installedArtifacts: [
            InstalledArtifactDescriptor(
              installationId: actorInstId,
              artifactId: 'aura-actor-v1',
              displayName: 'Aura Actor Model',
              version: '1.0.0',
              buildId: 'b1',
              platform: 'windows',
              architecture: 'x64',
              relativeInstallPath: actorRelPath,
              entryFileName: 'actor.gguf',
              artifactType: CatalogArtifactType.model,
              sourceKind: CatalogArtifactSourceKind.remoteHttps,
              sizeBytes: 1024,
              sha256: 'abc',
              status: InstallationStatus.verified,
              verifiedAt: DateTime.now().toUtc().toIso8601String(),
              installedAt: DateTime.now().toUtc().toIso8601String(),
            ),
          ],
        ),
      );
      final actorFullPath =
          '${pathResolver.resolveAppManagedRelativePath(actorRelPath)}\\actor.gguf';
      await fileSystem.writeBytes(actorFullPath, [1, 2, 3, 4]);

      const evalExtPath = r'C:\Models\evaluator.gguf';
      await fileSystem.writeBytes(evalExtPath, [1, 2, 3]);

      await configRepo.replaceRecord(
        ModelConfigurationRecord(
          schemaVersion: 1,
          runtime: const LlamaServerConfiguration(executablePath: execPath),
          models: ModelRoleConfiguration(
            actor: ManagedModelReference(installationId: actorInstId),
            evaluator: ExternalModelReference(absolutePath: evalExtPath),
          ),
          externalModelConsent: ExternalModelConsent.now(),
        ),
      );

      // Il preflight finale deve fallire a causa del probe processuale
      final finalRes = await failingFirstRunFacade.runFinalPreflight();
      expect(finalRes.step, equals(FirstRunSetupStep.failed));
      expect(finalRes.errorMessage, contains('probe processuale'));
    });
  });
}
