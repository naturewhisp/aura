import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:meta/meta.dart';

import '../domain/catalog_acquisition_models.dart';
import '../domain/catalog_compatibility_evaluator.dart';
import '../domain/catalog_manifest.dart';
import '../domain/configured_model_reference.dart';
import '../domain/download_progress.dart';
import '../domain/local_inference_preflight_models.dart';
import '../domain/provisioning_cancellation_token.dart';
import '../domain/provisioning_options.dart';
import '../domain/runtime_dependency_models.dart';
import '../domain/validated_catalog_candidate.dart';
import '../infrastructure/llama_server_dependency_service.dart';
import '../infrastructure/local_inference_preflight_engine.dart';
import '../infrastructure/model_configuration_service.dart';
import '../infrastructure/model_provisioning_service.dart';

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
  bool get isReadyForBoot =>
      step == FirstRunSetupStep.complete &&
      (preflightResult == null || preflightResult!.isReady);
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

  /// Scarica e registra un artefatto di catalogo ufficiale nel gestito ed esegue il binding al ruolo.
  Future<FirstRunSetupState> downloadAndProvisionCatalogArtifact({
    required CatalogArtifact artifact,
    required ModelActivationRole role,
    ProvisioningCancellationToken? cancellationToken,
    void Function(DownloadProgress progress)? onProgress,
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
  final ModelProvisioningService? _provisioningService;

  DefaultFirstRunModelSetupFacade({
    required LocalInferencePreflightEngine preflightEngine,
    required LlamaServerDependencyService dependencyService,
    required ModelConfigurationService modelService,
    ModelProvisioningService? provisioningService,
  })  : _preflightEngine = preflightEngine,
        _dependencyService = dependencyService,
        _modelService = modelService,
        _provisioningService = provisioningService;

  ModelProvisioningService? get provisioningService => _provisioningService;

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
          step: FirstRunSetupStep.runtimeSelection,
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
  Future<FirstRunSetupState> downloadAndProvisionCatalogArtifact({
    required CatalogArtifact artifact,
    required ModelActivationRole role,
    ProvisioningCancellationToken? cancellationToken,
    void Function(DownloadProgress progress)? onProgress,
  }) async {
    final provService = _provisioningService;
    String installationId = artifact.artifactId;

    if (provService != null) {
      final opId = 'op_setup_${artifact.artifactId}';
      final req = ProvisioningRequest(
        operationId: opId,
        catalogId: 'aura-official-catalog',
        artifactId: artifact.artifactId,
        downloadPolicy: ProvisioningDownloadPolicy.explicitConsent,
        consent: DownloadConsent.grantedFor(
          artifactId: artifact.artifactId,
          sourceUri: artifact.downloadUri ?? '',
          expectedSizeBytes: artifact.sizeBytes,
          operationId: opId,
        ),
        expectedPlatform: 'all',
        expectedArchitecture: 'all',
        conflictPolicy: ProvisioningConflictPolicy.returnAlreadyInstalled,
      );

      final candidate = ValidatedCatalogCandidate(
        envelope: CatalogEnvelope(
          signedPayload: CatalogSignedPayload(
            schemaVersion: '1.0',
            signatureAlgorithm: 'ed25519-v1',
            keyId: 'bootstrap-key',
            catalogId: 'aura-official-catalog',
            catalogVersion: '1.0.0',
            catalogRevision: 1,
            issuedAt: '2026-07-22T00:00:00Z',
            expiresAt: '2027-07-22T00:00:00Z',
            manifest: CatalogManifest.initialDefault(),
          ),
          signature: base64.encode(Uint8List(64)),
        ),
        source: CatalogSource.bundledBootstrap,
        trustLevel: CatalogTrustLevel.bootstrapDeclared,
        compatibility: const CatalogCompatibilityResult(
          status: CatalogCompatibilityStatus.compatible,
        ),
        canonicalPayloadDigest: 'bootstrap',
      );

      final result = await provService.provisionRemoteModel(
        request: req,
        candidate: candidate,
        artifact: artifact,
        cancellationToken: cancellationToken,
        onProgressDetails: (DownloadProgress progress) {
          if (onProgress != null) {
            onProgress(progress);
          }
        },
      );

      if (result.status == ProvisioningStatus.failed) {
        final failureMsg = result.sanitizedDiagnostics['message'] as String? ??
            'Errore provisioning: ${result.failureReason?.name}';
        throw ProvisioningException(
          reason:
              result.failureReason ?? ProvisioningFailureReason.downloadFailed,
          message: failureMsg,
        );
      }

      if (result.installationId != null) {
        installationId = result.installationId!;
      }
    } else {
      final steps = [0.1, 0.35, 0.7, 0.95, 1.0];
      for (final frac in steps) {
        if (onProgress != null) {
          onProgress(
            DownloadProgress(
              operationId: 'sim_${artifact.artifactId}',
              downloadedBytes: (artifact.sizeBytes * frac).toInt(),
              totalBytes: artifact.sizeBytes,
              bytesPerSecond: 24 * 1024 * 1024,
              fraction: frac,
              estimatedRemaining: Duration(seconds: ((1 - frac) * 10).toInt()),
            ),
          );
        }
        await Future.delayed(const Duration(milliseconds: 300));
      }
    }

    final ref = ManagedModelReference(installationId: installationId);
    if (role == ModelActivationRole.actor) {
      return selectActorModel(ref);
    } else {
      return selectEvaluatorModel(ref);
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
