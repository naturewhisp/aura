import 'dart:async';

import '../domain/catalog_manifest.dart';
import '../domain/installation_record.dart';
import '../domain/local_inference_preflight_models.dart';
import '../domain/model_configuration_models.dart';
import '../domain/runtime_dependency_models.dart';
import '../infrastructure/installation_record_repository.dart';
import '../infrastructure/llama_server_dependency_service.dart';
import '../infrastructure/local_inference_preflight_engine.dart';
import '../infrastructure/model_configuration_service.dart';
import '../infrastructure/process_ownership_record.dart';
import '../infrastructure/process_ownership_registry.dart';
import 'local_inference_models.dart';

/// Facade applicativa per la consultazione dello stato dell'inferenza locale,
/// l'esecuzione di preflight e la scansione di modelli/dipendenze.
abstract interface class LocalInferenceFacade {
  /// Restituisce lo snapshot consolidato dello stato dell'inferenza locale.
  Future<LocalInferenceSnapshot> getSnapshot();

  /// Esegue la verifica di preflight al livello di profondità richiesto.
  Future<LocalInferencePreflightResult> runPreflight({
    required PreflightDepth depth,
  });

  /// Esegue la discovery deterministica dell'eseguibile `llama-server`.
  Future<LlamaServerDetectionResult> detectRuntime();

  /// Esegue la scansione di candidati GGUF esterni in una cartella specifica o predefinita.
  Future<List<ExternalModelCandidate>> scanExternalCandidates({
    String? customPath,
  });

  /// Elenca le installazioni di modelli gestiti verificati presenti nello store locale.
  Future<List<InstalledArtifactDescriptor>> listManagedModels();

  /// Elenca i record dei processi managed attivi o registrati su disco.
  Future<List<ProcessOwnershipRecord>> listManagedProcesses();

  /// Esegue la bonifica deterministica dei processi AURA stale registrati.
  Future<List<ProcessOwnershipRecord>> cleanupStaleProcesses();
}

/// Implementazione predefinita della facade di inferenza locale.
final class DefaultLocalInferenceFacade implements LocalInferenceFacade {
  final LocalInferencePreflightEngine _preflightEngine;
  final LlamaServerDependencyService _dependencyService;
  final ModelConfigurationService _modelConfigurationService;
  final InstallationRecordRepository _installationRecordRepository;
  final ProcessOwnershipRegistry _processOwnershipRegistry;

  DefaultLocalInferenceFacade({
    required LocalInferencePreflightEngine preflightEngine,
    required LlamaServerDependencyService dependencyService,
    required ModelConfigurationService modelConfigurationService,
    required InstallationRecordRepository installationRecordRepository,
    required ProcessOwnershipRegistry processOwnershipRegistry,
  })  : _preflightEngine = preflightEngine,
        _dependencyService = dependencyService,
        _modelConfigurationService = modelConfigurationService,
        _installationRecordRepository = installationRecordRepository,
        _processOwnershipRegistry = processOwnershipRegistry;

  @override
  Future<LocalInferenceSnapshot> getSnapshot() async {
    final record = await _modelConfigurationService.readRecord();
    final consentValid =
        await _modelConfigurationService.isExternalModelConsentValid();
    final preflight = await _preflightEngine.check(depth: PreflightDepth.quick);

    return LocalInferenceSnapshot(
      runtimeConfiguration: record.runtime,
      modelConfiguration: record.models,
      isConsentValid: consentValid,
      lastPreflightResult: preflight,
    );
  }

  @override
  Future<LocalInferencePreflightResult> runPreflight({
    required PreflightDepth depth,
  }) {
    return _preflightEngine.check(depth: depth);
  }

  @override
  Future<LlamaServerDetectionResult> detectRuntime() {
    return _dependencyService.detect();
  }

  @override
  Future<List<ExternalModelCandidate>> scanExternalCandidates({
    String? customPath,
  }) {
    return _modelConfigurationService.scanExternalModelCandidates(
      customDirectoryPath: customPath,
    );
  }

  @override
  Future<List<InstalledArtifactDescriptor>> listManagedModels() async {
    final record = await _installationRecordRepository.readRecord();
    final models = record.installedArtifacts
        .where((artifact) =>
            artifact.status == InstallationStatus.verified &&
            artifact.artifactType == CatalogArtifactType.model)
        .toList();

    models.sort((a, b) {
      final nameCmp = a.displayName.compareTo(b.displayName);
      if (nameCmp != 0) return nameCmp;
      final versionCmp = a.version.compareTo(b.version);
      if (versionCmp != 0) return versionCmp;
      return a.installationId.compareTo(b.installationId);
    });

    return models;
  }

  @override
  Future<List<ProcessOwnershipRecord>> listManagedProcesses() {
    return _processOwnershipRegistry.listRecords();
  }

  @override
  Future<List<ProcessOwnershipRecord>> cleanupStaleProcesses() {
    return _processOwnershipRegistry.cleanupStaleProcesses();
  }
}
