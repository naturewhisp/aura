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
  late DefaultModelConfigurationService modelService;
  late DefaultLocalInferencePreflightEngine engine;
  late TestProcessLauncher processLauncher;

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

    processLauncher = TestProcessLauncher((req) async {
      return TestManagedProcess(stdoutText: 'version: b3450');
    });

    final dependencyService = DefaultLlamaServerDependencyService(
      configurationRepository: configRepo,
      fileSystem: fileSystem,
      pathResolver: pathResolver,
      processLauncher: processLauncher,
    );

    modelService = DefaultModelConfigurationService(
      configurationRepository: configRepo,
      installationRecordRepository: installRepo,
      fileSystem: fileSystem,
      pathResolver: pathResolver,
    );

    engine = DefaultLocalInferencePreflightEngine(
      configurationRepository: configRepo,
      installationRecordRepository: installRepo,
      dependencyService: dependencyService,
      fileSystem: fileSystem,
      pathResolver: pathResolver,
    );
  });

  group('Tranche 6.4f.4 — DefaultLocalInferencePreflightEngine Tests', () {
    test(
        'check(quick) segnala runtimeNotConfigured se nessun runtime è impostato',
        () async {
      final result = await engine.check(depth: PreflightDepth.quick);
      expect(result.isReady, isFalse);
      expect(
        result.failureReason,
        equals(LocalInferencePreflightFailure.runtimeNotConfigured),
      );
    });

    test('check(quick) segnala runtimeMissing se l\'eseguibile non esiste',
        () async {
      await configRepo.replaceRecord(
        const ModelConfigurationRecord(
          schemaVersion: 1,
          runtime: LlamaServerConfiguration(
            executablePath: execPath,
          ),
        ),
      );

      final result = await engine.check(depth: PreflightDepth.quick);
      expect(result.isReady, isFalse);
      expect(
        result.failureReason,
        equals(LocalInferencePreflightFailure.runtimeMissing),
      );
    });

    test(
        'check(quick) segnala actorNotConfigured se il runtime è valido ma l\'Actor è assente',
        () async {
      await fileSystem.writeBytes(execPath, [1, 2, 3]);
      await configRepo.replaceRecord(
        const ModelConfigurationRecord(
          schemaVersion: 1,
          runtime: LlamaServerConfiguration(
            executablePath: execPath,
          ),
        ),
      );

      final result = await engine.check(depth: PreflightDepth.quick);
      expect(result.isReady, isFalse);
      expect(
        result.failureReason,
        equals(LocalInferencePreflightFailure.actorNotConfigured),
      );
    });

    test(
        'check(quick) segnala managedInstallationUnavailable se il modello Actor gestito è mancante',
        () async {
      await fileSystem.writeBytes(execPath, [1, 2, 3]);
      await configRepo.replaceRecord(
        ModelConfigurationRecord(
          schemaVersion: 1,
          runtime: const LlamaServerConfiguration(
            executablePath: execPath,
          ),
          models: ModelRoleConfiguration(
            actor: ManagedModelReference(installationId: 'inst_missing'),
          ),
        ),
      );

      final result = await engine.check(depth: PreflightDepth.quick);
      expect(result.isReady, isFalse);
      expect(
        result.failureReason,
        equals(LocalInferencePreflightFailure.managedInstallationUnavailable),
      );
    });

    test(
        'check(quick) restituisce ready quando runtime e modelli (Managed ed External) sono validi',
        () async {
      await fileSystem.writeBytes(execPath, [1, 2, 3]);

      // Configura installazione gestita Actor
      const actorInstId = 'inst_actor_1';
      const actorRelPath = r'models\actor-v1';
      final record = InstallationRecord(
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
      );
      await installRepo.replaceRecord(record);

      final actorFullPath =
          '${pathResolver.resolveAppManagedRelativePath(actorRelPath)}\\actor.gguf';
      await fileSystem.writeBytes(actorFullPath, [1, 2, 3, 4]);

      // Configura modello esterno Evaluator
      const evaluatorExtPath = r'C:\ExternalModels\evaluator.gguf';
      await fileSystem.writeBytes(evaluatorExtPath, [5, 6, 7]);
      await modelService.recordExternalModelConsent();

      await configRepo.replaceRecord(
        ModelConfigurationRecord(
          schemaVersion: 1,
          runtime: const LlamaServerConfiguration(
            executablePath: execPath,
          ),
          models: ModelRoleConfiguration(
            actor: ManagedModelReference(installationId: actorInstId),
            evaluator: ExternalModelReference(absolutePath: evaluatorExtPath),
          ),
          externalModelConsent: ExternalModelConsent.now(),
        ),
      );

      final result = await engine.check(depth: PreflightDepth.quick);
      expect(result.isReady, isTrue);
      expect(result.failureReason, isNull);
    });

    test(
        'check(runtimeProbe) esegue il probe processuale di llama-server e valida la versione',
        () async {
      await fileSystem.writeBytes(execPath, [1, 2, 3]);

      const actorInstId = 'inst_actor_1';
      const actorRelPath = r'models\actor-v1';
      final record = InstallationRecord(
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
      );
      await installRepo.replaceRecord(record);

      final actorFullPath =
          '${pathResolver.resolveAppManagedRelativePath(actorRelPath)}\\actor.gguf';
      await fileSystem.writeBytes(actorFullPath, [1, 2, 3, 4]);

      const evaluatorExtPath = r'C:\ExternalModels\evaluator.gguf';
      await fileSystem.writeBytes(evaluatorExtPath, [5, 6, 7]);

      await configRepo.replaceRecord(
        ModelConfigurationRecord(
          schemaVersion: 1,
          runtime: const LlamaServerConfiguration(
            executablePath: execPath,
          ),
          models: ModelRoleConfiguration(
            actor: ManagedModelReference(installationId: actorInstId),
            evaluator: ExternalModelReference(absolutePath: evaluatorExtPath),
          ),
          externalModelConsent: ExternalModelConsent.now(),
        ),
      );

      final result = await engine.check(depth: PreflightDepth.runtimeProbe);
      expect(result.isReady, isTrue);
      expect(result.runtimeConfiguration?.detectedVersion, equals('b3450'));
    });

    test(
        'check(fullModelLoad) restituisce un esito documentato di non-disponibilità',
        () async {
      final result = await engine.check(depth: PreflightDepth.fullModelLoad);
      expect(result.isReady, isFalse);
      expect(
        result.failureReason,
        equals(LocalInferencePreflightFailure.runtimeStartupFailed),
      );
      expect(result.sanitizedMessage, contains('supervisor real-time'));
    });
  });
}
