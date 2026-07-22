import 'package:meta/meta.dart';
import 'catalog_manifest.dart';

/// Origine del catalogo acquisito dal client.
enum CatalogSource {
  bundledBootstrap,
  remoteSigned,
  cachedSigned,
  localDevelopment,
}

/// Livello di fiducia crittografica e provenienza del catalogo.
enum CatalogTrustLevel {
  bootstrapDeclared,
  signatureVerified,
  locallyImported,
  developmentUnsigned,
}

/// Identità univoca del contenuto binario grezzo dell'artefatto (Content Identity).
@immutable
final class ContentIdentity {
  final int sizeBytes;
  final String sha256;

  ContentIdentity({
    required this.sizeBytes,
    required String sha256,
  }) : sha256 = sha256.toLowerCase().trim() {
    if (sizeBytes <= 0) {
      throw ArgumentError('sizeBytes deve essere strettamente positivo (> 0).');
    }
    final shaRegExp = RegExp(r'^[a-f0-9]{64}$');
    if (!shaRegExp.hasMatch(this.sha256)) {
      throw ArgumentError(
          'sha256 deve essere una stringa esadecimale di 64 caratteri.');
    }
  }

  Map<String, dynamic> toJson() => {
        'sizeBytes': sizeBytes,
        'sha256': sha256,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ContentIdentity &&
          runtimeType == other.runtimeType &&
          sizeBytes == other.sizeBytes &&
          sha256 == other.sha256;

  @override
  int get hashCode => Object.hash(sizeBytes, sha256);

  @override
  String toString() =>
      'ContentIdentity(sizeBytes: $sizeBytes, sha256: $sha256)';
}

/// Identità univoca della specifica variante dell'artefatto nel provisioning (Artifact Identity).
@immutable
final class ArtifactIdentity {
  final String artifactId;
  final String version;
  final String buildId;
  final ContentIdentity contentIdentity;

  ArtifactIdentity({
    required String artifactId,
    required String version,
    required String buildId,
    required this.contentIdentity,
  })  : artifactId = artifactId.trim(),
        version = version.trim(),
        buildId = buildId.trim() {
    if (this.artifactId.isEmpty) {
      throw ArgumentError('artifactId non può essere vuoto.');
    }
    if (this.version.isEmpty) {
      throw ArgumentError('version non può essere vuota.');
    }
    if (this.buildId.isEmpty) {
      throw ArgumentError('buildId non può essere vuoto.');
    }
  }

  Map<String, dynamic> toJson() => {
        'artifactId': artifactId,
        'version': version,
        'buildId': buildId,
        'contentIdentity': contentIdentity.toJson(),
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ArtifactIdentity &&
          runtimeType == other.runtimeType &&
          artifactId == other.artifactId &&
          version == other.version &&
          buildId == other.buildId &&
          contentIdentity == other.contentIdentity;

  @override
  int get hashCode =>
      Object.hash(artifactId, version, buildId, contentIdentity);

  @override
  String toString() =>
      'ArtifactIdentity($artifactId@$version+$buildId, content: $contentIdentity)';
}

/// Identità della dichiarazione di un artefatto all'interno di una specifica revisione di catalogo.
@immutable
final class CatalogDeclarationIdentity {
  final String catalogId;
  final int catalogRevision;
  final ArtifactIdentity artifactIdentity;

  CatalogDeclarationIdentity({
    required String catalogId,
    required this.catalogRevision,
    required this.artifactIdentity,
  }) : catalogId = catalogId.trim() {
    if (this.catalogId.isEmpty) {
      throw ArgumentError('catalogId non può essere vuoto.');
    }
    if (catalogRevision < 0) {
      throw ArgumentError('catalogRevision non può essere negativa.');
    }
  }

  Map<String, dynamic> toJson() => {
        'catalogId': catalogId,
        'catalogRevision': catalogRevision,
        'artifactIdentity': artifactIdentity.toJson(),
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CatalogDeclarationIdentity &&
          runtimeType == other.runtimeType &&
          catalogId == other.catalogId &&
          catalogRevision == other.catalogRevision &&
          artifactIdentity == other.artifactIdentity;

  @override
  int get hashCode => Object.hash(catalogId, catalogRevision, artifactIdentity);

  @override
  String toString() =>
      'CatalogDeclarationIdentity($catalogId#$catalogRevision, artifact: $artifactIdentity)';
}

/// DTO del payload firmato del catalogo, contenente il protected header ed il manifest.
@immutable
final class CatalogSignedPayload {
  final String schemaVersion;
  final String signatureAlgorithm;
  final String keyId;
  final String catalogId;
  final String catalogVersion;
  final int catalogRevision;
  final String issuedAt;
  final String expiresAt;
  final CatalogManifest manifest;

