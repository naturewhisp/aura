import 'package:meta/meta.dart';
import 'catalog_manifest.dart';
import 'json_safe_value.dart';
import 'provisioning_options.dart';

const Object _unset = Object();

/// Descrive una singola installazione fisica registrata nell'InstallationRecord.
@immutable
final class InstalledArtifactDescriptor {
  final String installationId;
  final String artifactId;
  final CatalogArtifactType artifactType;
  final String displayName;
  final String version;
  final String buildId;
  final String platform;
  final String architecture;
  final String relativeInstallPath;
  final String installedAt;
  final int sizeBytes;
  final String sha256;
  final CatalogArtifactSourceKind sourceKind;
  final String status;
  final String? verifiedAt;
  final String ownership;
  final String? lastValidationAt;
  final String? failureDiscriminator;
  final bool retained;
  final Map<String, dynamic> metadata;

  InstalledArtifactDescriptor({
    required this.installationId,
    required this.artifactId,
    required this.artifactType,
    required this.displayName,
    required this.version,
    required this.buildId,
    required this.platform,
    required this.architecture,
    required this.relativeInstallPath,
    required this.installedAt,
    required this.sizeBytes,
    required this.sha256,
    required this.sourceKind,
    this.status = 'installed',
    this.verifiedAt,
    this.ownership = 'appManaged',
    this.lastValidationAt,
    this.failureDiscriminator,
    this.retained = true,
    Map<String, dynamic> metadata = const {},
  }) : metadata = JsonSafeValue.ensureJsonSafeMap(metadata);

