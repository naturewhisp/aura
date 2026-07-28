import 'package:meta/meta.dart';

import 'model_configuration_models.dart';
import 'provisioning_options.dart';
import 'runtime_dependency_models.dart';

/// Livelli di profondità di preflight per l'inferenza locale.
enum PreflightDepth {
  /// Verifica rapida: configurazione presente, eseguibile leggibile, installazione managed verificata, file esterno leggibile con size > 0.
  quick,

  /// Probe processuale: esegue `--version` / `--help` con timeout per verificare l'eseguibile `llama-server`.
  runtimeProbe,

  /// Probe completo con avvio processuale ed tentativo di caricamento del modello (esclusivamente on-demand).
  fullModelLoad,
}

/// Cause tipizzate di fallimento della verifica di preflight dell'inferenza locale.
enum LocalInferencePreflightFailure {
  runtimeNotConfigured,
  runtimeMissing,
  runtimeInvalid,
  actorNotConfigured,
  evaluatorNotConfigured,
  managedInstallationUnavailable,
  externalModelMissing,
  externalModelUnreadable,
  portUnavailable,
  runtimeStartupFailed,
  modelLoadFailed,
}

/// Esito diagnostico completo della verifica di preflight dell'inferenza locale.
@immutable
final class LocalInferencePreflightResult {
  final bool isReady;
  final LocalInferencePreflightFailure? failureReason;
  final String? sanitizedMessage;
  final ModelActivationRole? affectedRole;
  final LlamaServerConfiguration? runtimeConfiguration;
  final ModelRoleConfiguration? modelConfiguration;

  const LocalInferencePreflightResult({
    required this.isReady,
    this.failureReason,
    this.sanitizedMessage,
    this.affectedRole,
    this.runtimeConfiguration,
    this.modelConfiguration,
  });

  const LocalInferencePreflightResult.ready({
    this.runtimeConfiguration,
    this.modelConfiguration,
  })  : isReady = true,
        failureReason = null,
        sanitizedMessage = null,
        affectedRole = null;

  const LocalInferencePreflightResult.failed({
    required LocalInferencePreflightFailure reason,
    required String message,
    this.affectedRole,
    this.runtimeConfiguration,
    this.modelConfiguration,
  })  : isReady = false,
        failureReason = reason,
        sanitizedMessage = message;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LocalInferencePreflightResult &&
          runtimeType == other.runtimeType &&
          isReady == other.isReady &&
          failureReason == other.failureReason &&
          sanitizedMessage == other.sanitizedMessage &&
          affectedRole == other.affectedRole &&
          runtimeConfiguration == other.runtimeConfiguration &&
          modelConfiguration == other.modelConfiguration;

  @override
  int get hashCode => Object.hash(
        isReady,
        failureReason,
        sanitizedMessage,
        affectedRole,
        runtimeConfiguration,
        modelConfiguration,
      );

  @override
  String toString() =>
      'LocalInferencePreflightResult(ready: $isReady, reason: ${failureReason?.name}, role: ${affectedRole?.name}, msg: $sanitizedMessage)';
}
