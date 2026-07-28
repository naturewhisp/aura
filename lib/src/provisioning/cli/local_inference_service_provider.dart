import '../application/local_inference_facade.dart';
import '../application/runtime_model_settings_facade.dart';
import '../infrastructure/installation_record_repository.dart';
import '../infrastructure/json_model_configuration_repository.dart';
import '../infrastructure/llama_server_dependency_service.dart';
import '../infrastructure/local_inference_preflight_engine.dart';
import '../infrastructure/model_configuration_service.dart';
import '../infrastructure/provisioning_file_system.dart';
import '../infrastructure/provisioning_lock.dart';
import '../infrastructure/provisioning_path_resolver.dart';
import '../infrastructure/winget_dependency_adapter.dart';
import 'aura_cli_environment.dart';
import 'local_inference_cli_runner.dart';

/// Contenitore per i servizi e le facade dell'inferenza locale.
final class LocalInferenceServices {
  final LocalInferenceFacade inferenceFacade;
  final RuntimeModelSettingsFacade settingsFacade;
  final LocalInferenceCliRunner cliRunner;

  const LocalInferenceServices({
    required this.inferenceFacade,
    required this.settingsFacade,
    required this.cliRunner,
  });
}

/// Service provider / composition root per l'inizializzazione del grafo di dipendenze dell'inferenza locale.
final class LocalInferenceServiceProvider {
  /// Inizializza i servizi ed il runner CLI utilizzando percorsi dinamici e lock inter-processo su disco.
  static LocalInferenceServices create({
    required AuraCliEnvironment environment,
    ProvisioningFileSystem? customFileSystem,
    ProvisioningLock? customLock,
  }) {
    final pathResolver = ProvisioningPathResolver(
      appManagedRoot: environment.appManagedRoot,
      bundledRoot: environment.bundledRoot,
    );
    final fileSystem = customFileSystem ?? const LocalProvisioningFileSystem();
    final lock = customLock ??
        FileBasedProvisioningLock(lockDirectory: environment.appManagedRoot);

    final configRepo = JsonModelConfigurationRepository(
      storeDirectoryPath: pathResolver.appManagedRoot,
      fileSystem: fileSystem,
      lock: lock,
    );

    final installRepo = JsonInstallationRecordRepository(
      pathResolver: pathResolver,
      fileSystem: fileSystem,
      lock: lock,
    );

    final dependencyService = DefaultLlamaServerDependencyService(
      configurationRepository: configRepo,
      fileSystem: fileSystem,
      pathResolver: pathResolver,
    );

    final modelService = DefaultModelConfigurationService(
      configurationRepository: configRepo,
      installationRecordRepository: installRepo,
      fileSystem: fileSystem,
      pathResolver: pathResolver,
    );

    final preflightEngine = DefaultLocalInferencePreflightEngine(
      configurationRepository: configRepo,
      installationRecordRepository: installRepo,
      dependencyService: dependencyService,
      fileSystem: fileSystem,
      pathResolver: pathResolver,
    );

    final inferenceFacade = DefaultLocalInferenceFacade(
      preflightEngine: preflightEngine,
      dependencyService: dependencyService,
      modelConfigurationService: modelService,
      installationRecordRepository: installRepo,
    );

    final settingsFacade = DefaultRuntimeModelSettingsFacade(
      dependencyService: dependencyService,
      modelService: modelService,
      winGetAdapter: WinGetDependencyAdapter(),
    );

    final cliRunner = LocalInferenceCliRunner(
      inferenceFacade: inferenceFacade,
      settingsFacade: settingsFacade,
    );

    return LocalInferenceServices(
      inferenceFacade: inferenceFacade,
      settingsFacade: settingsFacade,
      cliRunner: cliRunner,
    );
  }
}
