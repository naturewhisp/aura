import 'package:meta/meta.dart';

import '../domain/local_inference_preflight_models.dart';
import '../domain/model_configuration_models.dart';
import '../domain/runtime_dependency_models.dart';

/// Snapshot immutabile che racchiude la configurazione complessiva e l'esito di preflight dell'inferenza locale.
@immutable
final class LocalInferenceSnapshot {
  final LlamaServerConfiguration? runtimeConfiguration;
  final ModelRoleConfiguration modelConfiguration;
  final bool isConsentValid;
  final LocalInferencePreflightResult lastPreflightResult;

  const LocalInferenceSnapshot({
    required this.runtimeConfiguration,
    required this.modelConfiguration,
    required this.isConsentValid,
    required this.lastPreflightResult,
  });

  /// Restituisce `true` se l'ambiente di inferenza locale è completamente configurato e pronto.
  bool get isReady => lastPreflightResult.isReady;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LocalInferenceSnapshot &&
          runtimeType == other.runtimeType &&
          runtimeConfiguration == other.runtimeConfiguration &&
          modelConfiguration == other.modelConfiguration &&
          isConsentValid == other.isConsentValid &&
          lastPreflightResult == other.lastPreflightResult;

  @override
  int get hashCode => Object.hash(
        runtimeConfiguration,
        modelConfiguration,
        isConsentValid,
        lastPreflightResult,
      );

  @override
  String toString() =>
      'LocalInferenceSnapshot(ready: $isReady, runtime: ${runtimeConfiguration?.executablePath}, actor: ${modelConfiguration.actor}, evaluator: ${modelConfiguration.evaluator})';
}
