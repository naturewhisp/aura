import 'dart:async';
import 'package:meta/meta.dart';

import '../domain/configured_model_reference.dart';
import '../domain/local_inference_preflight_models.dart';
import '../domain/provisioning_options.dart';
import '../domain/runtime_dependency_models.dart';
import '../infrastructure/llama_server_dependency_service.dart';
import '../infrastructure/local_inference_preflight_engine.dart';
import '../infrastructure/model_configuration_service.dart';

/// Passi del flusso di onboarding / first run setup dell'inferenza locale.
enum FirstRunSetupStep {
  initialCheck,
  runtimeSelection,
  actorSelection,
  evaluatorSelection,
  consentRequired,
  preflightCheck,
  complete,
  failed,
}

/// DTO immutabile che rappresenta lo stato dello stepper di configurazione iniziale.
@immutable
final class FirstRunSetupState {
  final FirstRunSetupStep step;
  final LocalInferencePreflightResult? preflightResult;
  final LlamaServerDetectionResult? runtimeDetectionResult;
  final String? errorMessage;
  final bool isOperationInProgress;

  const FirstRunSetupState({
    required this.step,
    this.preflightResult,
    this.runtimeDetectionResult,
    this.errorMessage,
    this.isOperationInProgress = false,
  });

  bool get isComplete => step == FirstRunSetupStep.complete;
  bool get hasError =>
      errorMessage != null ||
      (preflightResult != null && !preflightResult!.isReady);

  FirstRunSetupState copyWith({
    FirstRunSetupStep? step,
    Object? preflightResult = _unset,
    Object? runtimeDetectionResult = _unset,
    Object? errorMessage = _unset,
    bool? isOperationInProgress,
  }) {
    return FirstRunSetupState(
      step: step ?? this.step,
      preflightResult: identical(preflightResult, _unset)
          ? this.preflightResult
          : preflightResult as LocalInferencePreflightResult?,
      runtimeDetectionResult: identical(runtimeDetectionResult, _unset)
          ? this.runtimeDetectionResult
          : runtimeDetectionResult as LlamaServerDetectionResult?,
      errorMessage: identical(errorMessage, _unset)
          ? this.errorMessage
          : errorMessage as String?,
      isOperationInProgress:
          isOperationInProgress ?? this.isOperationInProgress,
    );
  }

  static const Object _unset = Object();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FirstRunSetupState &&
          runtimeType == other.runtimeType &&
          step == other.step &&
          preflightResult == other.preflightResult &&
          runtimeDetectionResult == other.runtimeDetectionResult &&
          errorMessage == other.errorMessage &&
          isOperationInProgress == other.isOperationInProgress;

  @override
  int get hashCode => Object.hash(
        step,
        preflightResult,
        runtimeDetectionResult,
        errorMessage,
        isOperationInProgress,
      );

  @override
  String toString() =>
      'FirstRunSetupState(step: ${step.name}, complete: $isComplete, err: $errorMessage)';
}

/// Facade per la guida e l'orchestrazione del flusso di prima configurazione.
abstract interface class FirstRunModelSetupFacade {
  /// Valuta lo stato iniziale dell'ambiente per determinare il primo passo richiesto.
  Future<FirstRunSetupState> evaluateInitialState();

  /// Configura l'eseguibile `llama-server` e fa progredire il flusso.
  Future<FirstRunSetupState> configureRuntime(String executablePath);

  /// Assegna il modello per il ruolo Actor e fa progredire il flusso.
  Future<FirstRunSetupState> selectActorModel(ConfiguredModelReference ref);

  /// Assegna il modello per il ruolo Evaluator e fa progredire il flusso.
  Future<FirstRunSetupState> selectEvaluatorModel(ConfiguredModelReference ref);

  /// Registra il consenso informato e ritenta il binding del modello Actor in modo stateless.
  Future<FirstRunSetupState> acceptConsentAndBindActor(
    ExternalModelReference reference,
  );

  /// Registra il consenso informato e ritenta il binding del modello Evaluator in modo stateless.
  Future<FirstRunSetupState> acceptConsentAndBindEvaluator(
    ExternalModelReference reference,
  );

  /// Registra il consenso informato per i modelli esterni e ritenta il passo bloccato per il ruolo specificato.
  Future<FirstRunSetupState> acceptConsentAndRetry({
    required ModelActivationRole role,
    required ExternalModelReference reference,
  });

  /// Esegue la verifica finale `runtimeProbe` per completare l'onboarding.
  Future<FirstRunSetupState> runFinalPreflight();
}

