import 'package:meta/meta.dart';
import 'catalog_acquisition_models.dart';
import 'catalog_manifest.dart';
import 'provisioning_options.dart';
import 'validated_catalog_candidate.dart';

/// DTO immutabile contenente la provenienza statica completa di un artefatto di catalogo autenticato.
@immutable
final class CatalogArtifactSnapshot {
  final String catalogId;
  final int catalogRevision;
  final String catalogSchemaVersion;
  final String signingKeyId;
  final CatalogTrustLevel trustLevel;
  final String artifactId;
  final String artifactVersion;
  final String buildId;
  final String? sourceRepository;
  final String? sourceRevision;
  final Uri? sourceUri;
  final String fileName;
  final int sizeBytes;
  final String sha256;
  final DateTime acquiredAtUtc;

  const CatalogArtifactSnapshot({
    required this.catalogId,
    required this.catalogRevision,
    required this.catalogSchemaVersion,
    required this.signingKeyId,
    required this.trustLevel,
    required this.artifactId,
    required this.artifactVersion,
    required this.buildId,
    this.sourceRepository,
    this.sourceRevision,
    this.sourceUri,
    required this.fileName,
    required this.sizeBytes,
    required this.sha256,
    required this.acquiredAtUtc,
  });

  /// Costruisce uno snapshot di provenienza a partire da un [ValidatedCatalogCandidate] autenticato e da un [CatalogArtifact].
  factory CatalogArtifactSnapshot.fromCandidate({
    required ValidatedCatalogCandidate candidate,
    required CatalogArtifact artifact,
    required DateTime acquiredAtUtc,
  }) {
    final payload = candidate.envelope.signedPayload;
    final repo = artifact.metadata['repository']?.toString();
    final revision = artifact.metadata['revision']?.toString();

    Uri? parsedUri;
    if (artifact.downloadUri != null &&
        artifact.downloadUri!.trim().isNotEmpty) {
      parsedUri = Uri.tryParse(artifact.downloadUri!.trim());
    }

    return CatalogArtifactSnapshot(
      catalogId: payload.catalogId,
      catalogRevision: payload.catalogRevision,
      catalogSchemaVersion: payload.schemaVersion,
      signingKeyId: payload.keyId,
      trustLevel: candidate.trustLevel,
      artifactId: artifact.artifactId,
      artifactVersion: artifact.version,
      buildId: artifact.buildId,
      sourceRepository: repo,
      sourceRevision: revision,
      sourceUri: parsedUri,
      fileName: artifact.fileName,
      sizeBytes: artifact.sizeBytes,
      sha256: artifact.sha256.toLowerCase(),
      acquiredAtUtc: acquiredAtUtc.toUtc(),
    );
  }

  /// Converte lo snapshot in una mappa serializzabile JSON.
  Map<String, dynamic> toJson() {
    return {
      'catalogId': catalogId,
      'catalogRevision': catalogRevision,
      'catalogSchemaVersion': catalogSchemaVersion,
      'signingKeyId': signingKeyId,
      'trustLevel': trustLevel.name,
      'artifactId': artifactId,
      'artifactVersion': artifactVersion,
      'buildId': buildId,
      if (sourceRepository != null) 'sourceRepository': sourceRepository,
      if (sourceRevision != null) 'sourceRevision': sourceRevision,
      if (sourceUri != null) 'sourceUri': sourceUri.toString(),
      'fileName': fileName,
      'sizeBytes': sizeBytes,
      'sha256': sha256,
      'acquiredAtUtc': acquiredAtUtc.toIso8601String(),
    };
  }

  /// Deserializza una mappa JSON nello snapshot di provenienza.
  /// Lancia [ProvisioningException] se un qualsiasi campo obbligatorio è mancante,
  /// vuoto o non conforme al formato atteso.
  factory CatalogArtifactSnapshot.fromJson(Map<String, dynamic> json) {
    // --- trustLevel ---
    final trustName = json['trustLevel'] as String?;
    if (trustName == null || trustName.isEmpty) {
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.installationRecordReadFailed,
        message:
            'CatalogArtifactSnapshot.fromJson: campo "trustLevel" mancante.',
      );
    }
    CatalogTrustLevel? trust;
    for (final v in CatalogTrustLevel.values) {
      if (v.name == trustName) {
        trust = v;
        break;
      }
    }
    if (trust == null) {
      throw ProvisioningException(
        reason: ProvisioningFailureReason.installationRecordReadFailed,
        message:
            'CatalogArtifactSnapshot.fromJson: trustLevel sconosciuto "$trustName".',
      );
    }

