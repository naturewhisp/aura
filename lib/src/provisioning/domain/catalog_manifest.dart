import 'package:meta/meta.dart';
import 'json_safe_value.dart';
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

/// Sentinel constant per rilevare il passaggio esplicito di null nei costruttori [copyWith].
const Object _unset = Object();

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
        metadata = JsonSafeValue.ensureJsonSafeMap(metadata);

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

      final rawSizeBytes = json['sizeBytes'];
      if (rawSizeBytes is! int) {
        throw const ProvisioningException(
          reason: ProvisioningFailureReason.catalogMalformed,
          message:
              'Il campo sizeBytes deve essere un numero intero JSON strict.',
        );
      }

      final rawCtxLen = json['contextLength'];
      if (rawCtxLen != null && rawCtxLen is! int) {
        throw const ProvisioningException(
          reason: ProvisioningFailureReason.catalogMalformed,
          message:
              'Il campo contextLength deve essere un numero intero JSON strict.',
        );
      }

      final displayName = json['displayName'] as String?;
      if (displayName == null || displayName.trim().isEmpty) {
        throw const ProvisioningException(
          reason: ProvisioningFailureReason.catalogMalformed,
          message: 'Campo obbligatorio mancante: displayName.',
        );
      }

      final license = json['license'] as String?;
      if (license == null || license.trim().isEmpty) {
        throw const ProvisioningException(
          reason: ProvisioningFailureReason.catalogMalformed,
          message: 'Campo obbligatorio mancante: license.',
        );
      }

      final releaseChannel = (json['releaseChannel'] as String?) ?? 'stable';

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
        displayName: displayName,
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
        sizeBytes: rawSizeBytes,
        sha256: json['sha256'] as String? ??
            (throw const ProvisioningException(
              reason: ProvisioningFailureReason.catalogMalformed,
              message: 'Campo obbligatorio mancante: sha256.',
            )),
        compression: CatalogCompressionFormat.parse(rawCompression),
        license: license,
        runtimeCompatibility: json['runtimeCompatibility'] as String?,
        minimumRuntimeBuild: json['minimumRuntimeBuild'] as String?,
        maximumRuntimeBuild: json['maximumRuntimeBuild'] as String?,
        modelArchitecture: json['modelArchitecture'] as String?,
        quantization: json['quantization'] as String?,
        contextLength: rawCtxLen,
        capabilities: parsedCaps,
        hardwareCompatibilityTags: parsedHwTags,
        deprecated: json['deprecated'] as bool? ?? false,
        releaseChannel: releaseChannel,
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
    Object? downloadUri = _unset,
    Object? bundledAssetId = _unset,
    int? sizeBytes,
    String? sha256,
    CatalogCompressionFormat? compression,
    String? license,
    Object? runtimeCompatibility = _unset,
    Object? minimumRuntimeBuild = _unset,
    Object? maximumRuntimeBuild = _unset,
    Object? modelArchitecture = _unset,
    Object? quantization = _unset,
    Object? contextLength = _unset,
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
      downloadUri: identical(downloadUri, _unset)
          ? this.downloadUri
          : downloadUri as String?,
      bundledAssetId: identical(bundledAssetId, _unset)
          ? this.bundledAssetId
          : bundledAssetId as String?,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      sha256: sha256 ?? this.sha256,
      compression: compression ?? this.compression,
      license: license ?? this.license,
      runtimeCompatibility: identical(runtimeCompatibility, _unset)
          ? this.runtimeCompatibility
          : runtimeCompatibility as String?,
      minimumRuntimeBuild: identical(minimumRuntimeBuild, _unset)
          ? this.minimumRuntimeBuild
          : minimumRuntimeBuild as String?,
      maximumRuntimeBuild: identical(maximumRuntimeBuild, _unset)
          ? this.maximumRuntimeBuild
          : maximumRuntimeBuild as String?,
      modelArchitecture: identical(modelArchitecture, _unset)
          ? this.modelArchitecture
          : modelArchitecture as String?,
      quantization: identical(quantization, _unset)
          ? this.quantization
          : quantization as String?,
      contextLength: identical(contextLength, _unset)
          ? this.contextLength
          : contextLength as int?,
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
        metadata = JsonSafeValue.ensureJsonSafeMap(metadata);

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

      final rawGeneratedAt = json['generatedAt'] as String?;
      if (rawGeneratedAt == null || rawGeneratedAt.isEmpty) {
        throw const ProvisioningException(
          reason: ProvisioningFailureReason.catalogMalformed,
          message: 'Campo obbligatorio mancante: generatedAt.',
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
        generatedAt: rawGeneratedAt,
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
      );
    }
  }

  CatalogArtifact? findArtifact(String artifactId) {
    final cleanId = artifactId.trim();
    for (final a in artifacts) {
      if (a.artifactId == cleanId) return a;
    }
    return null;
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

  /// Costruttore factory per il catalogo manifest predefinito iniziale di A.U.R.A.
  factory CatalogManifest.initialDefault(
      {String catalogId = 'aura-official-catalog'}) {
    return CatalogManifest(
      schemaVersion: '1.0',
      catalogId: catalogId,
      generatedAt: '2026-07-22T18:00:00.000Z',
      artifacts: [
        CatalogArtifact(
          artifactId: 'gemma-4-12b-it-qat-q4-0',
          artifactType: CatalogArtifactType.model,
          displayName: 'Gemma 4 12B IT QAT (Q4_0)',
          version: 'aaec3dd9d1012557147a627142759994d1fd8d37',
          buildId: 'aaec3dd9d1012557147a627142759994d1fd8d37',
          platform: 'all',
          architecture: 'all',
          fileName: 'gemma-4-12B-it-QAT-Q4_0.gguf',
          sourceKind: CatalogArtifactSourceKind.remoteHttps,
          downloadUri:
              'https://huggingface.co/lmstudio-community/gemma-4-12B-it-QAT-GGUF/resolve/aaec3dd9d1012557147a627142759994d1fd8d37/gemma-4-12B-it-QAT-Q4_0.gguf',
          sizeBytes: 6975879008,
          sha256:
              'f568ac5de71c8fcac5d5794494388ad94db9e18b4368ca897e21b30d2448eeec',
          compression: CatalogCompressionFormat.none,
          license: 'apache-2.0',
          modelArchitecture: 'gemma4',
          quantization: 'Q4_0',
          minimumRuntimeBuild: 'b3500',
          capabilities: const [
            'generate_character_response',
            'instruction_following'
          ],
          metadata: const {
            'repository': 'lmstudio-community/gemma-4-12B-it-QAT-GGUF',
            'revision': 'aaec3dd9d1012557147a627142759994d1fd8d37',
            'sourceCheckpoint': 'google/gemma-4-12B-it-qat-q4_0-unquantized',
            'quantizationStrategy': 'QAT',
            'role': 'actor',
            'logicalModelAlias': 'actor.default',
            'isDefaultActor': true,
          },
        ),
      ],
      metadata: const {
        'integritySource': 'bundled-bootstrap-catalog',
        'integrityAlgorithm': 'sha256',
        'fingerprintStatus': 'bootstrap-declared',
        'catalogVersion': 'bootstrap-v1',
      },
    );
  }
}
