import '../domain/catalog_manifest.dart';
import '../domain/provisioning_options.dart';

/// Validatore semantico per documenti [CatalogManifest].
abstract final class CatalogManifestValidator {
  static final RegExp _sha256Regex = RegExp(r'^[a-f0-9]{64}$');
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

    if (artifact.version.trim().isEmpty || artifact.buildId.trim().isEmpty) {
      throw ProvisioningException(
        reason: ProvisioningFailureReason.invalidCatalog,
        message: 'Artefatto "$id" ha version o buildId vuoto.',
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

    _validateFileName(id, artifact.fileName);

    if (artifact.downloadUri != null && artifact.downloadUri!.isNotEmpty) {
      final uri = Uri.tryParse(artifact.downloadUri!);
      if (uri == null || uri.scheme.toLowerCase() != 'https') {
        throw ProvisioningException(
          reason: ProvisioningFailureReason.invalidSourceUri,
          message: 'Artefatto "$id" ha un downloadUri non HTTPS sicuro.',
        );
      }
    }

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

  static void _validateFileName(String artifactId, String fileName) {
    final trimmed = fileName.trim();
    if (trimmed.isEmpty) {
      throw ProvisioningException(
        reason: ProvisioningFailureReason.invalidCatalog,
        message: 'Artefatto "$artifactId" ha un fileName vuoto.',
      );
    }

    if (trimmed.contains('/') ||
        trimmed.contains('\\') ||
        trimmed.contains('..')) {
      throw ProvisioningException(
        reason: ProvisioningFailureReason.invalidCatalog,
        message:
            'Artefatto "$artifactId" contiene path traversal o separatori nel fileName.',
      );
    }

    if (_reservedWindowsNamesRegex.hasMatch(trimmed)) {
      throw ProvisioningException(
        reason: ProvisioningFailureReason.invalidCatalog,
        message:
            'Artefatto "$artifactId" utilizza un nome dispositivo riservato Windows.',
      );
    }

    if (trimmed.startsWith('.') || trimmed.endsWith('.')) {
      throw ProvisioningException(
        reason: ProvisioningFailureReason.invalidCatalog,
        message:
            'Artefatto "$artifactId" ha un fileName che inizia o termina con punto.',
      );
    }
  }
}
