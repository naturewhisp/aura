import 'package:meta/meta.dart';
import '../../agent_runtime/model_catalog.dart';
import '../domain/activation_state.dart';
import '../domain/catalog_manifest.dart';
import '../infrastructure/activation_state_repository.dart';
import '../infrastructure/installation_record_repository.dart';
import '../infrastructure/provisioning_file_system.dart';
import '../infrastructure/provisioning_path_resolver.dart';
import '../resolvers/model_resolver.dart';
import '../resolvers/runtime_resolver.dart';

/// Stato dell'inizializzazione del provisioning all'avvio dell'applicazione.
enum ProvisioningBootstrapStatus {
  /// Avvio completato con successo: runtime e modello attivo sono integri ed attivi senza degradazione.
  ready,

  /// Avvio completato con riconciliazione/degradazione: è stato attivato un fallback (lastKnownGood o latestVerified).
  degraded,

  /// Inizializzazione non completata o fallita: nessun runtime o modello valido disponibile.
  failed,
}

/// Esito sintetico e diagnostico del bootstrap del provisioning.
@immutable
final class ProvisioningBootstrapResult {
  final ProvisioningBootstrapStatus status;
  final ResolvedModelPayload? activeModel;
  final ResolvedRuntimePayload? activeRuntime;
  final ActivationState activationState;
  final Map<String, dynamic> diagnostics;

  const ProvisioningBootstrapResult({
    required this.status,
    required this.activeModel,
    required this.activeRuntime,
    required this.activationState,
    required this.diagnostics,
  });

  bool get isReady => status == ProvisioningBootstrapStatus.ready;
  bool get isDegraded => status == ProvisioningBootstrapStatus.degraded;
  bool get isFailed => status == ProvisioningBootstrapStatus.failed;

  Map<String, dynamic> toJson() => {
        'status': status.name,
        if (activeModel != null) 'activeModel': activeModel!.toJson(),
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

  ProvisioningBootstrapService({
    required ProvisioningPathResolver pathResolver,
    required InstallationRecordRepository recordRepository,
    required ActivationStateRepository activationRepository,
    required ModelResolver modelResolver,
    required RuntimeResolver runtimeResolver,
    ProvisioningFileSystem fileSystem = const LocalProvisioningFileSystem(),
  })  : _pathResolver = pathResolver,
        _fileSystem = fileSystem,
        _recordRepository = recordRepository,
        _activationRepository = activationRepository,
        _modelResolver = modelResolver,
        _runtimeResolver = runtimeResolver;

  /// Esegue il bootstrap completo del perimetro di provisioning:
  /// 1. Garantisce l'esistenza della struttura di directory gestite dall'app (`models/`, `runtimes/`, `records/`, `activation/`).
  /// 2. Inizializza i repository di stato se mancanti.
  /// 3. Esegue la risoluzione e la verifica dell'integrità del modello di Actor predefinito e del runtime.
  /// 4. Se un'installazione attiva è mancante o corrotta, riconcilia automaticamente lo stato su `lastKnownGood` o `latestVerified`.
  /// 5. Restituisce l'esito diagnostico [ProvisioningBootstrapResult].
  Future<ProvisioningBootstrapResult> bootstrap(
      {CatalogManifest? initialManifest}) async {
    // 1. Assicura le directory gestite dall'applicazione
    await _fileSystem.createDirectory(_pathResolver.appManagedRoot);
    await _fileSystem.createDirectory(
        _pathResolver.join(_pathResolver.appManagedRoot, 'models'));
    await _fileSystem.createDirectory(
        _pathResolver.join(_pathResolver.appManagedRoot, 'runtimes'));
    await _fileSystem.createDirectory(
        _pathResolver.join(_pathResolver.appManagedRoot, 'records'));
    await _fileSystem.createDirectory(
        _pathResolver.join(_pathResolver.appManagedRoot, 'activation'));

    // 2. Legge o inizializza i record persistenti
    final record = await _recordRepository.readRecord();
    var state = await _activationRepository.readState();

    // 3. Risoluzione e verifica dell'integrità del modello Actor predefinito
    final modelRes =
        await _modelResolver.resolveModel(LogicalModelIds.defaultActor);
    final ResolvedModelPayload? resolvedModel =
        modelRes.isSuccess ? modelRes.payload : null;

    // 4. Risoluzione e verifica dell'integrità del runtime di inferenza
    final runtimeRes = await _runtimeResolver.resolveRuntime();
    final ResolvedRuntimePayload? resolvedRuntime =
        runtimeRes.isSuccess ? runtimeRes.payload : null;

    bool stateReconciled = false;

    // Riconciliazione automatica dello stato di attivazione se è stato attivato un fallback per il modello
    if (resolvedModel != null && resolvedModel.isFallbackUsed) {
      state = state.copyWith(
        activeModelInstallationId: resolvedModel.installationId,
        updatedAt: DateTime.now().toUtc().toIso8601String(),
      );
      stateReconciled = true;
    }

    // Riconciliazione automatica dello stato di attivazione se è stato attivato un fallback per il runtime
    if (resolvedRuntime != null && resolvedRuntime.isFallbackUsed) {
      state = state.copyWith(
        activeRuntimeInstallationId: resolvedRuntime.installationId,
        updatedAt: DateTime.now().toUtc().toIso8601String(),
      );
      stateReconciled = true;
    }

    if (stateReconciled) {
      await _activationRepository.replaceState(state);
    }

    // 5. Calcolo dello stato di bootstrap complessivo
    final bool isModelValid = resolvedModel != null;
    final bool isRuntimeValid = resolvedRuntime != null;
    final bool isDegraded = (resolvedModel?.isFallbackUsed == true) ||
        (resolvedRuntime?.isFallbackUsed == true);

    final status = (!isModelValid || !isRuntimeValid)
        ? ProvisioningBootstrapStatus.failed
        : (isDegraded
            ? ProvisioningBootstrapStatus.degraded
            : ProvisioningBootstrapStatus.ready);

    final diagnostics = <String, dynamic>{
      'appManagedRoot': _pathResolver.appManagedRoot,
      'totalRecords': record.installedArtifacts.length,
      'verifiedRecords':
          record.installedArtifacts.where((a) => a.isVerified).length,
      'stateReconciled': stateReconciled,
      'isModelValid': isModelValid,
      'isRuntimeValid': isRuntimeValid,
      'modelFallbackUsed': resolvedModel?.isFallbackUsed ?? false,
      'runtimeFallbackUsed': resolvedRuntime?.isFallbackUsed ?? false,
      if (resolvedModel?.fallbackSource != null)
        'modelFallbackSource': resolvedModel!.fallbackSource,
      if (resolvedRuntime?.fallbackSource != null)
        'runtimeFallbackSource': resolvedRuntime!.fallbackSource,
    };

    return ProvisioningBootstrapResult(
      status: status,
      activeModel: resolvedModel,
      activeRuntime: resolvedRuntime,
      activationState: state,
      diagnostics: diagnostics,
    );
  }
}
