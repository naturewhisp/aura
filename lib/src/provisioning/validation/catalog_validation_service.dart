import '../domain/catalog_acquisition_exceptions.dart';
import '../domain/catalog_acquisition_models.dart';
import '../domain/immutable_repository_revision_policy.dart';

/// Esito dell'operazione di validazione di un envelope di catalogo.
final class CatalogValidationResult {
  final bool isValid;
  final CatalogAcquisitionFailureReason? failureReason;
  final String? errorMessage;

  const CatalogValidationResult.valid()
      : isValid = true,
        failureReason = null,
        errorMessage = null;

  const CatalogValidationResult.invalid({
    required CatalogAcquisitionFailureReason reason,
    required String message,
  })  : isValid = false,
        failureReason = reason,
        errorMessage = message;
}

/// Servizio centrale per la validazione strutturale, semantica e temporale di un catalogo firmato.
final class CatalogValidationService {
  const CatalogValidationService();

  /// Convalida l'[envelope] rispetto al tempo iniettato [nowUtc] e alla tolleranza di clock [allowedClockSkew].
  CatalogValidationResult validate(
    CatalogEnvelope envelope, {
    required DateTime nowUtc,
    Duration allowedClockSkew = const Duration(minutes: 5),
    CatalogSource source = CatalogSource.remoteSigned,
  }) {
    final payload = envelope.signedPayload;

    // 1. Schema version
    if (payload.schemaVersion != '1.0') {
      return CatalogValidationResult.invalid(
        reason: CatalogAcquisitionFailureReason.unsupportedSchemaVersion,
        message: 'Versione di schema non supportata: ${payload.schemaVersion}',
      );
    }

    // 2. Signature algorithm
    if (payload.signatureAlgorithm != 'ed25519-v1') {
      return CatalogValidationResult.invalid(
        reason: CatalogAcquisitionFailureReason.unsupportedSignatureAlgorithm,
        message:
            'Algoritmo di firma non supportato: ${payload.signatureAlgorithm}',
      );
    }

    // 3. Key ID
    if (payload.keyId.trim().isEmpty) {
      return const CatalogValidationResult.invalid(
        reason: CatalogAcquisitionFailureReason.unknownKeyId,
        message: 'Identificatore della chiave pubblica keyId vuoto.',
      );
    }

    // 4. Validazione date (ISO 8601)
    DateTime issuedAt;
    DateTime expiresAt;
    try {
      issuedAt = DateTime.parse(payload.issuedAt).toUtc();
    } catch (_) {
      return CatalogValidationResult.invalid(
        reason: CatalogAcquisitionFailureReason.invalidIssuedAt,
        message: 'Data di emissione issuedAt non valida: ${payload.issuedAt}',
      );
    }

    try {
      expiresAt = DateTime.parse(payload.expiresAt).toUtc();
    } catch (_) {
      return CatalogValidationResult.invalid(
        reason: CatalogAcquisitionFailureReason.invalidExpiresAt,
        message: 'Data di scadenza expiresAt non valida: ${payload.expiresAt}',
      );
    }

    // Finding 4: expiresAt deve essere STRETTAMENTE successivo a issuedAt
    if (!expiresAt.isAfter(issuedAt)) {
      return const CatalogValidationResult.invalid(
        reason: CatalogAcquisitionFailureReason.invalidExpiresAt,
        message:
            'La data di scadenza expiresAt deve essere strettamente successiva alla data di emissione issuedAt.',
      );
    }

    // Finding 6: Validazione che issuedAt non sia troppo nel futuro oltre il clock skew
    final effectiveNow = nowUtc.toUtc();
    if (issuedAt.isAfter(effectiveNow.add(allowedClockSkew))) {
      return CatalogValidationResult.invalid(
        reason: CatalogAcquisitionFailureReason.invalidIssuedAt,
        message:
            'La data di emissione issuedAt è nel futuro oltre il margine di clock skew: $issuedAt',
      );
    }

    // Verificare la scadenza temporale con margine di clock skew
    if (expiresAt.isBefore(effectiveNow.subtract(allowedClockSkew))) {
      return CatalogValidationResult.invalid(
        reason: CatalogAcquisitionFailureReason.catalogExpired,
        message:
            'Il catalogo è scaduto il $expiresAt (tempo corrente: $effectiveNow).',
      );
    }

    // 5. Validazione dei modelli e degli artefatti nel manifest
    final manifest = payload.manifest;
    final seenArtifactIdentities = <ArtifactIdentity>{};

    for (final artifact in manifest.artifacts) {
      // Finding 5: Per cataloghi firmati remoti o cached, repositoryRevision DEVE essere esplicitata
      final repoRevision = artifact.metadata['repositoryRevision'] as String?;
      if ((source == CatalogSource.remoteSigned ||
              source == CatalogSource.cachedSigned) &&
          (repoRevision == null || repoRevision.trim().isEmpty)) {
        return CatalogValidationResult.invalid(
          reason: CatalogAcquisitionFailureReason.floatingRepositoryRevision,
          message:
              'Campo repositoryRevision mancante nei metadati dell\'artefatto ${artifact.artifactId}.',
        );
      }

      final effectiveRevision = repoRevision ?? artifact.version;

      // Validazione della revisione immutabile del repository
      try {
        ImmutableRepositoryRevisionPolicy.validateRevision(
          revision: effectiveRevision,
          source: source,
        );
      } on InvalidCatalogRevisionException catch (e) {
        return CatalogValidationResult.invalid(
          reason: CatalogAcquisitionFailureReason.floatingRepositoryRevision,
          message: e.message,
        );
      }

      // Validazione Content Identity (sizeBytes > 0, sha256 64 hex)
      if (artifact.sizeBytes <= 0) {
        return CatalogValidationResult.invalid(
          reason: CatalogAcquisitionFailureReason.invalidSizeBytes,
          message:
              'Dimensioni byte non valide per la variante ${artifact.artifactId}: ${artifact.sizeBytes}',
        );
      }

      final shaLower = artifact.sha256.toLowerCase().trim();
      final shaRegExp = RegExp(r'^[a-f0-9]{64}$');
      if (!shaRegExp.hasMatch(shaLower)) {
        return CatalogValidationResult.invalid(
          reason: CatalogAcquisitionFailureReason.invalidSha256,
          message:
              'SHA-256 non valido per la variante ${artifact.artifactId}: ${artifact.sha256}',
        );
      }

      // Verifica assenza di duplicate ArtifactIdentity
      final contentIdentity = ContentIdentity(
        sizeBytes: artifact.sizeBytes,
        sha256: shaLower,
      );
      final artifactIdentity = ArtifactIdentity(
        artifactId: artifact.artifactId,
        version: artifact.version,
        buildId: artifact.buildId,
        contentIdentity: contentIdentity,
      );

      if (seenArtifactIdentities.contains(artifactIdentity)) {
        return CatalogValidationResult.invalid(
          reason: CatalogAcquisitionFailureReason.duplicateArtifactIdentity,
          message:
              'Dichiarazione duplicata dell\'artefatto $artifactIdentity nel catalogo.',
        );
      }
      seenArtifactIdentities.add(artifactIdentity);
    }

    return const CatalogValidationResult.valid();
  }
}
