import 'package:meta/meta.dart';

/// Tipo di artefatto descritto nel catalogo.
enum CatalogArtifactType {
  runtime,
  model;

  static CatalogArtifactType parse(String value) {
    return CatalogArtifactType.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw ArgumentError('CatalogArtifactType non valido: $value'),
    );
  }
}

/// Formato di compressione dell'artefatto nel catalogo.
enum CatalogCompressionFormat {
  none,
  zip;

  static CatalogCompressionFormat parse(String value) {
    return CatalogCompressionFormat.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw ArgumentError('CatalogCompressionFormat non valido: $value'),
    );
  }
}

/// Rappresenta un singolo artefatto (runtime binario o modello GGUF) nel catalogo.
@immutable
final class CatalogArtifact {
  final String artifactId;
  final CatalogArtifactType artifactType;
  final String displayName;
  final String version;
  final String buildId;
  final String platform;
  final String architecture;
  final String fileName;
  final String? downloadUri;
  final int sizeBytes;
  final String sha256;
  final CatalogCompressionFormat compression;
  final String license;
  final String source;
  final String? runtimeCompatibility;
  final String? minimumRuntimeBuild;
  final String? maximumRuntimeBuild;
  final String? modelArchitecture;
  final String? quantization;
  final int? contextLength;
  final List<String> capabilities;
  final List<String> hardwareCompatibilityTags;
  final bool deprecated;
  final String releaseChannel;
  final Map<String, dynamic> metadata;

  const CatalogArtifact({
    required this.artifactId,
    required this.artifactType,
    required this.displayName,
    required this.version,
    required this.buildId,
    required this.platform,
    required this.architecture,
    required this.fileName,
    this.downloadUri,
    required this.sizeBytes,
    required this.sha256,
    this.compression = CatalogCompressionFormat.none,
    required this.license,
    required this.source,
    this.runtimeCompatibility,
    this.minimumRuntimeBuild,
    this.maximumRuntimeBuild,
    this.modelArchitecture,
    this.quantization,
    this.contextLength,
    this.capabilities = const [],
    this.hardwareCompatibilityTags = const [],
    this.deprecated = false,
    this.releaseChannel = 'stable',
    this.metadata = const {},
  });

