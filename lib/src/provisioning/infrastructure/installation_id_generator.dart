import '../domain/catalog_manifest.dart';

/// Contratto astratto per la generazione di identificatori di installazione (`installationId`).
abstract interface class InstallationIdGenerator {
  String generateId({
    required CatalogArtifact artifact,
    required DateTime timestampUtc,
  });
}

/// Implementazione concreta deterministica e monotona basata su sequenza atomica per istanza.
final class MonotonicInstallationIdGenerator
    implements InstallationIdGenerator {
  int _sequence = 0;

  MonotonicInstallationIdGenerator();

  @override
  String generateId({
    required CatalogArtifact artifact,
    required DateTime timestampUtc,
  }) {
    final seq = ++_sequence;
    final ms = timestampUtc.millisecondsSinceEpoch;
    return 'inst-${artifact.artifactId}-${artifact.version}-$ms-$seq';
  }
}
