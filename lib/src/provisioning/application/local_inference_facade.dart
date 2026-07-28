import 'dart:async';

import '../domain/local_inference_preflight_models.dart';
import '../domain/model_configuration_models.dart';
import '../domain/runtime_dependency_models.dart';
import '../infrastructure/llama_server_dependency_service.dart';
import '../infrastructure/local_inference_preflight_engine.dart';
import '../infrastructure/model_configuration_service.dart';
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
}

/// Implementazione predefinita della facade di inferenza locale.
final class DefaultLocalInferenceFacade implements LocalInferenceFacade {
  final LocalInferencePreflightEngine _preflightEngine;
  final LlamaServerDependencyService _dependencyService;
  final ModelConfigurationService _modelConfigurationService;

  DefaultLocalInferenceFacade({
    required LocalInferencePreflightEngine preflightEngine,
    required LlamaServerDependencyService dependencyService,
    required ModelConfigurationService modelConfigurationService,
  })  : _preflightEngine = preflightEngine,
        _dependencyService = dependencyService,
        _modelConfigurationService = modelConfigurationService;

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
}