  factory CatalogArtifact.fromJson(Map<String, dynamic> json) {
    final rawType = json['artifactType'] as String?;
    if (rawType == null || rawType.isEmpty) {
      throw const FormatException('Campo obbligatorio mancante: artifactType');
    }
    final rawCompression = (json['compression'] as String?) ?? 'none';

    return CatalogArtifact(
      artifactId: json['artifactId'] as String? ??
          (throw const FormatException(
              'Campo obbligatorio mancante: artifactId')),
      artifactType: CatalogArtifactType.parse(rawType),
      displayName: json['displayName'] as String? ?? '',
      version: json['version'] as String? ??
          (throw const FormatException('Campo obbligatorio mancante: version')),
      buildId: json['buildId'] as String? ??
          (throw const FormatException('Campo obbligatorio mancante: buildId')),
      platform: json['platform'] as String? ??
          (throw const FormatException(
              'Campo obbligatorio mancante: platform')),
      architecture: json['architecture'] as String? ??
          (throw const FormatException(
              'Campo obbligatorio mancante: architecture')),
      fileName: json['fileName'] as String? ??
          (throw const FormatException(
              'Campo obbligatorio mancante: fileName')),
      downloadUri: json['downloadUri'] as String?,
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ??
          (throw const FormatException(
              'Campo obbligatorio mancante: sizeBytes')),
      sha256: json['sha256'] as String? ??
          (throw const FormatException('Campo obbligatorio mancante: sha256')),
      compression: CatalogCompressionFormat.parse(rawCompression),
      license: json['license'] as String? ?? 'unknown',
      source: json['source'] as String? ?? 'bundled',
      runtimeCompatibility: json['runtimeCompatibility'] as String?,
      minimumRuntimeBuild: json['minimumRuntimeBuild'] as String?,
      maximumRuntimeBuild: json['maximumRuntimeBuild'] as String?,
      modelArchitecture: json['modelArchitecture'] as String?,
      quantization: json['quantization'] as String?,
      contextLength: (json['contextLength'] as num?)?.toInt(),
      capabilities: (json['capabilities'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      hardwareCompatibilityTags:
          (json['hardwareCompatibilityTags'] as List<dynamic>?)
                  ?.map((e) => e.toString())
                  .toList() ??
              const [],
      deprecated: json['deprecated'] as bool? ?? false,
      releaseChannel: json['releaseChannel'] as String? ?? 'stable',
      metadata: json['metadata'] != null
          ? Map<String, dynamic>.from(json['metadata'] as Map)
          : const {},
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'artifactId': artifactId,
      'artifactType': artifactType.name,
      'displayName': displayName,
      'version': version,
      'buildId': buildId,
      'platform': platform,
      'architecture': architecture,
      'fileName': fileName,
      if (downloadUri != null) 'downloadUri': downloadUri,
      'sizeBytes': sizeBytes,
      'sha256': sha256,
      'compression': compression.name,
      'license': license,
      'source': source,
      if (runtimeCompatibility != null)
        'runtimeCompatibility': runtimeCompatibility,
      if (minimumRuntimeBuild != null)
        'minimumRuntimeBuild': minimumRuntimeBuild,
      if (maximumRuntimeBuild != null)
        'maximumRuntimeBuild': maximumRuntimeBuild,
      if (modelArchitecture != null) 'modelArchitecture': modelArchitecture,
      if (quantization != null) 'quantization': quantization,
      if (contextLength != null) 'contextLength': contextLength,
      'capabilities': capabilities,
      'hardwareCompatibilityTags': hardwareCompatibilityTags,
      'deprecated': deprecated,
      'releaseChannel': releaseChannel,
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }

  CatalogArtifact copyWith({
    String? artifactId,
    CatalogArtifactType? artifactType,
    String? displayName,
    String? version,
    String? buildId,
    String? platform,
    String? architecture,
    String? fileName,
    String? downloadUri,
    int? sizeBytes,
    String? sha256,
    CatalogCompressionFormat? compression,
    String? license,
    String? source,
    String? runtimeCompatibility,
    String? minimumRuntimeBuild,
    String? maximumRuntimeBuild,
    String? modelArchitecture,
    String? quantization,
    int? contextLength,
    List<String>? capabilities,
    List<String>? hardwareCompatibilityTags,
    bool? deprecated,
    String? releaseChannel,
    Map<String, dynamic>? metadata,
  }) {
    return CatalogArtifact(
      artifactId: artifactId ?? this.artifactId,
      artifactType: artifactType ?? this.artifactType,
      displayName: displayName ?? this.displayName,
      version: version ?? this.version,
      buildId: buildId ?? this.buildId,
      platform: platform ?? this.platform,
      architecture: architecture ?? this.architecture,
      fileName: fileName ?? this.fileName,
      downloadUri: downloadUri ?? this.downloadUri,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      sha256: sha256 ?? this.sha256,
      compression: compression ?? this.compression,
      license: license ?? this.license,
      source: source ?? this.source,
      runtimeCompatibility: runtimeCompatibility ?? this.runtimeCompatibility,
      minimumRuntimeBuild: minimumRuntimeBuild ?? this.minimumRuntimeBuild,
      maximumRuntimeBuild: maximumRuntimeBuild ?? this.maximumRuntimeBuild,
      modelArchitecture: modelArchitecture ?? this.modelArchitecture,
      quantization: quantization ?? this.quantization,
      contextLength: contextLength ?? this.contextLength,
      capabilities: capabilities ?? this.capabilities,
      hardwareCompatibilityTags:
          hardwareCompatibilityTags ?? this.hardwareCompatibilityTags,
      deprecated: deprecated ?? this.deprecated,
      releaseChannel: releaseChannel ?? this.releaseChannel,
      metadata: metadata ?? this.metadata,
    );
  }
}

/// Documento di catalogo immutabile che dichiara tutti gli artefatti disponibili.
@immutable
final class CatalogManifest {
  final String schemaVersion;
  final String catalogId;
  final String generatedAt;
  final List<CatalogArtifact> artifacts;
  final Map<String, dynamic> metadata;

  const CatalogManifest({
    required this.schemaVersion,
    required this.catalogId,
    required this.generatedAt,
    required this.artifacts,
    this.metadata = const {},
  });

  factory CatalogManifest.fromJson(Map<String, dynamic> json) {
    final rawSchema = json['schemaVersion'] as String?;
    if (rawSchema == null || rawSchema.isEmpty) {
      throw const FormatException('Campo obbligatorio mancante: schemaVersion');
    }

    final rawCatalogId = json['catalogId'] as String?;
    if (rawCatalogId == null || rawCatalogId.isEmpty) {
      throw const FormatException('Campo obbligatorio mancante: catalogId');
    }

    final rawArtifacts = json['artifacts'] as List<dynamic>?;
    if (rawArtifacts == null) {
      throw const FormatException('Campo obbligatorio mancante: artifacts');
    }

    final parsedArtifacts = rawArtifacts
        .map((e) =>
            CatalogArtifact.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();

    return CatalogManifest(
      schemaVersion: rawSchema,
      catalogId: rawCatalogId,
      generatedAt: json['generatedAt'] as String? ?? '',
      artifacts: List.unmodifiable(parsedArtifacts),
      metadata: json['metadata'] != null
          ? Map<String, dynamic>.from(json['metadata'] as Map)
          : const {},
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'schemaVersion': schemaVersion,
      'catalogId': catalogId,
      'generatedAt': generatedAt,
      'artifacts': artifacts.map((a) => a.toJson()).toList(),
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }

  CatalogManifest copyWith({
    String? schemaVersion,
    String? catalogId,
    String? generatedAt,
    List<CatalogArtifact>? artifacts,
    Map<String, dynamic>? metadata,
  }) {
    return CatalogManifest(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      catalogId: catalogId ?? this.catalogId,
      generatedAt: generatedAt ?? this.generatedAt,
      artifacts: artifacts ?? this.artifacts,
      metadata: metadata ?? this.metadata,
    );
  }
}
