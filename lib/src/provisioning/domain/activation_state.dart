import 'package:meta/meta.dart';
import 'json_safe_value.dart';
import 'provisioning_options.dart';

const Object _unset = Object();

/// Preferenza per la sorgente del runtime di inferenza.
enum RuntimeSourcePreference {
  appManaged,
  bundled;

  static RuntimeSourcePreference parse(String value) {
    for (final pref in RuntimeSourcePreference.values) {
      if (pref.name == value.trim()) {
        return pref;
      }
    }
    throw ProvisioningException(
      reason: ProvisioningFailureReason.catalogMalformed,
      message: 'RuntimeSourcePreference non valida: "$value".',
    );
  }
}

/// Policy di fallback per la gestione di errori durante il bootstrap/inferenza.
enum ProvisionedFallbackPolicy {
  managedLlamaServerWithRuleBasedFallback,
  managedLlamaServerOnly,
  ruleBasedOnly;

  static ProvisionedFallbackPolicy parse(String value) {
    for (final policy in ProvisionedFallbackPolicy.values) {
      if (policy.name == value.trim()) {
        return policy;
      }
    }
    throw ProvisioningException(
      reason: ProvisioningFailureReason.catalogMalformed,
      message: 'ProvisionedFallbackPolicy non valida: "$value".',
    );
  }
}

/// Rappresenta lo stato di attivazione corrente del runtime e dei modelli referenziati da ruoli specifici (Actor ed Evaluator).
@immutable
final class ActivationState {
  final String schemaVersion;
  final String updatedAt;
  final String? activeRuntimeInstallationId;
  final String? activeActorModelInstallationId;
  final String? activeEvaluatorModelInstallationId;
  final String? lastKnownGoodRuntimeInstallationId;
  final String? lastKnownGoodActorModelInstallationId;
  final String? lastKnownGoodEvaluatorModelInstallationId;
  final RuntimeSourcePreference runtimeSourcePreference;
  final ProvisionedFallbackPolicy fallbackPolicy;
  final bool explicitUserSelection;
  final String? selectedModelAlias;
  final Map<String, dynamic> metadata;

  ActivationState({
    this.schemaVersion = '1.1',
    required this.updatedAt,
    this.activeRuntimeInstallationId,
    String? activeModelInstallationId,
    String? activeActorModelInstallationId,
    this.activeEvaluatorModelInstallationId,
    this.lastKnownGoodRuntimeInstallationId,
    String? lastKnownGoodModelInstallationId,
    String? lastKnownGoodActorModelInstallationId,
    this.lastKnownGoodEvaluatorModelInstallationId,
    this.runtimeSourcePreference = RuntimeSourcePreference.appManaged,
    this.fallbackPolicy =
        ProvisionedFallbackPolicy.managedLlamaServerWithRuleBasedFallback,
    this.explicitUserSelection = false,
    this.selectedModelAlias,
    Map<String, dynamic> metadata = const {},
  })  : activeActorModelInstallationId =
            activeActorModelInstallationId ?? activeModelInstallationId,
        lastKnownGoodActorModelInstallationId =
            lastKnownGoodActorModelInstallationId ??
                lastKnownGoodModelInstallationId,
        metadata = JsonSafeValue.ensureJsonSafeMap(metadata) {
    if (DateTime.tryParse(updatedAt) == null) {
      throw ProvisioningException(
        reason: ProvisioningFailureReason.catalogMalformed,
        message: 'Timestamp updatedAt ISO-8601 non valido: "$updatedAt".',
      );
    }
  }

  /// Compatibility getter per l'installazione attiva predefinita del modello (Actor).
  String? get activeModelInstallationId =>
      activeActorModelInstallationId ?? activeEvaluatorModelInstallationId;

  /// Compatibility getter per lastKnownGood del modello predefinito (Actor).
  String? get lastKnownGoodModelInstallationId =>
      lastKnownGoodActorModelInstallationId ??
      lastKnownGoodEvaluatorModelInstallationId;

  factory ActivationState.empty({required String updatedAt}) {
    return ActivationState(
      schemaVersion: '1.1',
      updatedAt: updatedAt,
    );
  }

