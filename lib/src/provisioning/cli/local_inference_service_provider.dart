import 'package:http/http.dart' as http;
import '../domain/provisioning_clock.dart';
import '../infrastructure/activation_state_repository.dart';
import '../infrastructure/artifact_download_engine.dart';
import '../infrastructure/artifact_ingestion_engine.dart';
import '../infrastructure/download_checkpoint_repository.dart';
import '../infrastructure/download_concurrency_controller.dart';
import '../infrastructure/model_provisioning_service.dart';
import '../infrastructure/provisioning_coordinator.dart';
import '../infrastructure/provisioning_http_client.dart';
import '../application/first_run_model_setup_facade.dart';
import '../application/local_inference_facade.dart';
import '../application/runtime_model_settings_facade.dart';
import '../infrastructure/installation_record_repository.dart';
import '../infrastructure/json_model_configuration_repository.dart';
import '../infrastructure/llama_server_dependency_service.dart';
import '../infrastructure/local_inference_preflight_engine.dart';
import '../infrastructure/model_configuration_service.dart';
import '../infrastructure/process_ownership_registry.dart';
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
  final FirstRunModelSetupFacade firstRunFacade;
  final LlamaServerDependencyService dependencyService;
  final LocalInferenceCliRunner cliRunner;
  final InstallationRecordRepository installationRecordRepository;
  final ProvisioningPathResolver pathResolver;
  final ProvisioningFileSystem fileSystem;

  const LocalInferenceServices({
    required this.inferenceFacade,
    required this.settingsFacade,
    required this.firstRunFacade,
    required this.dependencyService,
    required this.cliRunner,
    required this.installationRecordRepository,
    required this.pathResolver,
    required this.fileSystem,
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

    final processOwnershipRegistry = ProcessOwnershipRegistry(
      pathResolver: pathResolver,
      lock: lock,
    );

    final inferenceFacade = DefaultLocalInferenceFacade(
      preflightEngine: preflightEngine,
      dependencyService: dependencyService,
      modelConfigurationService: modelService,
      installationRecordRepository: installRepo,
      processOwnershipRegistry: processOwnershipRegistry,
    );

    final settingsFacade = DefaultRuntimeModelSettingsFacade(
      dependencyService: dependencyService,
      modelService: modelService,
      winGetAdapter: WinGetDependencyAdapter(),
    );

    final checkpointRepo = JsonDownloadCheckpointRepository(
      fileSystem: fileSystem,
      pathResolver: pathResolver,
      lock: lock,
    );

    final activationRepo = JsonActivationStateRepository(
      fileSystem: fileSystem,
      pathResolver: pathResolver,
      lock: lock,
      clock: const SystemProvisioningClock(),
    );

    final httpClient = http.Client();
    final downloadEngine = DefaultArtifactDownloadEngine(
      httpClient: httpClient,
      fileSystem: fileSystem,
      pathResolver: pathResolver,
      checkpointRepository: checkpointRepo,
      concurrencyController:
          DownloadConcurrencyController(maxConcurrentDownloads: 1),
      clock: const SystemProvisioningClock(),
    );

    final coordinator = ProvisioningCoordinator(
      lock: lock,
      recordRepository: installRepo,
      activationRepository: activationRepo,
      ingestionEngine: ArtifactIngestionEngine(
        pathResolver: pathResolver,
        httpClient: HttpProvisioningHttpClient(client: httpClient),
        fileSystem: fileSystem,
      ),
      pathResolver: pathResolver,
      fileSystem: fileSystem,
      clock: const SystemProvisioningClock(),
    );

    final provisioningEnvironment = ProvisioningEnvironment(
      downloadEngine: downloadEngine,
      coordinator: coordinator,
      checkpointRepository: checkpointRepo,
      pathResolver: pathResolver,
      fileSystem: fileSystem,
      clock: const SystemProvisioningClock(),
    );

    final provisioningService = ModelProvisioningService(
      environment: provisioningEnvironment,
    );

    final firstRunFacade = DefaultFirstRunModelSetupFacade(
      preflightEngine: preflightEngine,
      dependencyService: dependencyService,
      modelService: modelService,
      provisioningService: provisioningService,
    );

    final cliRunner = LocalInferenceCliRunner(
      inferenceFacade: inferenceFacade,
      settingsFacade: settingsFacade,
    );

    return LocalInferenceServices(
      inferenceFacade: inferenceFacade,
      settingsFacade: settingsFacade,
      firstRunFacade: firstRunFacade,
      dependencyService: dependencyService,
      cliRunner: cliRunner,
      installationRecordRepository: installRepo,
      pathResolver: pathResolver,
      fileSystem: fileSystem,
    );
  }
}
