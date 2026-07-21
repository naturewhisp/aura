import 'package:meta/meta.dart';
import 'provisioning_options.dart';

/// Tipo di artefatto descritto nel catalogo.
enum CatalogArtifactType {
  runtime,
  model;

  static CatalogArtifactType parse(String value) {
    for (final type in CatalogArtifactType.values) {
      if (type.name == value.trim()) {
        return type;
      }
    }
    throw ProvisioningException(
      reason: ProvisioningFailureReason.catalogMalformed,
      message: 'CatalogArtifactType non valido: "$value".',
    );
  }
}

/// Formato di compressione dell'artefatto nel catalogo.
enum CatalogCompressionFormat {
  none,
  zip;

  static CatalogCompressionFormat parse(String value) {
    for (final format in CatalogCompressionFormat.values) {
      if (format.name == value.trim()) {
        return format;
      }
    }
    throw ProvisioningException(
      reason: ProvisioningFailureReason.catalogMalformed,
      message: 'CatalogCompressionFormat non valido: "$value".',
    );
  }
}

/// Origine discriminata dell'artefatto nel catalogo.
enum CatalogArtifactSourceKind {
  bundled,
  remoteHttps,
  localImport;

  static CatalogArtifactSourceKind parse(String value) {
    for (final kind in CatalogArtifactSourceKind.values) {
      if (kind.name == value.trim()) {
        return kind;
      }
    }
    throw ProvisioningException(
      reason: ProvisioningFailureReason.catalogMalformed,
      message: 'CatalogArtifactSourceKind non valido: "$value".',
    );
  }
}

/// Helper privato per la validazione ricorsiva e l'immutabilità dei grafi JSON.
Map<String, dynamic> _ensureJsonSafeMap(Map<String, dynamic> map) {
  final result = <String, dynamic>{};
  for (final entry in map.entries) {
    final key = entry.key;
    _validateJsonSafeValue(entry.value, path: key);
    result[key] = _freezeJsonSafeValue(entry.value);
  }
  return Map.unmodifiable(result);
}

void _validateJsonSafeValue(Object? value, {required String path}) {
  if (value == null || value is bool || value is String) {
    return;
  }
  if (value is num) {
    if (value.isNaN || value.isInfinite) {
      throw ProvisioningException(
        reason: ProvisioningFailureReason.catalogMalformed,
        message:
            'Valore numerico non finito (NaN/Infinity) non ammesso in metadata al path "$path".',
      );
    }
    return;
  }
  if (value is List) {
    for (var i = 0; i < value.length; i++) {
      _validateJsonSafeValue(value[i], path: '$path[$i]');
    }
    return;
  }
  if (value is Map) {
    for (final entry in value.entries) {
      if (entry.key is! String) {
        throw ProvisioningException(
          reason: ProvisioningFailureReason.catalogMalformed,
          message:
              'Chiave non stringa "${entry.key}" non ammessa in metadata al path "$path".',
        );
      }
      _validateJsonSafeValue(entry.value, path: '$path.${entry.key}');
    }
    return;
  }
  throw ProvisioningException(
    reason: ProvisioningFailureReason.catalogMalformed,
    message:
        'Tipo di dato non JSON-safe "${value.runtimeType}" rilevato al path "$path".',
  );
}

