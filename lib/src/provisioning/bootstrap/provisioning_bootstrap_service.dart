import 'package:meta/meta.dart';
import '../../agent_runtime/model_catalog.dart';
import '../domain/activation_state.dart';
import '../domain/provisioning_clock.dart';
import '../infrastructure/activation_state_repository.dart';
import '../infrastructure/installation_record_repository.dart';
import '../infrastructure/provisioning_file_system.dart';
import '../infrastructure/provisioning_path_resolver.dart';
import '../resolvers/model_resolver.dart';
import '../resolvers/runtime_resolver.dart';

/// Stato dell'inizializzazione del provisioning all'avvio dell'applicazione.
enum ProvisioningBootstrapStatus {
  /// Avvio completato con successo: runtime, modello Actor e modello Evaluator sono tutti integri ed attivi senza degradazione.
  ready,

  /// Avvio completato con riconciliazione/degradazione: è stato attivato un fallback per almeno un modello o per il runtime.
  degraded,

  /// Inizializzazione fallita: il runtime o uno dei due modelli (Actor o Evaluator) non è disponibile o integro.
  failed,
}

/// Esito sintetico e diagnostico del bootstrap del provisioning.
@immutable
final class ProvisioningBootstrapResult {
  final ProvisioningBootstrapStatus status;
  final ResolvedModelPayload? activeActorModel;
  final ResolvedModelPayload? activeEvaluatorModel;
  final ResolvedRuntimePayload? activeRuntime;
  final ActivationState activationState;
  final Map<String, dynamic> diagnostics;

  const ProvisioningBootstrapResult({
    required this.status,
    required this.activeActorModel,
    required this.activeEvaluatorModel,
    required this.activeRuntime,
    required this.activationState,
    required this.diagnostics,
  });

  bool get isReady => status == ProvisioningBootstrapStatus.ready;
  bool get isDegraded => status == ProvisioningBootstrapStatus.degraded;
  bool get isFailed => status == ProvisioningBootstrapStatus.failed;

  Map<String, dynamic> toJson() => {
        'status': status.name,
        if (activeActorModel != null)
          'activeActorModel': activeActorModel!.toJson(),
        if (activeEvaluatorModel != null)
          'activeEvaluatorModel': activeEvaluatorModel!.toJson(),
        if (activeRuntime != null) 'activeRuntime': activeRuntime!.toJson(),
        'activationState': activationState.toJson(),
        'diagnostics': diagnostics,
      };
}

/// Orchestratore di bootstrap per l'inizializzazione delle directory, la verifica dell'integrità all'avvio e la riconciliazione automatica dello stato.
final class ProvisioningBootstrapService {
  final ProvisioningPathResolver _pathResolver;
  final ProvisioningFileSystem _fileSystem;
  final InstallationRecordRepository _recordRepository;
  final ActivationStateRepository _activationRepository;
  final ModelResolver _modelResolver;
  final RuntimeResolver _runtimeResolver;
  final ProvisioningClock _clock;

  ProvisioningBootstrapService({
    required ProvisioningPathResolver pathResolver,
    required InstallationRecordRepository recordRepository,
    required ActivationStateRepository activationRepository,
    required ModelResolver modelResolver,
    required RuntimeResolver runtimeResolver,
    ProvisioningFileSystem fileSystem = const LocalProvisioningFileSystem(),
    ProvisioningClock clock = const SystemProvisioningClock(),
  })  : _pathResolver = pathResolver,
        _fileSystem = fileSystem,
        _recordRepository = recordRepository,
        _activationRepository = activationRepository,
        _modelResolver = modelResolver,
        _runtimeResolver = runtimeResolver,
        _clock = clock;