  factory InstalledArtifactDescriptor.fromJson(Map<String, dynamic> json) {
    try {
      final rawType = json['artifactType'] as String?;
      if (rawType == null || rawType.isEmpty) {
        throw const ProvisioningException(
          reason: ProvisioningFailureReason.installationRecordReadFailed,
          message:
              'Campo obbligatorio mancante in InstalledArtifactDescriptor: artifactType.',
        );
      }

      final rawSourceKind =
          (json['sourceKind'] as String?) ?? (json['source'] as String?);
      if (rawSourceKind == null || rawSourceKind.isEmpty) {
        throw const ProvisioningException(
          reason: ProvisioningFailureReason.installationRecordReadFailed,
          message:
              'Campo obbligatorio mancante in InstalledArtifactDescriptor: sourceKind.',
        );
      }

      final rawSizeBytes = json['sizeBytes'];
      if (rawSizeBytes is! int) {
        throw const ProvisioningException(
          reason: ProvisioningFailureReason.installationRecordReadFailed,
          message:
              'Il campo sizeBytes deve essere un numero intero JSON strict.',
        );
      }

      final relativePath = json['relativeInstallPath'] as String? ??
          (json['installPath'] as String?);
      if (relativePath == null || relativePath.trim().isEmpty) {
        throw const ProvisioningException(
          reason: ProvisioningFailureReason.installationRecordReadFailed,
          message:
              'Campo obbligatorio mancante in InstalledArtifactDescriptor: relativeInstallPath.',
        );
      }

      final instId = json['installationId'] as String?;
      if (instId == null || instId.trim().isEmpty) {
        throw const ProvisioningException(
          reason: ProvisioningFailureReason.installationRecordReadFailed,
          message: 'Campo obbligatorio mancante: installationId.',
        );
      }

      return InstalledArtifactDescriptor(
        installationId: instId,
        artifactId: json['artifactId'] as String? ??
            (throw const ProvisioningException(
              reason: ProvisioningFailureReason.installationRecordReadFailed,
              message: 'Campo obbligatorio mancante: artifactId.',
            )),
        artifactType: CatalogArtifactType.parse(rawType),
        displayName: json['displayName'] as String? ??
            (throw const ProvisioningException(
              reason: ProvisioningFailureReason.installationRecordReadFailed,
              message: 'Campo obbligatorio mancante: displayName.',
            )),
        version: json['version'] as String? ??
            (throw const ProvisioningException(
              reason: ProvisioningFailureReason.installationRecordReadFailed,
              message: 'Campo obbligatorio mancante: version.',
            )),
        buildId: json['buildId'] as String? ??
            (throw const ProvisioningException(
              reason: ProvisioningFailureReason.installationRecordReadFailed,
              message: 'Campo obbligatorio mancante: buildId.',
            )),
        platform: json['platform'] as String? ??
            (throw const ProvisioningException(
              reason: ProvisioningFailureReason.installationRecordReadFailed,
              message: 'Campo obbligatorio mancante: platform.',
            )),
        architecture: json['architecture'] as String? ??
            (throw const ProvisioningException(
              reason: ProvisioningFailureReason.installationRecordReadFailed,
              message: 'Campo obbligatorio mancante: architecture.',
            )),
        relativeInstallPath: relativePath,
        installedAt: json['installedAt'] as String? ??
            (throw const ProvisioningException(
              reason: ProvisioningFailureReason.installationRecordReadFailed,
              message: 'Campo obbligatorio mancante: installedAt.',
            )),
        sizeBytes: rawSizeBytes,
        sha256: json['sha256'] as String? ??
            (throw const ProvisioningException(
              reason: ProvisioningFailureReason.installationRecordReadFailed,
              message: 'Campo obbligatorio mancante: sha256.',
            )),
        sourceKind: CatalogArtifactSourceKind.parse(rawSourceKind),
        status: (json['status'] as String?) ?? 'installed',
        verifiedAt: json['verifiedAt'] as String?,
        ownership: (json['ownership'] as String?) ?? 'appManaged',
        lastValidationAt: json['lastValidationAt'] as String?,
        failureDiscriminator: json['failureDiscriminator'] as String?,
        retained: json['retained'] as bool? ?? true,
        metadata: json['metadata'] != null
            ? Map<String, dynamic>.from(json['metadata'] as Map)
            : const {},
      );
    } on ProvisioningException {
      rethrow;
    } catch (_) {
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.installationRecordReadFailed,
        message: 'Errore di parsing dei campi di InstalledArtifactDescriptor.',
      );
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'installationId': installationId,
      'artifactId': artifactId,
      'artifactType': artifactType.name,
      'displayName': displayName,
      'version': version,
      'buildId': buildId,
      'platform': platform,
      'architecture': architecture,
      'relativeInstallPath': relativeInstallPath,
      'installedAt': installedAt,
      'sizeBytes': sizeBytes,
      'sha256': sha256,
      'sourceKind': sourceKind.name,
      'status': status,
      if (verifiedAt != null) 'verifiedAt': verifiedAt,
      'ownership': ownership,
      if (lastValidationAt != null) 'lastValidationAt': lastValidationAt,
      if (failureDiscriminator != null)
        'failureDiscriminator': failureDiscriminator,
      'retained': retained,
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }

  InstalledArtifactDescriptor copyWith({
    String? installationId,
    String? artifactId,
    CatalogArtifactType? artifactType,
    String? displayName,
    String? version,
    String? buildId,
    String? platform,
    String? architecture,
    String? relativeInstallPath,
    String? installedAt,
    int? sizeBytes,
    String? sha256,
    CatalogArtifactSourceKind? sourceKind,
    String? status,
    Object? verifiedAt = _unset,
    String? ownership,
    Object? lastValidationAt = _unset,
    Object? failureDiscriminator = _unset,
    bool? retained,
    Map<String, dynamic>? metadata,
  }) {
    return InstalledArtifactDescriptor(
      installationId: installationId ?? this.installationId,
      artifactId: artifactId ?? this.artifactId,
      artifactType: artifactType ?? this.artifactType,
      displayName: displayName ?? this.displayName,
      version: version ?? this.version,
      buildId: buildId ?? this.buildId,
      platform: platform ?? this.platform,
      architecture: architecture ?? this.architecture,
      relativeInstallPath: relativeInstallPath ?? this.relativeInstallPath,
      installedAt: installedAt ?? this.installedAt,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      sha256: sha256 ?? this.sha256,
      sourceKind: sourceKind ?? this.sourceKind,
      status: status ?? this.status,
      verifiedAt: identical(verifiedAt, _unset)
          ? this.verifiedAt
          : verifiedAt as String?,
      ownership: ownership ?? this.ownership,
      lastValidationAt: identical(lastValidationAt, _unset)
          ? this.lastValidationAt
          : lastValidationAt as String?,
      failureDiscriminator: identical(failureDiscriminator, _unset)
          ? this.failureDiscriminator
          : failureDiscriminator as String?,
      retained: retained ?? this.retained,
      metadata: metadata ?? this.metadata,
    );
  }
}