  factory ActivationState.fromJson(Map<String, dynamic> json) {
    try {
      final rawSchema = json['schemaVersion'] as String?;
      if (rawSchema == null || rawSchema.trim().isEmpty) {
        throw const ProvisioningException(
          reason: ProvisioningFailureReason.activationStateReadFailed,
          message: 'Campo obbligatorio mancante: schemaVersion.',
        );
      }

      final cleanSchema = rawSchema.trim();
      if (cleanSchema != '1.0' && cleanSchema != '1.1') {
        throw ProvisioningException(
          reason: ProvisioningFailureReason.unsupportedSchemaVersion,
          message:
              'Versione di schema non supportata: "$rawSchema". Attese: "1.0" o "1.1".',
        );
      }

      final rawUpdatedAt = json['updatedAt'] as String?;
      if (rawUpdatedAt == null || rawUpdatedAt.trim().isEmpty) {
        throw const ProvisioningException(
          reason: ProvisioningFailureReason.activationStateReadFailed,
          message: 'Campo obbligatorio mancante: updatedAt.',
        );
      }

      final rawPref =
          (json['runtimeSourcePreference'] as String?) ?? 'appManaged';
      final rawFallback = (json['fallbackPolicy'] as String?) ??
          'managedLlamaServerWithRuleBasedFallback';

      final activeActor = (json['activeActorModelInstallationId'] as String?) ??
          (json['activeModelInstallationId'] as String?);
      final activeEval = json['activeEvaluatorModelInstallationId'] as String?;

      final lkgActor =
          (json['lastKnownGoodActorModelInstallationId'] as String?) ??
              (json['lastKnownGoodModelInstallationId'] as String?);
      final lkgEval =
          json['lastKnownGoodEvaluatorModelInstallationId'] as String?;

      return ActivationState(
        schemaVersion: cleanSchema,
        updatedAt: rawUpdatedAt,
        activeRuntimeInstallationId:
            json['activeRuntimeInstallationId'] as String?,
        activeActorModelInstallationId: activeActor,
        activeEvaluatorModelInstallationId: activeEval,
        lastKnownGoodRuntimeInstallationId:
            json['lastKnownGoodRuntimeInstallationId'] as String?,
        lastKnownGoodActorModelInstallationId: lkgActor,
        lastKnownGoodEvaluatorModelInstallationId: lkgEval,
        runtimeSourcePreference: RuntimeSourcePreference.parse(rawPref),
        fallbackPolicy: ProvisionedFallbackPolicy.parse(rawFallback),
        explicitUserSelection: json['explicitUserSelection'] as bool? ?? false,
        selectedModelAlias: json['selectedModelAlias'] as String?,
        metadata: json['metadata'] != null
            ? Map<String, dynamic>.from(json['metadata'] as Map)
            : const {},
      );
    } on ProvisioningException {
      rethrow;
    } catch (_) {
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.activationStateReadFailed,
        message: 'Errore di parsing del file active_state.json.',
      );
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'schemaVersion': schemaVersion,
      'updatedAt': updatedAt,
      if (activeRuntimeInstallationId != null)
        'activeRuntimeInstallationId': activeRuntimeInstallationId,
      if (activeActorModelInstallationId != null)
        'activeActorModelInstallationId': activeActorModelInstallationId,
      if (activeEvaluatorModelInstallationId != null)
        'activeEvaluatorModelInstallationId':
            activeEvaluatorModelInstallationId,
      if (lastKnownGoodRuntimeInstallationId != null)
        'lastKnownGoodRuntimeInstallationId':
            lastKnownGoodRuntimeInstallationId,
      if (lastKnownGoodActorModelInstallationId != null)
        'lastKnownGoodActorModelInstallationId':
            lastKnownGoodActorModelInstallationId,
      if (lastKnownGoodEvaluatorModelInstallationId != null)
        'lastKnownGoodEvaluatorModelInstallationId':
            lastKnownGoodEvaluatorModelInstallationId,
      'runtimeSourcePreference': runtimeSourcePreference.name,
      'fallbackPolicy': fallbackPolicy.name,
      'explicitUserSelection': explicitUserSelection,
      if (selectedModelAlias != null) 'selectedModelAlias': selectedModelAlias,
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }

  ActivationState copyWith({
    String? schemaVersion,
    String? updatedAt,
    Object? activeRuntimeInstallationId = _unset,
    Object? activeModelInstallationId = _unset,
    Object? activeActorModelInstallationId = _unset,
    Object? activeEvaluatorModelInstallationId = _unset,
    Object? lastKnownGoodRuntimeInstallationId = _unset,
    Object? lastKnownGoodModelInstallationId = _unset,
    Object? lastKnownGoodActorModelInstallationId = _unset,
    Object? lastKnownGoodEvaluatorModelInstallationId = _unset,
    RuntimeSourcePreference? runtimeSourcePreference,
    ProvisionedFallbackPolicy? fallbackPolicy,
    bool? explicitUserSelection,
    Object? selectedModelAlias = _unset,
    Map<String, dynamic>? metadata,
  }) {
    final newActiveActor = identical(activeActorModelInstallationId, _unset)
        ? (identical(activeModelInstallationId, _unset)
            ? this.activeActorModelInstallationId
            : activeModelInstallationId as String?)
        : activeActorModelInstallationId as String?;

    final newLkgActor = identical(lastKnownGoodActorModelInstallationId, _unset)
        ? (identical(lastKnownGoodModelInstallationId, _unset)
            ? this.lastKnownGoodActorModelInstallationId
            : lastKnownGoodModelInstallationId as String?)
        : lastKnownGoodActorModelInstallationId as String?;

    return ActivationState(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      updatedAt: updatedAt ?? this.updatedAt,
      activeRuntimeInstallationId:
          identical(activeRuntimeInstallationId, _unset)
              ? this.activeRuntimeInstallationId
              : activeRuntimeInstallationId as String?,
      activeActorModelInstallationId: newActiveActor,
      activeEvaluatorModelInstallationId:
          identical(activeEvaluatorModelInstallationId, _unset)
              ? this.activeEvaluatorModelInstallationId
              : activeEvaluatorModelInstallationId as String?,
      lastKnownGoodRuntimeInstallationId:
          identical(lastKnownGoodRuntimeInstallationId, _unset)
              ? this.lastKnownGoodRuntimeInstallationId
              : lastKnownGoodRuntimeInstallationId as String?,
      lastKnownGoodActorModelInstallationId: newLkgActor,
      lastKnownGoodEvaluatorModelInstallationId:
          identical(lastKnownGoodEvaluatorModelInstallationId, _unset)
              ? this.lastKnownGoodEvaluatorModelInstallationId
              : lastKnownGoodEvaluatorModelInstallationId as String?,
      runtimeSourcePreference:
          runtimeSourcePreference ?? this.runtimeSourcePreference,
      fallbackPolicy: fallbackPolicy ?? this.fallbackPolicy,
      explicitUserSelection:
          explicitUserSelection ?? this.explicitUserSelection,
      selectedModelAlias: identical(selectedModelAlias, _unset)
          ? this.selectedModelAlias
          : selectedModelAlias as String?,
      metadata: metadata ?? this.metadata,
    );
  }
}
