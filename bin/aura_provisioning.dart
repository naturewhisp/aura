import 'dart:io';
import 'package:aura_core/aura_offline.dart';

void main(List<String> args) async {
  if (args.isEmpty || args.contains('--help') || args.contains('-h')) {
    _printHelp();
    exit(0);
  }

  final command = args[0].toLowerCase();
  final appManagedRoot = Platform.environment['AURA_APP_MANAGED_ROOT'] ??
      '${Directory.current.path}/.aura_managed';
  final bundledRoot = Platform.environment['AURA_BUNDLED_ROOT'] ??
      '${Directory.current.path}/assets/provisioning';

  final pathResolver = ProvisioningPathResolver(
    appManagedRoot: appManagedRoot,
    bundledRoot: bundledRoot,
  );

  const fileSystem = LocalProvisioningFileSystem();
  final lock = InMemoryProvisioningLock();

  final recordRepo = JsonInstallationRecordRepository(
    pathResolver: pathResolver,
    lock: lock,
    fileSystem: fileSystem,
  );

  final activationRepo = JsonActivationStateRepository(
    pathResolver: pathResolver,
    lock: lock,
    fileSystem: fileSystem,
  );

  final httpClient = HttpProvisioningHttpClient();
  final ingestionEngine = ArtifactIngestionEngine(
    pathResolver: pathResolver,
    httpClient: httpClient,
    fileSystem: fileSystem,
  );

  final verifier = LocalInstalledArtifactVerifier(fileSystem: fileSystem);

  final coordinator = ProvisioningCoordinator(
    lock: lock,
    recordRepository: recordRepo,
    activationRepository: activationRepo,
    ingestionEngine: ingestionEngine,
    pathResolver: pathResolver,
    fileSystem: fileSystem,
    verifier: verifier,
  );

  final catalog = ModelCatalog.initialDefault();

  final modelResolver = ModelResolver(
    catalog: catalog,
    recordRepository: recordRepo,
    activationRepository: activationRepo,
    pathResolver: pathResolver,
    verifier: verifier,
  );

  final runtimeResolver = RuntimeResolver(
    recordRepository: recordRepo,
    activationRepository: activationRepo,
    pathResolver: pathResolver,
    verifier: verifier,
    fileSystem: fileSystem,
  );

  final bootstrapService = ProvisioningBootstrapService(
    pathResolver: pathResolver,
    recordRepository: recordRepo,
    activationRepository: activationRepo,
    modelResolver: modelResolver,
    runtimeResolver: runtimeResolver,
    fileSystem: fileSystem,
  );

  final cliRunner = ProvisioningCliRunner(
    bootstrapService: bootstrapService,
    coordinator: coordinator,
    recordRepository: recordRepo,
  );

  CliCommandResult result;

  try {
    switch (command) {
      case 'status':
        result = await cliRunner.status();
        break;
      case 'list-catalog':
        final manifest = CatalogManifest.initialDefault();
        result = cliRunner.listCatalog(manifest);
        break;
      case 'list-installed':
        result = await cliRunner.listInstalled();
        break;
      case 'activate':
        if (args.length < 2) {
          stderr.writeln('Errore: Specificare l\'installationId da attivare.');
          stderr.writeln(
              'Uso: activate <installationId> [--role actor|evaluator]');
          exit(1);
        }
        final instId = args[1];
        ModelActivationRole? role;
        if (args.contains('--role')) {
          final idx = args.indexOf('--role');
          if (idx + 1 >= args.length) {
            stderr.writeln(
                'Errore: Opzione --role specificata senza il valore del ruolo (actor|evaluator).');
            exit(1);
          }
          final roleStr = args[idx + 1];
          role = ModelActivationRole.tryParse(roleStr);
          if (role == null) {
            stderr.writeln(
                'Errore: Ruolo di attivazione non valido "$roleStr". Valori ammessi: actor, evaluator.');
            exit(1);
          }
        }
        result = await cliRunner.activate(
          installationId: instId,
          operationId: 'cli-activate-${DateTime.now().millisecondsSinceEpoch}',
          modelRole: role,
        );
        break;
      case 'remove':
        if (args.length < 2) {
          stderr.writeln('Errore: Specificare l\'installationId da rimuovere.');
          exit(1);
        }
        final instId = args[1];
        result = await cliRunner.remove(
          installationId: instId,
          operationId: 'cli-remove-${DateTime.now().millisecondsSinceEpoch}',
        );
        break;
      default:
        stderr.writeln('Errore: Comando sconosciuto "$command".');
        _printHelp();
        exit(1);
    }
  } catch (e) {
    stderr.writeln('Errore durante l\'esecuzione del comando CLI: $e');
    exit(1);
  } finally {
    await httpClient.close();
  }

  print(result.toFormattedJson());
  exit(result.success ? 0 : 1);
}

void _printHelp() {
  print('''
A.U.R.A. Provisioning CLI Runner (Phase 6.3e)
Uso: aura_provisioning <comando> [opzioni]

Comandi disponibili:
  status               Mostra lo stato di salute di bootstrap e le installazioni attive.
  list-catalog         Elenca gli artefatti dichiarati nel catalogo iniziale di bootstrap.
  list-installed       Elenca le installazioni registrate nello stato persistente locale.
  activate <instId>    Attiva un'installazione specifica tramite il suo installationId.
  remove <instId>      Rimuove un'installazione non attiva dal disco e dal registro.
  --help, -h           Mostra questa schermata di aiuto.
''');
}
