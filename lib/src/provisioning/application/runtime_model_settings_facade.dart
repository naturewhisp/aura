import 'dart:async';

import '../domain/configured_model_reference.dart';
import '../domain/model_configuration_models.dart';
import '../domain/runtime_dependency_models.dart';
import '../infrastructure/llama_server_dependency_service.dart';
import '../infrastructure/model_configuration_service.dart';
import '../infrastructure/winget_dependency_adapter.dart';

/// Facade applicativa per la gestione delle impostazioni del runtime `llama-server`,
/// l'assegnazione dei ruoli Actor/Evaluator ed il consenso informato.
abstract interface class RuntimeModelSettingsFacade {
  /// Configura e valida un nuovo percorso dell'eseguibile `llama-server`.
  Future<LlamaServerConfiguration> setRuntimeExecutable(String path);

  /// Rimuove la configurazione attuale del runtime.
  Future<void> clearRuntimeExecutable();

  /// Associa un riferimento di modello (managed o external) al ruolo Actor.
  Future<ModelBindingValidationResult> bindActor(ConfiguredModelReference ref);

  /// Rimuove l'assegnazione del modello Actor.
  Future<void> clearActorBinding();

  /// Associa un riferimento di modello (managed o external) al ruolo Evaluator.
  Future<ModelBindingValidationResult> bindEvaluator(
      ConfiguredModelReference ref);

  /// Rimuove l'assegnazione del modello Evaluator.
  Future<void> clearEvaluatorBinding();

  /// Registra il consenso informato dell'utente per l'uso di modelli esterni GGUF.
  Future<ExternalModelConsent> recordConsent();

  /// Verifica se il consenso informato corrente è valido.
  Future<bool> isConsentValid();

  /// Genera l'assistenza all'installazione via WinGet per `llama-server`.
  Future<InstallationAssistance> getWinGetAssistance({String? customPackageId});

  /// Verifica se l'utility WinGet è disponibile nel sistema.
  Future<bool> isWinGetAvailable();
}

/// Implementazione predefinita della facade delle impostazioni runtime e modelli.
final class DefaultRuntimeModelSettingsFacade
    implements RuntimeModelSettingsFacade {
  final LlamaServerDependencyService _dependencyService;
  final ModelConfigurationService _modelService;
  final WinGetDependencyAdapter _winGetAdapter;

  DefaultRuntimeModelSettingsFacade({
    required LlamaServerDependencyService dependencyService,
    required ModelConfigurationService modelService,
    required WinGetDependencyAdapter winGetAdapter,
  })  : _dependencyService = dependencyService,
        _modelService = modelService,
        _winGetAdapter = winGetAdapter;

  @override
  Future<LlamaServerConfiguration> setRuntimeExecutable(String path) {
    return _dependencyService.configureExecutable(executablePath: path);
  }

  @override
  Future<void> clearRuntimeExecutable() {
    return _dependencyService.clearConfiguration();
  }

  @override
  Future<ModelBindingValidationResult> bindActor(ConfiguredModelReference ref) {
    return _modelService.bindActorModel(ref);
  }

  @override
  Future<void> clearActorBinding() {
    return _modelService.clearActorBinding();
  }

  @override
  Future<ModelBindingValidationResult> bindEvaluator(
      ConfiguredModelReference ref) {
    return _modelService.bindEvaluatorModel(ref);
  }

  @override
  Future<void> clearEvaluatorBinding() {
    return _modelService.clearEvaluatorBinding();
  }

  @override
  Future<ExternalModelConsent> recordConsent() {
    return _modelService.recordExternalModelConsent();
  }

  @override
  Future<bool> isConsentValid() {
    return _modelService.isExternalModelConsentValid();
  }

  @override
  Future<InstallationAssistance> getWinGetAssistance(
      {String? customPackageId}) {
    return _winGetAdapter.getAssistance(customPackageId: customPackageId);
  }

  @override
  Future<bool> isWinGetAvailable() {
    return _winGetAdapter.checkWinGetAvailable();
  }
}
