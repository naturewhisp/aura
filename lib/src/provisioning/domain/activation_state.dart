import 'package:meta/meta.dart';
import 'json_safe_value.dart';
import 'provisioning_options.dart';

const Object _unset = Object();

/// Rappresenta lo stato di attivazione corrente del runtime e del modello riferito ad installazioni stabili.
@immutable
final class ActivationState {
  final String schemaVersion;
  final String updatedAt;
  final String? activeRuntimeInstallationId;
  final String? activeModelInstallationId;
  final String? lastKnownGoodRuntimeInstallationId;
  final String? lastKnownGoodModelInstallationId;
  final String runtimeSourcePreference;
  final String fallbackPolicy;
  final bool explicitUserSelection;
  final String? selectedModelAlias;
  final Map<String, dynamic> metadata;

  ActivationState({
    this.schemaVersion = '1.0',
    required this.updatedAt,
    this.activeRuntimeInstallationId,
    this.activeModelInstallationId,
    this.lastKnownGoodRuntimeInstallationId,
    this.lastKnownGoodModelInstallationId,
    this.runtimeSourcePreference = 'appManaged',
    this.fallbackPolicy = 'managedLlamaServerWithRuleBasedFallback',
    this.explicitUserSelection = false,
    this.selectedModelAlias,
    Map<String, dynamic> metadata = const {},
  }) : metadata = JsonSafeValue.ensureJsonSafeMap(metadata);

  factory ActivationState.empty({required String updatedAt}) {
    return ActivationState(
      schemaVersion: '1.0',
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

      final rawUpdatedAt = json['updatedAt'] as String?;
      if (rawUpdatedAt == null || rawUpdatedAt.trim().isEmpty) {
        throw const ProvisioningException(
          reason: ProvisioningFailureReason.activationStateReadFailed,
          message: 'Campo obbligatorio mancante: updatedAt.',
        );
      }

      return ActivationState(
        schemaVersion: rawSchema,
        updatedAt: rawUpdatedAt,
        activeRuntimeInstallationId:
            json['activeRuntimeInstallationId'] as String?,
        activeModelInstallationId: json['activeModelInstallationId'] as String?,
        lastKnownGoodRuntimeInstallationId:
            json['lastKnownGoodRuntimeInstallationId'] as String?,
        lastKnownGoodModelInstallationId:
            json['lastKnownGoodModelInstallationId'] as String?,
        runtimeSourcePreference:
            (json['runtimeSourcePreference'] as String?) ?? 'appManaged',
        fallbackPolicy: (json['fallbackPolicy'] as String?) ??
            'managedLlamaServerWithRuleBasedFallback',
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
      if (activeModelInstallationId != null)
        'activeModelInstallationId': activeModelInstallationId,
      if (lastKnownGoodRuntimeInstallationId != null)
        'lastKnownGoodRuntimeInstallationId':
            lastKnownGoodRuntimeInstallationId,
      if (lastKnownGoodModelInstallationId != null)
        'lastKnownGoodModelInstallationId': lastKnownGoodModelInstallationId,
      'runtimeSourcePreference': runtimeSourcePreference,
      'fallbackPolicy': fallbackPolicy,
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
    Object? lastKnownGoodRuntimeInstallationId = _unset,
    Object? lastKnownGoodModelInstallationId = _unset,
    String? runtimeSourcePreference,
    String? fallbackPolicy,
    bool? explicitUserSelection,
    Object? selectedModelAlias = _unset,
    Map<String, dynamic>? metadata,
  }) {
    return ActivationState(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      updatedAt: updatedAt ?? this.updatedAt,
      activeRuntimeInstallationId:
          identical(activeRuntimeInstallationId, _unset)
              ? this.activeRuntimeInstallationId
              : activeRuntimeInstallationId as String?,
      activeModelInstallationId: identical(activeModelInstallationId, _unset)
          ? this.activeModelInstallationId
          : activeModelInstallationId as String?,
      lastKnownGoodRuntimeInstallationId:
          identical(lastKnownGoodRuntimeInstallationId, _unset)
              ? this.lastKnownGoodRuntimeInstallationId
              : lastKnownGoodRuntimeInstallationId as String?,
      lastKnownGoodModelInstallationId:
          identical(lastKnownGoodModelInstallationId, _unset)
              ? this.lastKnownGoodModelInstallationId
              : lastKnownGoodModelInstallationId as String?,
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