/// Registro persistente degli artefatti installati (installation_record.json).
@immutable
final class InstallationRecord {
  final String schemaVersion;
  final String updatedAt;
  final List<InstalledArtifactDescriptor> installedArtifacts;
  final Map<String, dynamic> metadata;

  InstallationRecord({
    this.schemaVersion = '1.0',
    required this.updatedAt,
    required List<InstalledArtifactDescriptor> installedArtifacts,
    Map<String, dynamic> metadata = const {},
  })  : installedArtifacts = List.unmodifiable(
            List<InstalledArtifactDescriptor>.from(installedArtifacts)),
        metadata = JsonSafeValue.ensureJsonSafeMap(metadata);

  factory InstallationRecord.empty({required String updatedAt}) {
    return InstallationRecord(
      schemaVersion: '1.0',
      updatedAt: updatedAt,
      installedArtifacts: const [],
    );
  }

  factory InstallationRecord.fromJson(Map<String, dynamic> json) {
    try {
      final rawSchema = json['schemaVersion'] as String?;
      if (rawSchema == null || rawSchema.trim().isEmpty) {
        throw const ProvisioningException(
          reason: ProvisioningFailureReason.installationRecordReadFailed,
          message: 'Campo obbligatorio mancante: schemaVersion.',
        );
      }

      final rawUpdatedAt = json['updatedAt'] as String?;
      if (rawUpdatedAt == null || rawUpdatedAt.trim().isEmpty) {
        throw const ProvisioningException(
          reason: ProvisioningFailureReason.installationRecordReadFailed,
          message: 'Campo obbligatorio mancante: updatedAt.',
        );
      }

      final rawArtifacts = json['installedArtifacts'] as List<dynamic>?;
      if (rawArtifacts == null) {
        throw const ProvisioningException(
          reason: ProvisioningFailureReason.installationRecordReadFailed,
          message: 'Campo obbligatorio mancante: installedArtifacts.',
        );
      }

      final parsedArtifacts = <InstalledArtifactDescriptor>[];
      for (final item in rawArtifacts) {
        if (item is! Map) {
          throw const ProvisioningException(
            reason: ProvisioningFailureReason.installationRecordReadFailed,
            message:
                'Elemento non mappa presente nella lista installedArtifacts.',
          );
        }
        parsedArtifacts.add(InstalledArtifactDescriptor.fromJson(
            Map<String, dynamic>.from(item)));
      }

      return InstallationRecord(
        schemaVersion: rawSchema,
        updatedAt: rawUpdatedAt,
        installedArtifacts: parsedArtifacts,
        metadata: json['metadata'] != null
            ? Map<String, dynamic>.from(json['metadata'] as Map)
            : const {},
      );
    } on ProvisioningException {
      rethrow;
    } catch (_) {
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.installationRecordReadFailed,
        message: 'Errore di parsing del file installation_record.json.',
      );
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'schemaVersion': schemaVersion,
      'updatedAt': updatedAt,
      'installedArtifacts': installedArtifacts.map((a) => a.toJson()).toList(),
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }

  InstallationRecord copyWith({
    String? schemaVersion,
    String? updatedAt,
    List<InstalledArtifactDescriptor>? installedArtifacts,
    Map<String, dynamic>? metadata,
  }) {
    return InstallationRecord(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      updatedAt: updatedAt ?? this.updatedAt,
      installedArtifacts: installedArtifacts ?? this.installedArtifacts,
      metadata: metadata ?? this.metadata,
    );
  }
}