    // --- signingKeyId ---
    final signingKeyId = json['signingKeyId'] as String?;
    if (signingKeyId == null || signingKeyId.trim().isEmpty) {
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.installationRecordReadFailed,
        message:
            'CatalogArtifactSnapshot.fromJson: campo "signingKeyId" mancante o vuoto.',
      );
    }

    // --- catalogSchemaVersion ---
    final catalogSchemaVersion = json['catalogSchemaVersion'] as String?;
    if (catalogSchemaVersion == null || catalogSchemaVersion.trim().isEmpty) {
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.installationRecordReadFailed,
        message:
            'CatalogArtifactSnapshot.fromJson: campo "catalogSchemaVersion" mancante.',
      );
    }

    // --- sha256 ---
    final sha256Raw = json['sha256'] as String?;
    if (sha256Raw == null) {
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.installationRecordReadFailed,
        message: 'CatalogArtifactSnapshot.fromJson: campo "sha256" mancante.',
      );
    }
    final sha256 = sha256Raw.toLowerCase();
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(sha256)) {
      throw ProvisioningException(
        reason: ProvisioningFailureReason.installationRecordReadFailed,
        message:
            'CatalogArtifactSnapshot.fromJson: sha256 non conforme (atteso hex di 64 caratteri).',
      );
    }

    // --- sizeBytes ---
    final sizeBytesRaw = json['sizeBytes'];
    if (sizeBytesRaw == null) {
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.installationRecordReadFailed,
        message:
            'CatalogArtifactSnapshot.fromJson: campo "sizeBytes" mancante.',
      );
    }
    final sizeBytes = (sizeBytesRaw as num).toInt();
    if (sizeBytes <= 0) {
      throw ProvisioningException(
        reason: ProvisioningFailureReason.installationRecordReadFailed,
        message:
            'CatalogArtifactSnapshot.fromJson: sizeBytes deve essere > 0, ricevuto $sizeBytes.',
      );
    }

    // --- campi stringa obbligatori non vuoti ---
    String _requireString(String key) {
      final v = json[key] as String?;
      if (v == null || v.trim().isEmpty) {
        throw ProvisioningException(
          reason: ProvisioningFailureReason.installationRecordReadFailed,
          message:
              'CatalogArtifactSnapshot.fromJson: campo "$key" mancante o vuoto.',
        );
      }
      return v;
    }

    final catalogId = _requireString('catalogId');
    final artifactId = _requireString('artifactId');
    final artifactVersion = _requireString('artifactVersion');
    final buildId = _requireString('buildId');
    final fileName = _requireString('fileName');

    // --- catalogRevision ---
    final catalogRevisionRaw = json['catalogRevision'];
    if (catalogRevisionRaw == null) {
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.installationRecordReadFailed,
        message:
            'CatalogArtifactSnapshot.fromJson: campo "catalogRevision" mancante.',
      );
    }
    final catalogRevision = (catalogRevisionRaw as num).toInt();
    if (catalogRevision < 0) {
      throw ProvisioningException(
        reason: ProvisioningFailureReason.installationRecordReadFailed,
        message:
            'CatalogArtifactSnapshot.fromJson: catalogRevision non valido: $catalogRevision.',
      );
    }

    // --- acquiredAtUtc ---
    final acquiredAtUtcRaw = json['acquiredAtUtc'] as String?;
    if (acquiredAtUtcRaw == null || acquiredAtUtcRaw.trim().isEmpty) {
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.installationRecordReadFailed,
        message:
            'CatalogArtifactSnapshot.fromJson: campo "acquiredAtUtc" mancante.',
      );
    }
    DateTime acquiredAtUtc;
    try {
      acquiredAtUtc = DateTime.parse(acquiredAtUtcRaw).toUtc();
    } catch (_) {
      throw ProvisioningException(
        reason: ProvisioningFailureReason.installationRecordReadFailed,
        message:
            'CatalogArtifactSnapshot.fromJson: "acquiredAtUtc" non parsabile come ISO-8601.',
      );
    }

    // --- sourceUri opzionale ---
    Uri? parsedUri;
    final uriStr = json['sourceUri'] as String?;
    if (uriStr != null && uriStr.trim().isNotEmpty) {
      parsedUri = Uri.tryParse(uriStr.trim());
      if (parsedUri != null) {
        final scheme = parsedUri.scheme.toLowerCase();
        if (scheme != 'https' && scheme != 'http') {
          throw ProvisioningException(
            reason: ProvisioningFailureReason.installationRecordReadFailed,
            message:
                'CatalogArtifactSnapshot.fromJson: schema URI non ammesso "$scheme" (solo https/http).',
          );
        }
      }
    }

    return CatalogArtifactSnapshot(
      catalogId: catalogId,
      catalogRevision: catalogRevision,
      catalogSchemaVersion: catalogSchemaVersion,
      signingKeyId: signingKeyId,
      trustLevel: trust,
      artifactId: artifactId,
      artifactVersion: artifactVersion,
      buildId: buildId,
      sourceRepository: json['sourceRepository'] as String?,
      sourceRevision: json['sourceRevision'] as String?,
      sourceUri: parsedUri,
      fileName: fileName,
      sizeBytes: sizeBytes,
      sha256: sha256,
      acquiredAtUtc: acquiredAtUtc,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CatalogArtifactSnapshot &&
          runtimeType == other.runtimeType &&
          catalogId == other.catalogId &&
          catalogRevision == other.catalogRevision &&
          catalogSchemaVersion == other.catalogSchemaVersion &&
          signingKeyId == other.signingKeyId &&
          trustLevel == other.trustLevel &&
          artifactId == other.artifactId &&
          artifactVersion == other.artifactVersion &&
          buildId == other.buildId &&
          sourceRepository == other.sourceRepository &&
          sourceRevision == other.sourceRevision &&
          sourceUri == other.sourceUri &&
          fileName == other.fileName &&
          sizeBytes == other.sizeBytes &&
          sha256 == other.sha256 &&
          acquiredAtUtc == other.acquiredAtUtc;

  @override
  int get hashCode => Object.hash(
        catalogId,
        catalogRevision,
        catalogSchemaVersion,
        signingKeyId,
        trustLevel,
        artifactId,
        artifactVersion,
        buildId,
        sourceRepository,
        sourceRevision,
        sourceUri,
        fileName,
        sizeBytes,
        sha256,
        acquiredAtUtc,
      );
}