/// Implementazione predefinita dell'orchestratore di first run setup.
final class DefaultFirstRunModelSetupFacade
    implements FirstRunModelSetupFacade {
  final LocalInferencePreflightEngine _preflightEngine;
  final LlamaServerDependencyService _dependencyService;
  final ModelConfigurationService _modelService;

  DefaultFirstRunModelSetupFacade({
    required LocalInferencePreflightEngine preflightEngine,
    required LlamaServerDependencyService dependencyService,
    required ModelConfigurationService modelService,
  })  : _preflightEngine = preflightEngine,
        _dependencyService = dependencyService,
        _modelService = modelService;

  @override
  Future<FirstRunSetupState> evaluateInitialState() async {
    final preflight = await _preflightEngine.check(depth: PreflightDepth.quick);
    final detection = await _dependencyService.detect();

    if (preflight.isReady) {
      final probeResult =
          await _preflightEngine.check(depth: PreflightDepth.runtimeProbe);
      if (probeResult.isReady) {
        return FirstRunSetupState(
          step: FirstRunSetupStep.complete,
          preflightResult: probeResult,
          runtimeDetectionResult: detection,
        );
      } else {
        return FirstRunSetupState(
          step: FirstRunSetupStep.failed,
          preflightResult: probeResult,
          runtimeDetectionResult: detection,
          errorMessage: probeResult.sanitizedMessage,
        );
      }
    }

    // Se preflight individua il ruolo specifico che necessita di intervento:
    if (preflight.affectedRole == ModelActivationRole.actor) {
      return FirstRunSetupState(
        step: FirstRunSetupStep.actorSelection,
        preflightResult: preflight,
        runtimeDetectionResult: detection,
      );
    }

    if (preflight.affectedRole == ModelActivationRole.evaluator) {
      return FirstRunSetupState(
        step: FirstRunSetupStep.evaluatorSelection,
        preflightResult: preflight,
        runtimeDetectionResult: detection,
      );
    }

    // Fallback in base alla causa di fallimento runtime
    switch (preflight.failureReason) {
      case LocalInferencePreflightFailure.runtimeNotConfigured:
      case LocalInferencePreflightFailure.runtimeMissing:
      case LocalInferencePreflightFailure.runtimeInvalid:
        return FirstRunSetupState(
          step: FirstRunSetupStep.runtimeSelection,
          preflightResult: preflight,
          runtimeDetectionResult: detection,
        );

      default:
        return FirstRunSetupState(
          step: FirstRunSetupStep.runtimeSelection,
          preflightResult: preflight,
          runtimeDetectionResult: detection,
        );
    }
  }

  @override
  Future<FirstRunSetupState> configureRuntime(String executablePath) async {
    final validation = await _dependencyService.validateExecutable(
      executablePath: executablePath,
    );
    if (!validation.isValid) {
      return FirstRunSetupState(
        step: FirstRunSetupStep.runtimeSelection,
        errorMessage:
            'Eseguibile non valido: ${validation.errorMessage ?? validation.status.name}',
      );
    }

    await _dependencyService.configureExecutable(
        executablePath: executablePath);
    return evaluateInitialState();
  }

  @override
  Future<FirstRunSetupState> selectActorModel(
      ConfiguredModelReference ref) async {
    final result = await _modelService.bindActorModel(ref);
    if (!result.isValid) {
      if (ref is ExternalModelReference &&
          !await _modelService.isExternalModelConsentValid()) {
        return FirstRunSetupState(
          step: FirstRunSetupStep.consentRequired,
          errorMessage: result.errorMessage,
        );
      }
      return FirstRunSetupState(
        step: FirstRunSetupStep.actorSelection,
        errorMessage: result.errorMessage,
      );
    }

    return evaluateInitialState();
  }

  @override
  Future<FirstRunSetupState> selectEvaluatorModel(
      ConfiguredModelReference ref) async {
    final result = await _modelService.bindEvaluatorModel(ref);
    if (!result.isValid) {
      if (ref is ExternalModelReference &&
          !await _modelService.isExternalModelConsentValid()) {
        return FirstRunSetupState(
          step: FirstRunSetupStep.consentRequired,
          errorMessage: result.errorMessage,
        );
      }
      return FirstRunSetupState(
        step: FirstRunSetupStep.evaluatorSelection,
        errorMessage: result.errorMessage,
      );
    }

    return evaluateInitialState();
  }

  @override
  Future<FirstRunSetupState> acceptConsentAndBindActor(
    ExternalModelReference reference,
  ) async {
    await _modelService.recordExternalModelConsent();
    return selectActorModel(reference);
  }

  @override
  Future<FirstRunSetupState> acceptConsentAndBindEvaluator(
    ExternalModelReference reference,
  ) async {
    await _modelService.recordExternalModelConsent();
    return selectEvaluatorModel(reference);
  }

  @override
  Future<FirstRunSetupState> acceptConsentAndRetry({
    required ModelActivationRole role,
    required ExternalModelReference reference,
  }) async {
    await _modelService.recordExternalModelConsent();
    switch (role) {
      case ModelActivationRole.actor:
        return selectActorModel(reference);
      case ModelActivationRole.evaluator:
        return selectEvaluatorModel(reference);
    }
  }

  @override
  Future<FirstRunSetupState> runFinalPreflight() async {
    final result =
        await _preflightEngine.check(depth: PreflightDepth.runtimeProbe);
    if (result.isReady) {
      return FirstRunSetupState(
        step: FirstRunSetupStep.complete,
        preflightResult: result,
      );
    } else {
      return FirstRunSetupState(
        step: FirstRunSetupStep.failed,
        preflightResult: result,
        errorMessage: result.sanitizedMessage,
      );
    }
  }
}