Object? _freezeJsonSafeValue(Object? value) {
  if (value is List) {
    return List.unmodifiable(value.map(_freezeJsonSafeValue));
  }
  if (value is Map) {
    final copy = <String, dynamic>{};
    for (final entry in value.entries) {
      copy[entry.key as String] = _freezeJsonSafeValue(entry.value);
    }
    return Map.unmodifiable(copy);
  }
  return value;
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
  final CatalogArtifactSourceKind sourceKind;
  final String? downloadUri;
  final String? bundledAssetId;
  final int sizeBytes;
  final String sha256;
  final CatalogCompressionFormat compression;
  final String license;
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

  CatalogArtifact({
    required this.artifactId,
    required this.artifactType,
    required this.displayName,
    required this.version,
    required this.buildId,
    required this.platform,
    required this.architecture,
    required this.fileName,
    required this.sourceKind,
    this.downloadUri,
    this.bundledAssetId,
    required this.sizeBytes,
    required this.sha256,
    this.compression = CatalogCompressionFormat.none,
    required this.license,
    this.runtimeCompatibility,
    this.minimumRuntimeBuild,
    this.maximumRuntimeBuild,
    this.modelArchitecture,
    this.quantization,
    this.contextLength,
    List<String> capabilities = const [],
    List<String> hardwareCompatibilityTags = const [],
    this.deprecated = false,
    this.releaseChannel = 'stable',
    Map<String, dynamic> metadata = const {},
  })  : capabilities = List.unmodifiable(List<String>.from(capabilities)),
        hardwareCompatibilityTags =
            List.unmodifiable(List<String>.from(hardwareCompatibilityTags)),
        metadata = _ensureJsonSafeMap(metadata);

  factory CatalogArtifact.fromJson(Map<String, dynamic> json) {
    try {
      final rawType = json['artifactType'] as String?;
      if (rawType == null || rawType.isEmpty) {
        throw const ProvisioningException(
          reason: ProvisioningFailureReason.catalogMalformed,
          message: 'Campo obbligatorio mancante: artifactType.',
        );
      }

      final rawSourceKind =
          (json['sourceKind'] as String?) ?? (json['source'] as String?);
      if (rawSourceKind == null || rawSourceKind.isEmpty) {
        throw const ProvisioningException(
          reason: ProvisioningFailureReason.catalogMalformed,
          message: 'Campo obbligatorio mancante: sourceKind.',
        );
      }

      final rawCompression = (json['compression'] as String?) ?? 'none';

      final capsRaw = json['capabilities'] as List<dynamic>?;
      final parsedCaps = <String>[];
      if (capsRaw != null) {
        for (final item in capsRaw) {
          if (item is! String) {
            throw const ProvisioningException(
              reason: ProvisioningFailureReason.catalogMalformed,
              message:
                  'Elemento non-stringa presente nella lista capabilities.',
            );
          }
          parsedCaps.add(item);
        }
      }

      final hwTagsRaw = json['hardwareCompatibilityTags'] as List<dynamic>?;
      final parsedHwTags = <String>[];
      if (hwTagsRaw != null) {
        for (final item in hwTagsRaw) {
          if (item is! String) {
            throw const ProvisioningException(
              reason: ProvisioningFailureReason.catalogMalformed,
              message:
                  'Elemento non-stringa presente nella lista hardwareCompatibilityTags.',
            );
          }
          parsedHwTags.add(item);
        }
      }

      return CatalogArtifact(
        artifactId: json['artifactId'] as String? ??
            (throw const ProvisioningException(
              reason: ProvisioningFailureReason.catalogMalformed,
              message: 'Campo obbligatorio mancante: artifactId.',
            )),
        artifactType: CatalogArtifactType.parse(rawType),
        displayName: json['displayName'] as String? ?? '',
        version: json['version'] as String? ??
            (throw const ProvisioningException(
              reason: ProvisioningFailureReason.catalogMalformed,
              message: 'Campo obbligatorio mancante: version.',
            )),
        buildId: json['buildId'] as String? ??
            (throw const ProvisioningException(
              reason: ProvisioningFailureReason.catalogMalformed,
              message: 'Campo obbligatorio mancante: buildId.',
            )),
        platform: json['platform'] as String? ??
            (throw const ProvisioningException(
              reason: ProvisioningFailureReason.catalogMalformed,
              message: 'Campo obbligatorio mancante: platform.',
            )),
        architecture: json['architecture'] as String? ??
            (throw const ProvisioningException(
              reason: ProvisioningFailureReason.catalogMalformed,
              message: 'Campo obbligatorio mancante: architecture.',
            )),
        fileName: json['fileName'] as String? ??
            (throw const ProvisioningException(
              reason: ProvisioningFailureReason.catalogMalformed,
              message: 'Campo obbligatorio mancante: fileName.',
            )),
        sourceKind: CatalogArtifactSourceKind.parse(rawSourceKind),
        downloadUri: json['downloadUri'] as String?,
        bundledAssetId: json['bundledAssetId'] as String?,
        sizeBytes: (json['sizeBytes'] as num?)?.toInt() ??
            (throw const ProvisioningException(
              reason: ProvisioningFailureReason.catalogMalformed,
              message: 'Campo obbligatorio mancante: sizeBytes.',
            )),
        sha256: json['sha256'] as String? ??
            (throw const ProvisioningException(
              reason: ProvisioningFailureReason.catalogMalformed,
              message: 'Campo obbligatorio mancante: sha256.',
            )),
        compression: CatalogCompressionFormat.parse(rawCompression),
        license: json['license'] as String? ?? 'unknown',
        runtimeCompatibility: json['runtimeCompatibility'] as String?,
        minimumRuntimeBuild: json['minimumRuntimeBuild'] as String?,
        maximumRuntimeBuild: json['maximumRuntimeBuild'] as String?,
        modelArchitecture: json['modelArchitecture'] as String?,
        quantization: json['quantization'] as String?,
        contextLength: (json['contextLength'] as num?)?.toInt(),
        capabilities: parsedCaps,
        hardwareCompatibilityTags: parsedHwTags,
        deprecated: json['deprecated'] as bool? ?? false,
        releaseChannel: json['releaseChannel'] as String? ?? 'stable',
        metadata: json['metadata'] != null
            ? Map<String, dynamic>.from(json['metadata'] as Map)
            : const {},
      );
    } on ProvisioningException {
      rethrow;
    } catch (e) {
      throw ProvisioningException(
        reason: ProvisioningFailureReason.catalogMalformed,
        message: 'Errore di parsing dei campi di CatalogArtifact.',
        cause: e,
      );
    }
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
      'sourceKind': sourceKind.name,
      if (downloadUri != null) 'downloadUri': downloadUri,
      if (bundledAssetId != null) 'bundledAssetId': bundledAssetId,
      'sizeBytes': sizeBytes,
      'sha256': sha256,
      'compression': compression.name,
      'license': license,
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
    CatalogArtifactSourceKind? sourceKind,
    String? downloadUri,
    String? bundledAssetId,
    int? sizeBytes,
    String? sha256,
    CatalogCompressionFormat? compression,
    String? license,
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
      sourceKind: sourceKind ?? this.sourceKind,
      downloadUri: downloadUri ?? this.downloadUri,
      bundledAssetId: bundledAssetId ?? this.bundledAssetId,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      sha256: sha256 ?? this.sha256,
      compression: compression ?? this.compression,
      license: license ?? this.license,
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

  CatalogManifest({
    required this.schemaVersion,
    required this.catalogId,
    required this.generatedAt,
    required List<CatalogArtifact> artifacts,
    Map<String, dynamic> metadata = const {},
  })  : artifacts = List.unmodifiable(List<CatalogArtifact>.from(artifacts)),
        metadata = _ensureJsonSafeMap(metadata);

  factory CatalogManifest.fromJson(Map<String, dynamic> json) {
    try {
      final rawSchema = json['schemaVersion'] as String?;
      if (rawSchema == null || rawSchema.isEmpty) {
        throw const ProvisioningException(
          reason: ProvisioningFailureReason.catalogMalformed,
          message: 'Campo obbligatorio mancante: schemaVersion.',
        );
      }

      final rawCatalogId = json['catalogId'] as String?;
      if (rawCatalogId == null || rawCatalogId.isEmpty) {
        throw const ProvisioningException(
          reason: ProvisioningFailureReason.catalogMalformed,
          message: 'Campo obbligatorio mancante: catalogId.',
        );
      }

      final rawArtifacts = json['artifacts'] as List<dynamic>?;
      if (rawArtifacts == null) {
        throw const ProvisioningException(
          reason: ProvisioningFailureReason.catalogMalformed,
          message: 'Campo obbligatorio mancante: artifacts.',
        );
      }

      final parsedArtifacts = <CatalogArtifact>[];
      for (final e in rawArtifacts) {
        if (e is! Map) {
          throw const ProvisioningException(
            reason: ProvisioningFailureReason.catalogMalformed,
            message: 'Elemento non mappa presente nella lista artifacts.',
          );
        }
        parsedArtifacts
            .add(CatalogArtifact.fromJson(Map<String, dynamic>.from(e)));
      }

      return CatalogManifest(
        schemaVersion: rawSchema,
        catalogId: rawCatalogId,
        generatedAt: json['generatedAt'] as String? ?? '',
        artifacts: parsedArtifacts,
        metadata: json['metadata'] != null
            ? Map<String, dynamic>.from(json['metadata'] as Map)
            : const {},
      );
    } on ProvisioningException {
      rethrow;
    } catch (e) {
      throw ProvisioningException(
        reason: ProvisioningFailureReason.catalogMalformed,
        message: 'Errore di parsing del catalogo manifest.',
        cause: e,
      );
    }
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
