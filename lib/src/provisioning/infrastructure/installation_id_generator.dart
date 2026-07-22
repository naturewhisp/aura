import '../domain/catalog_manifest.dart';

/// Generatore deterministico e monotono di identificatori di installazione (`installationId`).
abstract final class InstallationIdGenerator {
  static int _sequence = 0;

  /// Genera un [installationId] univoco basato sulla lettura singola del timestamp e su un contatore monotono.
  static String generateId({
    required CatalogArtifact artifact,
    required DateTime timestampUtc,
  }) {
    final seq = ++_sequence;
    final ms = timestampUtc.millisecondsSinceEpoch;
    return 'inst-${artifact.artifactId}-${artifact.version}-$ms-$seq';
  }
}