  CatalogSignedPayload({
    required String schemaVersion,
    required String signatureAlgorithm,
    required String keyId,
    required String catalogId,
    required String catalogVersion,
    required this.catalogRevision,
    required String issuedAt,
    required String expiresAt,
    required this.manifest,
  })  : schemaVersion = schemaVersion.trim(),
        signatureAlgorithm = signatureAlgorithm.trim(),
        keyId = keyId.trim(),
        catalogId = catalogId.trim(),
        catalogVersion = catalogVersion.trim(),
        issuedAt = issuedAt.trim(),
        expiresAt = expiresAt.trim() {
    if (this.schemaVersion.isEmpty) throw ArgumentError('schemaVersion vuota.');
    if (this.signatureAlgorithm.isEmpty)
      throw ArgumentError('signatureAlgorithm vuoto.');
    if (this.keyId.isEmpty) throw ArgumentError('keyId vuoto.');
    if (this.catalogId.isEmpty) throw ArgumentError('catalogId vuoto.');
    if (this.catalogVersion.isEmpty)
      throw ArgumentError('catalogVersion vuota.');
    if (catalogRevision < 0) throw ArgumentError('catalogRevision negativa.');
    if (this.issuedAt.isEmpty) throw ArgumentError('issuedAt vuoto.');
    if (this.expiresAt.isEmpty) throw ArgumentError('expiresAt vuoto.');
  }

  factory CatalogSignedPayload.fromJson(Map<String, dynamic> json) {
    return CatalogSignedPayload(
      schemaVersion: json['schemaVersion'] as String? ?? '1.0',
      signatureAlgorithm: json['signatureAlgorithm'] as String? ?? 'ed25519-v1',
      keyId: json['keyId'] as String? ?? '',
      catalogId: json['catalogId'] as String? ?? '',
      catalogVersion: json['catalogVersion'] as String? ?? '',
      catalogRevision: (json['catalogRevision'] as num?)?.toInt() ?? 0,
      issuedAt: json['issuedAt'] as String? ?? '',
      expiresAt: json['expiresAt'] as String? ?? '',
      manifest: CatalogManifest.fromJson(
          json['manifest'] as Map<String, dynamic>? ?? {}),
    );
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'signatureAlgorithm': signatureAlgorithm,
        'keyId': keyId,
        'catalogId': catalogId,
        'catalogVersion': catalogVersion,
        'catalogRevision': catalogRevision,
        'issuedAt': issuedAt,
        'expiresAt': expiresAt,
        'manifest': manifest.toJson(),
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CatalogSignedPayload &&
          runtimeType == other.runtimeType &&
          schemaVersion == other.schemaVersion &&
          signatureAlgorithm == other.signatureAlgorithm &&
          keyId == other.keyId &&
          catalogId == other.catalogId &&
          catalogVersion == other.catalogVersion &&
          catalogRevision == other.catalogRevision &&
          issuedAt == other.issuedAt &&
          expiresAt == other.expiresAt &&
          manifest.catalogId == other.manifest.catalogId;

  @override
  int get hashCode => Object.hash(
        schemaVersion,
        signatureAlgorithm,
        keyId,
        catalogId,
        catalogVersion,
        catalogRevision,
        issuedAt,
        expiresAt,
        manifest,
      );
}

/// Wrapper esterno che contiene il payload firmato e la firma digitale in Base64.
@immutable
final class CatalogEnvelope {
  final CatalogSignedPayload signedPayload;
  final String signature;

  CatalogEnvelope({
    required this.signedPayload,
    required String signature,
  }) : signature = signature.trim() {
    if (this.signature.isEmpty) {
      throw ArgumentError('signature non può essere vuota.');
    }
  }

  factory CatalogEnvelope.fromJson(Map<String, dynamic> json) {
    final payloadJson = json['signedPayload'] as Map<String, dynamic>?;
    if (payloadJson == null) {
      throw ArgumentError('Campo signedPayload mancante o non valido.');
    }
    final sig = json['signature'] as String? ?? '';
    return CatalogEnvelope(
      signedPayload: CatalogSignedPayload.fromJson(payloadJson),
      signature: sig,
    );
  }

  Map<String, dynamic> toJson() => {
        'signedPayload': signedPayload.toJson(),
        'signature': signature,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CatalogEnvelope &&
          runtimeType == other.runtimeType &&
          signedPayload == other.signedPayload &&
          signature == other.signature;

  @override
  int get hashCode => Object.hash(signedPayload, signature);
}

/// DTO contenente il risultato dell'acquisizione e selezione del catalogo.
@immutable
final class CatalogAcquisitionResult {
  final CatalogManifest effectiveCatalog;
  final CatalogTrustLevel trustLevel;
  final CatalogSource catalogSource;
  final DateTime acquiredAt;
  final Map<String, dynamic> diagnostics;

  const CatalogAcquisitionResult({
    required this.effectiveCatalog,
    required this.trustLevel,
    required this.catalogSource,
    required this.acquiredAt,
    this.diagnostics = const {},
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CatalogAcquisitionResult &&
          runtimeType == other.runtimeType &&
          effectiveCatalog == other.effectiveCatalog &&
          trustLevel == other.trustLevel &&
          catalogSource == other.catalogSource &&
          acquiredAt == other.acquiredAt;

  @override
  int get hashCode =>
      Object.hash(effectiveCatalog, trustLevel, catalogSource, acquiredAt);
}
