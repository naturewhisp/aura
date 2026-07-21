import 'package:meta/meta.dart';
import 'json_safe_value.dart';
import 'provisioning_options.dart';

const Object _unset = Object();

/// Rappresenta lo stato di attivazione corrente del runtime e del modello (active_state.json).
@immutable
final class ActivationState {
  final String schemaVersion;
  final String updatedAt;
  final String? activeRuntimeId;
  final String? activeRuntimeVersion;
  final String? activeModelId;
  final String? activeModelVersion;
  final Map<String, dynamic> metadata;

  ActivationState({
    this.schemaVersion = '1.0',
    required this.updatedAt,
    this.activeRuntimeId,
    this.activeRuntimeVersion,
    this.activeModelId,
    this.activeModelVersion,
    Map<String, dynamic> metadata = const {},
  }) : metadata = JsonSafeValue.ensureJsonSafeMap(metadata);

  factory ActivationState.empty({String? updatedAt}) {
    return ActivationState(
      schemaVersion: '1.0',
      updatedAt: updatedAt ?? DateTime.now().toUtc().toIso8601String(),
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
        activeRuntimeId: json['activeRuntimeId'] as String?,
        activeRuntimeVersion: json['activeRuntimeVersion'] as String?,
        activeModelId: json['activeModelId'] as String?,
        activeModelVersion: json['activeModelVersion'] as String?,
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
      if (activeRuntimeId != null) 'activeRuntimeId': activeRuntimeId,
      if (activeRuntimeVersion != null)
        'activeRuntimeVersion': activeRuntimeVersion,
      if (activeModelId != null) 'activeModelId': activeModelId,
      if (activeModelVersion != null) 'activeModelVersion': activeModelVersion,
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }

  ActivationState copyWith({
    String? schemaVersion,
    String? updatedAt,
    Object? activeRuntimeId = _unset,
    Object? activeRuntimeVersion = _unset,
    Object? activeModelId = _unset,
    Object? activeModelVersion = _unset,
    Map<String, dynamic>? metadata,
  }) {
    return ActivationState(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      updatedAt: updatedAt ?? this.updatedAt,
      activeRuntimeId: identical(activeRuntimeId, _unset)
          ? this.activeRuntimeId
          : activeRuntimeId as String?,
      activeRuntimeVersion: identical(activeRuntimeVersion, _unset)
          ? this.activeRuntimeVersion
          : activeRuntimeVersion as String?,
      activeModelId: identical(activeModelId, _unset)
          ? this.activeModelId
          : activeModelId as String?,
      activeModelVersion: identical(activeModelVersion, _unset)
          ? this.activeModelVersion
          : activeModelVersion as String?,
      metadata: metadata ?? this.metadata,
    );
  }
}
