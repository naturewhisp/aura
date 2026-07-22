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

  const ValidatedCatalogCandidate({
    required this.envelope,
    required this.source,
    required this.trustLevel,
    required this.compatibility,
    required this.canonicalPayloadDigest,
  });

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
