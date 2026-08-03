import 'dart:async';

import '../domain/catalog_manifest.dart';
import '../domain/configured_model_reference.dart';
import '../domain/installation_record.dart';
import '../domain/local_inference_preflight_models.dart';
import '../domain/provisioning_options.dart';
import '../domain/runtime_dependency_models.dart';
import 'bundled_runtime_resolver.dart';
import 'installation_record_repository.dart';
import 'json_model_configuration_repository.dart';
import 'llama_server_dependency_service.dart';
import 'provisioning_file_system.dart';
import 'provisioning_path_resolver.dart';
import 'runtime_manifest_repository.dart';

/// Contratto astratto per il motore di preflight dell'inferenza locale.
///
/// Esegue verifiche graduali sulla configurazione dell'ambiente di inferenza locale
/// (`llama-server` + modelli Actor/Evaluator) a profondità crescente.
abstract interface class LocalInferencePreflightEngine {
  /// Esegue la verifica di preflight all'interno del livello di profondità richiesto.
  ///
  /// - [PreflightDepth.quick]: controlli statici su configurazione e filesystem (< 100 ms).
  /// - [PreflightDepth.runtimeProbe]: include probe processuale con timeout 5s.
  /// - [PreflightDepth.fullModelLoad]: riservato al supervisor real-time; restituisce
  ///   sempre un esito documentato di non-disponibilità in questa implementazione.
  Future<LocalInferencePreflightResult> check({
    required PreflightDepth depth,
  });
}