  /// Esegue il bootstrap completo del perimetro di provisioning:
  /// 1. Garantisce l'esistenza delle directory app-managed (models, runtimes, staging, cache, logs).
  /// 2. Inizializza i repository di stato se mancanti.
  /// 3. Risolve e verifica in modo role-aware SIA l'Actor SIA l'Evaluator SIA il runtime.
  /// 4. Se un'installazione attiva è mancante o corrotta, riconcilia automaticamente lo stato in [ActivationStateRepository].
  /// 5. Restituisce l'esito diagnostico [ProvisioningBootstrapResult].
  Future<ProvisioningBootstrapResult> bootstrap() async {
    // 1. Assicura l'esistenza delle directory gestite coerentemente con i getter del ProvisioningPathResolver
    await _fileSystem.createDirectory(_pathResolver.appManagedRoot);
    await _fileSystem.createDirectory(_pathResolver.modelsDirectory);
    await _fileSystem.createDirectory(_pathResolver.runtimesDirectory);
    await _fileSystem.createDirectory(_pathResolver.stagingDirectory);
    await _fileSystem.createDirectory(_pathResolver.cacheDirectory);
    await _fileSystem.createDirectory(_pathResolver.logsDirectory);

    // 2. Legge o inizializza i record persistenti
    final record = await _recordRepository.readRecord();
    var state = await _activationRepository.readState();

    // 3. Risoluzione e verifica role-aware dell'Actor predefinito
    final actorRes =
        await _modelResolver.resolveModel(LogicalModelIds.defaultActor);
    final ResolvedModelPayload? resolvedActor =
        actorRes.isSuccess ? actorRes.payload : null;

    // 4. Risoluzione e verifica role-aware dell'Evaluator predefinito
    final evalRes =
        await _modelResolver.resolveModel(LogicalModelIds.defaultEvaluator);
    final ResolvedModelPayload? resolvedEvaluator =
        evalRes.isSuccess ? evalRes.payload : null;

    // 5. Risoluzione e verifica dell'integrità del runtime di inferenza
    final runtimeRes = await _runtimeResolver.resolveRuntime();
    final ResolvedRuntimePayload? resolvedRuntime =
        runtimeRes.isSuccess ? runtimeRes.payload : null;

    bool stateReconciled = false;
    final nowIso = _clock.nowUtc().toUtc().toIso8601String();

    // Riconciliazione dello stato di attivazione dell'Actor
    if (resolvedActor != null && resolvedActor.isFallbackUsed) {
      state = state.copyWith(
        activeActorModelInstallationId: resolvedActor.installationId,
        updatedAt: nowIso,
      );
      stateReconciled = true;
    }

    // Riconciliazione dello stato di attivazione dell'Evaluator
    if (resolvedEvaluator != null && resolvedEvaluator.isFallbackUsed) {
      state = state.copyWith(
        activeEvaluatorModelInstallationId: resolvedEvaluator.installationId,
        updatedAt: nowIso,
      );
      stateReconciled = true;
    }

    // Riconciliazione dello stato di attivazione del runtime
    if (resolvedRuntime != null && resolvedRuntime.isFallbackUsed) {
      state = state.copyWith(
        activeRuntimeInstallationId: resolvedRuntime.installationId,
        updatedAt: nowIso,
      );
      stateReconciled = true;
    }

    if (stateReconciled) {
      await _activationRepository.replaceState(state);
    }

    // 6. Determinazione dello stato di bootstrap complessivo
    final bool isActorValid = resolvedActor != null;
    final bool isEvaluatorValid = resolvedEvaluator != null;
    final bool isRuntimeValid = resolvedRuntime != null;

    final bool anyFallbackUsed = (resolvedActor?.isFallbackUsed == true) ||
        (resolvedEvaluator?.isFallbackUsed == true) ||
        (resolvedRuntime?.isFallbackUsed == true);

    final status = (!isActorValid || !isEvaluatorValid || !isRuntimeValid)
        ? ProvisioningBootstrapStatus.failed
        : (anyFallbackUsed
            ? ProvisioningBootstrapStatus.degraded
            : ProvisioningBootstrapStatus.ready);

    final diagnostics = <String, dynamic>{
      'appManagedRoot': _pathResolver.appManagedRoot,
      'totalRecords': record.installedArtifacts.length,
      'verifiedRecords':
          record.installedArtifacts.where((a) => a.isVerified).length,
      'stateReconciled': stateReconciled,
      'isActorValid': isActorValid,
      'isEvaluatorValid': isEvaluatorValid,
      'isRuntimeValid': isRuntimeValid,
      'actorFallbackUsed': resolvedActor?.isFallbackUsed ?? false,
      'evaluatorFallbackUsed': resolvedEvaluator?.isFallbackUsed ?? false,
      'runtimeFallbackUsed': resolvedRuntime?.isFallbackUsed ?? false,
    };

    return ProvisioningBootstrapResult(
      status: status,
      activeActorModel: resolvedActor,
      activeEvaluatorModel: resolvedEvaluator,
      activeRuntime: resolvedRuntime,
      activationState: state,
      diagnostics: diagnostics,
    );
  }
}
