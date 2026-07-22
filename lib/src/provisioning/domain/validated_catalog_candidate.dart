import 'package:meta/meta.dart';
import 'catalog_acquisition_models.dart';
import 'catalog_compatibility_evaluator.dart';

/// Rappresentazione di un candidato di catalogo già sottoposto a validazione strutturale e di firma.
@immutable
final class ValidatedCatalogCandidate {
  final CatalogEnvelope envelope;
  final CatalogSource source;
  final CatalogTrustLevel trustLevel;
  final CatalogCompatibilityResult compatibility;
  final String canonicalPayloadDigest;

  ValidatedCatalogCandidate({
    required this.envelope,
    required this.source,
    required this.trustLevel,
    required this.compatibility,
    required this.canonicalPayloadDigest,
  }) {
    // Finding 3: Invariante di coerenza tra sorgente e livello di fiducia
    switch (source) {
      case CatalogSource.remoteSigned:
      case CatalogSource.cachedSigned:
        if (trustLevel != CatalogTrustLevel.signatureVerified) {
          throw ArgumentError(
            'Un catalogo firmato ($source) richiede il livello di fiducia signatureVerified, ottenuto: $trustLevel',
          );
        }
        break;
      case CatalogSource.bundledBootstrap:
        if (trustLevel != CatalogTrustLevel.bootstrapDeclared) {
          throw ArgumentError(
            'Un catalogo bootstrap ($source) richiede il livello di fiducia bootstrapDeclared, ottenuto: $trustLevel',
          );
        }
        break;
      case CatalogSource.localDevelopment:
        if (trustLevel != CatalogTrustLevel.developmentUnsigned &&
            trustLevel != CatalogTrustLevel.locallyImported) {
          throw ArgumentError(
            'Un catalogo di sviluppo locale ($source) richiede developmentUnsigned o locallyImported, ottenuto: $trustLevel',
          );
        }
        break;
    }
  }

  String get catalogId => envelope.signedPayload.catalogId;
  int get catalogRevision => envelope.signedPayload.catalogRevision;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ValidatedCatalogCandidate &&
          runtimeType == other.runtimeType &&
          envelope == other.envelope &&
          source == other.source &&
          trustLevel == other.trustLevel &&
          canonicalPayloadDigest == other.canonicalPayloadDigest;

  @override
  int get hashCode => Object.hash(
        envelope,
        source,
        trustLevel,
        canonicalPayloadDigest,
      );
}