/// Implementazione predefinita del motore di preflight.
final class DefaultLocalInferencePreflightEngine
    implements LocalInferencePreflightEngine {
  final BundledRuntimeResolver _runtimeResolver;
  final JsonModelConfigurationRepository _configurationRepository;
  final InstallationRecordRepository _installationRecordRepository;
  final LlamaServerDependencyService _dependencyService;
  final ProvisioningFileSystem _fileSystem;
  final ProvisioningPathResolver _pathResolver;

  DefaultLocalInferencePreflightEngine({
    required JsonModelConfigurationRepository configurationRepository,
    required InstallationRecordRepository installationRecordRepository,
    required LlamaServerDependencyService dependencyService,
    required ProvisioningFileSystem fileSystem,
    required ProvisioningPathResolver pathResolver,
    BundledRuntimeResolver? runtimeResolver,
  })  : _configurationRepository = configurationRepository,
        _installationRecordRepository = installationRecordRepository,
        _dependencyService = dependencyService,
        _fileSystem = fileSystem,
        _pathResolver = pathResolver,
        _runtimeResolver = runtimeResolver ??
            DefaultBundledRuntimeResolver(
              manifestRepository: DefaultRuntimeManifestRepository(
                fileSystem: fileSystem,
                pathResolver: pathResolver,
              ),
              fileSystem: fileSystem,
              pathResolver: pathResolver,
            );

  @override
  Future<LocalInferencePreflightResult> check({
    required PreflightDepth depth,
  }) async {
    // fullModelLoad è out-of-scope: richiede un supervisor real-time dedicato
    if (depth == PreflightDepth.fullModelLoad) {
      return const LocalInferencePreflightResult.failed(
        reason: LocalInferencePreflightFailure.runtimeStartupFailed,
        message:
            'Il preflight fullModelLoad richiede un supervisor real-time e '
            'non è disponibile in questa implementazione statica. '
            'Usare il runtime supervisor nella fase 6.4f.8+.',
      );
    }

    final configRecord = await _configurationRepository.readRecord();

    // 1. Risoluzione portabile del runtime configurato
    final runtimeConfig = configRecord.runtime;
    if (runtimeConfig == null) {
      return const LocalInferencePreflightResult.failed(
        reason: LocalInferencePreflightFailure.runtimeNotConfigured,
        message: 'Nessun eseguibile llama-server è stato configurato. '
            'Utilizza le impostazioni per selezionare il percorso dell\'eseguibile.',
      );
    }

    ResolvedLlamaRuntime? resolvedRuntime;
    try {
      resolvedRuntime = await _runtimeResolver.resolve(runtimeConfig);
    } catch (e) {
      return LocalInferencePreflightResult.failed(
        reason: LocalInferencePreflightFailure.runtimeInvalid,
        message: 'Impossibile risolvere il runtime configurato: $e',
        runtimeConfiguration: runtimeConfig,
      );
    }

    if (resolvedRuntime == null) {
      return LocalInferencePreflightResult.failed(
        reason: LocalInferencePreflightFailure.runtimeMissing,
        message:
            'L\'eseguibile llama-server configurato non è presente sul disco o il manifest è mancante.',
        runtimeConfiguration: runtimeConfig,
      );
    }

    final execPath = resolvedRuntime.executablePath;

    // 2. Verifica fisica rapida del file runtime risolto
    if (!await _fileSystem.fileExists(execPath)) {
      return LocalInferencePreflightResult.failed(
        reason: LocalInferencePreflightFailure.runtimeMissing,
        message: 'L\'eseguibile llama-server non è presente sul disco.',
        runtimeConfiguration: runtimeConfig,
      );
    }

    // 3. Verifica dimensione > 0 del file runtime
    try {
      final size = await _fileSystem.getFileSize(execPath);
      if (size <= 0) {
        return LocalInferencePreflightResult.failed(
          reason: LocalInferencePreflightFailure.runtimeInvalid,
          message:
              'L\'eseguibile llama-server ha dimensione non valida (0 byte).',
          runtimeConfiguration: runtimeConfig,
        );
      }
    } catch (_) {
      return LocalInferencePreflightResult.failed(
        reason: LocalInferencePreflightFailure.runtimeInvalid,
        message:
            'Impossibile leggere la dimensione dell\'eseguibile llama-server.',
        runtimeConfiguration: runtimeConfig,
      );
    }

    // 4. Verifica modello Actor configurato
    final modelConfig = configRecord.models;
    final actorRef = modelConfig.actor;
    if (actorRef == null) {
      return LocalInferencePreflightResult.failed(
        reason: LocalInferencePreflightFailure.actorNotConfigured,
        message: 'Nessun modello Actor è stato configurato. '
            'Configura un modello per il ruolo Actor nelle impostazioni.',
        affectedRole: ModelActivationRole.actor,
        runtimeConfiguration: runtimeConfig,
        modelConfiguration: modelConfig,
      );
    }

    // 5. Verifica fisica del modello Actor
    final actorCheck = await _checkModelReference(actorRef);
    if (actorCheck != null) {
      return LocalInferencePreflightResult.failed(
        reason: actorCheck.failure,
        message: actorCheck.message,
        affectedRole: ModelActivationRole.actor,
        runtimeConfiguration: runtimeConfig,
        modelConfiguration: modelConfig,
      );
    }

    // 6. Verifica modello Evaluator configurato
    final evaluatorRef = modelConfig.evaluator;
    if (evaluatorRef == null) {
      return LocalInferencePreflightResult.failed(
        reason: LocalInferencePreflightFailure.evaluatorNotConfigured,
        message: 'Nessun modello Evaluator è stato configurato. '
            'Configura un modello per il ruolo Evaluator nelle impostazioni.',
        affectedRole: ModelActivationRole.evaluator,
        runtimeConfiguration: runtimeConfig,
        modelConfiguration: modelConfig,
      );
    }

    // 7. Verifica fisica del modello Evaluator
    final evaluatorCheck = await _checkModelReference(evaluatorRef);
    if (evaluatorCheck != null) {
      return LocalInferencePreflightResult.failed(
        reason: evaluatorCheck.failure,
        message: evaluatorCheck.message,
        affectedRole: ModelActivationRole.evaluator,
        runtimeConfiguration: runtimeConfig,
        modelConfiguration: modelConfig,
      );
    }

    // Per il livello quick: tutte le verifiche statiche sono superate
    if (depth == PreflightDepth.quick) {
      return LocalInferencePreflightResult.ready(
        runtimeConfiguration: runtimeConfig,
        modelConfiguration: modelConfig,
      );
    }

    // 8. runtimeProbe: probe processuale sull'eseguibile llama-server con metadati vendor
    assert(depth == PreflightDepth.runtimeProbe, 'Depth non gestita: $depth');

    final probeResult = await _dependencyService.validateExecutable(
      executablePath: execPath,
      variantId: resolvedRuntime.variantId,
      vendorDirectories: resolvedRuntime.vendorDirectories,
    );
    if (!probeResult.isValid) {
      return LocalInferencePreflightResult.failed(
        reason: LocalInferencePreflightFailure.runtimeInvalid,
        message: 'Il probe processuale di llama-server è fallito: '
            '${probeResult.errorMessage ?? probeResult.status.name}.',
        runtimeConfiguration: runtimeConfig,
        modelConfiguration: modelConfig,
      );
    }

    // Probe superato: aggiorna la configurazione runtime con versione rilevata
    final updatedConfig = runtimeConfig.copyWith(
      detectedVersion: probeResult.detectedVersion,
      lastValidatedAtUtc: probeResult.lastValidatedAtUtc,
      validationStatus: LlamaServerValidationStatus.valid,
    );

    return LocalInferencePreflightResult.ready(
      runtimeConfiguration: updatedConfig,
      modelConfiguration: modelConfig,
    );
  }

  /// Verifica la disponibilità fisica di un [ConfiguredModelReference].
  ///
  /// Restituisce `null` se la verifica è superata, altrimenti un [_ModelCheckFailure]
  /// con causa e messaggio tipizzati.
  Future<_ModelCheckFailure?> _checkModelReference(
    ConfiguredModelReference reference,
  ) async {
    switch (reference) {
      case ManagedModelReference(:final installationId):
        return _checkManagedModel(installationId);
      case ExternalModelReference(:final absolutePath):
        return _checkExternalModel(absolutePath);
    }
  }

  Future<_ModelCheckFailure?> _checkManagedModel(String installationId) async {
    final record = await _installationRecordRepository.readRecord();
    final descriptor = record.findInstallation(installationId);

    if (descriptor == null ||
        descriptor.status != InstallationStatus.verified ||
        descriptor.artifactType != CatalogArtifactType.model) {
      return _ModelCheckFailure(
        failure: LocalInferencePreflightFailure.managedInstallationUnavailable,
        message:
            'L\'installazione gestita "$installationId" non è disponibile, '
            'non è di tipo modello o non si trova nello stato "verified".',
      );
    }

    final installDir = _pathResolver.resolveAppManagedRelativePath(
      descriptor.relativeInstallPath,
    );
    final entryFileName = descriptor.entryFileName ?? '';
    final entryFilePath = '$installDir\\$entryFileName';

    if (!await _fileSystem.fileExists(entryFilePath)) {
      return _ModelCheckFailure(
        failure: LocalInferencePreflightFailure.managedInstallationUnavailable,
        message:
            'Il file payload dell\'installazione gestita "$installationId" '
            'non è presente sul disco ("$entryFilePath").',
      );
    }

    try {
      final size = await _fileSystem.getFileSize(entryFilePath);
      if (size <= 0) {
        return _ModelCheckFailure(
          failure:
              LocalInferencePreflightFailure.managedInstallationUnavailable,
          message:
              'Il file payload dell\'installazione gestita "$installationId" '
              'ha dimensione non valida (0 byte).',
        );
      }
    } catch (_) {
      return _ModelCheckFailure(
        failure: LocalInferencePreflightFailure.managedInstallationUnavailable,
        message:
            'Impossibile leggere la dimensione del file payload dell\'installazione '
            'gestita "$installationId".',
      );
    }

    return null;
  }

  Future<_ModelCheckFailure?> _checkExternalModel(
    String absolutePath,
  ) async {
    final cleanPath = absolutePath.trim();
    if (!cleanPath.toLowerCase().endsWith('.gguf')) {
      return _ModelCheckFailure(
        failure: LocalInferencePreflightFailure.externalModelUnreadable,
        message:
            'Il file specificato per il modello esterno non ha estensione ".gguf": "$cleanPath".',
      );
    }

    if (!await _fileSystem.fileExists(cleanPath)) {
      return _ModelCheckFailure(
        failure: LocalInferencePreflightFailure.externalModelMissing,
        message: 'Il file GGUF esterno non è presente sul disco: "$cleanPath".',
      );
    }

    try {
      final size = await _fileSystem.getFileSize(cleanPath);
      if (size <= 0) {
        return _ModelCheckFailure(
          failure: LocalInferencePreflightFailure.externalModelUnreadable,
          message: 'Il file GGUF esterno ha dimensione non valida (0 byte): '
              '"$cleanPath".',
        );
      }
    } catch (_) {
      return _ModelCheckFailure(
        failure: LocalInferencePreflightFailure.externalModelUnreadable,
        message: 'Impossibile leggere la dimensione del file GGUF esterno: '
            '"$cleanPath".',
      );
    }

    return null;
  }
}

/// DTO interno per veicolare una causa di fallimento da un metodo di controllo modello.
final class _ModelCheckFailure {
  final LocalInferencePreflightFailure failure;
  final String message;

  const _ModelCheckFailure({
    required this.failure,
    required this.message,
  });
}
