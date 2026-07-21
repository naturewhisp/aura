import '../domain/catalog_manifest.dart';
import '../domain/provisioning_options.dart';
import '../infrastructure/provisioning_path_resolver.dart';

/// Validatore semantico per documenti [CatalogManifest].
abstract final class CatalogManifestValidator {
  static final RegExp _sha256Regex = RegExp(r'^[a-f0-9]{64}$');
  static final RegExp _invalidWindowsCharsRegex = RegExp(r'[<>:"|?*\x00-\x1F]');
  static final RegExp _reservedWindowsNamesRegex = RegExp(
    r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\..*)?$',
    caseSensitive: false,
  );

  /// Valida il catalogo manifest. Se invalido, lancia una [ProvisioningException].
  static void validate(CatalogManifest manifest) {
    if (manifest.catalogId.trim().isEmpty) {
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.invalidCatalog,
        message: 'Il catalogo ha un catalogId vuoto.',
      );
    }

    if (manifest.generatedAt.trim().isEmpty ||
        DateTime.tryParse(manifest.generatedAt.trim()) == null) {
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.invalidCatalog,
        message:
            'Il catalogo ha un campo generatedAt non valido (atteso ISO-8601).',
      );
    }

    final seenArtifactIds = <String>{};

    for (final artifact in manifest.artifacts) {
      _validateArtifact(artifact, seenArtifactIds);
    }
  }

  static void _validateArtifact(
    CatalogArtifact artifact,
    Set<String> seenArtifactIds,
  ) {
    final id = artifact.artifactId.trim();
    if (id.isEmpty) {
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.invalidCatalog,
        message: 'Rilevato artefatto con artifactId vuoto.',
      );
    }

    if (!seenArtifactIds.add(id)) {
      throw ProvisioningException(
        reason: ProvisioningFailureReason.invalidCatalog,
        message: 'artifactId duplicato nel catalogo: "$id".',
      );
    }

    if (artifact.displayName.trim().isEmpty) {
      throw ProvisioningException(
        reason: ProvisioningFailureReason.invalidCatalog,
        message: 'Artefatto "$id" ha displayName vuoto.',
      );
    }

    if (artifact.version.trim().isEmpty || artifact.buildId.trim().isEmpty) {
      throw ProvisioningException(
        reason: ProvisioningFailureReason.invalidCatalog,
        message: 'Artefatto "$id" ha version o buildId vuoto.',
      );
    }

    if (artifact.platform.trim().isEmpty ||
        artifact.architecture.trim().isEmpty) {
      throw ProvisioningException(
        reason: ProvisioningFailureReason.invalidCatalog,
        message: 'Artefatto "$id" ha platform o architecture vuota.',
      );
    }

    if (artifact.license.trim().isEmpty) {
      throw ProvisioningException(
        reason: ProvisioningFailureReason.invalidCatalog,
        message: 'Artefatto "$id" ha license vuota.',
      );
    }

    if (artifact.releaseChannel.trim().isEmpty) {
      throw ProvisioningException(
        reason: ProvisioningFailureReason.invalidCatalog,
        message: 'Artefatto "$id" ha releaseChannel vuoto.',
      );
    }

    if (artifact.sizeBytes <= 0) {
      throw ProvisioningException(
        reason: ProvisioningFailureReason.invalidCatalog,
        message:
            'Artefatto "$id" ha sizeBytes non valido: ${artifact.sizeBytes}.',
      );
    }

    final normalizedSha = artifact.sha256.trim().toLowerCase();
    if (!_sha256Regex.hasMatch(normalizedSha)) {
      throw ProvisioningException(
        reason: ProvisioningFailureReason.invalidCatalog,
        message:
            'Artefatto "$id" ha un hash SHA-256 non valido (attesi 64 caratteri esadecimali).',
      );
    }

    if (artifact.contextLength != null && artifact.contextLength! <= 0) {
      throw ProvisioningException(
        reason: ProvisioningFailureReason.invalidCatalog,
        message: 'Artefatto "$id" ha contextLength <= 0.',
      );
    }

    _validateFileName(id, artifact.fileName);
    _validateSourceKind(artifact);

    if (artifact.artifactType == CatalogArtifactType.model) {
      if (artifact.modelArchitecture == null ||
          artifact.modelArchitecture!.trim().isEmpty) {
        throw ProvisioningException(
          reason: ProvisioningFailureReason.invalidCatalog,
          message: 'Artefatto modello "$id" non specifica modelArchitecture.',
        );
      }
      if (artifact.quantization == null ||
          artifact.quantization!.trim().isEmpty) {
        throw ProvisioningException(
          reason: ProvisioningFailureReason.invalidCatalog,
          message: 'Artefatto modello "$id" non specifica quantization.',
        );
      }
    }

    if (artifact.artifactType == CatalogArtifactType.runtime) {
      if (artifact.minimumRuntimeBuild == null ||
          artifact.minimumRuntimeBuild!.trim().isEmpty) {
        throw ProvisioningException(
          reason: ProvisioningFailureReason.invalidCatalog,
          message: 'Artefatto runtime "$id" non specifica minimumRuntimeBuild.',
        );
      }
    }
  }

  static void _validateSourceKind(CatalogArtifact artifact) {
    final id = artifact.artifactId;
    switch (artifact.sourceKind) {
      case CatalogArtifactSourceKind.remoteHttps:
        if (artifact.downloadUri == null ||
            artifact.downloadUri!.trim().isEmpty) {
          throw ProvisioningException(
            reason: ProvisioningFailureReason.invalidSourceUri,
            message:
                'Artefatto remoto "$id" richiede un downloadUri non vuoto.',
          );
        }
        final uri = Uri.tryParse(artifact.downloadUri!.trim());
        if (uri == null ||
            !uri.isAbsolute ||
            uri.scheme.toLowerCase() != 'https' ||
            uri.host.isEmpty ||
            uri.userInfo.isNotEmpty) {
          throw ProvisioningException(
            reason: ProvisioningFailureReason.invalidSourceUri,
            message:
                'Artefatto remoto "$id" ha un downloadUri non HTTPS assoluto valido.',
          );
        }
        if (artifact.bundledAssetId != null) {
          throw ProvisioningException(
            reason: ProvisioningFailureReason.invalidCatalog,
            message:
                'Artefatto remoto "$id" non può specificare bundledAssetId.',
          );
        }
        break;

      case CatalogArtifactSourceKind.bundled:
        if (artifact.downloadUri != null) {
          throw ProvisioningException(
            reason: ProvisioningFailureReason.invalidCatalog,
            message:
                'Artefatto bundled "$id" non può dichiarare un downloadUri remoto.',
          );
        }
        if (artifact.bundledAssetId == null ||
            artifact.bundledAssetId!.trim().isEmpty) {
          throw ProvisioningException(
            reason: ProvisioningFailureReason.invalidCatalog,
            message:
                'Artefatto bundled "$id" richiede un bundledAssetId non vuoto.',
          );
        }
        ProvisioningPathResolver.sanitizeSegment(artifact.bundledAssetId!);
        break;

      case CatalogArtifactSourceKind.localImport:
        if (artifact.downloadUri != null) {
          throw ProvisioningException(
            reason: ProvisioningFailureReason.invalidCatalog,
            message:
                'Artefatto localImport "$id" non può dichiarare un downloadUri predefinito.',
          );
        }
        if (artifact.bundledAssetId != null) {
          throw ProvisioningException(
            reason: ProvisioningFailureReason.invalidCatalog,
            message:
                'Artefatto localImport "$id" non può dichiarare un bundledAssetId.',
          );
        }
        break;
    }
  }

  static void _validateFileName(String artifactId, String fileName) {
    if (fileName.isEmpty) {
      throw ProvisioningException(
        reason: ProvisioningFailureReason.invalidCatalog,
        message: 'Artefatto "$artifactId" ha un fileName vuoto.',
      );
    }

    if (fileName.contains('/') || fileName.contains('\\')) {
      throw ProvisioningException(
        reason: ProvisioningFailureReason.invalidCatalog,
        message:
            'Artefatto "$artifactId" contiene separatori di percorso nel fileName.',
      );
    }

    if (fileName.contains('..')) {
      throw ProvisioningException(
        reason: ProvisioningFailureReason.invalidCatalog,
        message:
            'Artefatto "$artifactId" contiene path traversal ("..") nel fileName.',
      );
    }

    if (_invalidWindowsCharsRegex.hasMatch(fileName)) {
      throw ProvisioningException(
        reason: ProvisioningFailureReason.invalidCatalog,
        message:
            'Artefatto "$artifactId" contiene caratteri non validi Windows nel fileName.',
      );
    }

    final trimmed = fileName.trim();
    if (trimmed != fileName) {
      throw ProvisioningException(
        reason: ProvisioningFailureReason.invalidCatalog,
        message:
            'Artefatto "$artifactId" ha spazi iniziali o finali nel fileName.',
      );
    }

    if (trimmed.startsWith('.') || trimmed.endsWith('.')) {
      throw ProvisioningException(
        reason: ProvisioningFailureReason.invalidCatalog,
        message:
            'Artefatto "$artifactId" ha un fileName che inizia o termina con un punto.',
      );
    }

    if (_reservedWindowsNamesRegex.hasMatch(trimmed)) {
      throw ProvisioningException(
        reason: ProvisioningFailureReason.invalidCatalog,
        message:
            'Artefatto "$artifactId" utilizza un nome dispositivo riservato Windows.',
      );
    }

    if (trimmed.length > 255) {
      throw ProvisioningException(
        reason: ProvisioningFailureReason.invalidCatalog,
        message:
            'Artefatto "$artifactId" supera la lunghezza massima consentita di 255 caratteri per il fileName.',
      );
    }
  }
}
