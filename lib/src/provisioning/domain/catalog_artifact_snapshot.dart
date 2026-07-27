import 'package:meta/meta.dart';
import 'catalog_acquisition_models.dart';
import 'catalog_manifest.dart';
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
  factory CatalogArtifactSnapshot.fromJson(Map<String, dynamic> json) {
    final trustName = json['trustLevel'] as String? ??
        CatalogTrustLevel.developmentUnsigned.name;
    final trust = CatalogTrustLevel.values.firstWhere(
      (e) => e.name == trustName,
      orElse: () => CatalogTrustLevel.developmentUnsigned,
    );

    Uri? parsedUri;
    final uriStr = json['sourceUri'] as String?;
    if (uriStr != null && uriStr.trim().isNotEmpty) {
      parsedUri = Uri.tryParse(uriStr.trim());
    }

    return CatalogArtifactSnapshot(
      catalogId: json['catalogId'] as String,
      catalogRevision: (json['catalogRevision'] as num).toInt(),
      catalogSchemaVersion: json['catalogSchemaVersion'] as String? ?? '1.0',
      signingKeyId: json['signingKeyId'] as String? ?? 'unknown-key',
      trustLevel: trust,
      artifactId: json['artifactId'] as String,
      artifactVersion: json['artifactVersion'] as String,
      buildId: json['buildId'] as String,
      sourceRepository: json['sourceRepository'] as String?,
      sourceRevision: json['sourceRevision'] as String?,
      sourceUri: parsedUri,
      fileName: json['fileName'] as String,
      sizeBytes: (json['sizeBytes'] as num).toInt(),
      sha256: (json['sha256'] as String).toLowerCase(),
      acquiredAtUtc: DateTime.parse(json['acquiredAtUtc'] as String).toUtc(),
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
