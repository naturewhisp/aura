import 'package:meta/meta.dart';

/// Descrittore di un file scaricato con successo nella directory di staging (`.part`).
///
/// **Invariante Tranche 6.4c:**
/// L'emissione di uno [StagingArtifact] certifica esclusivamente che l'I/O ed il download
/// si sono completati (`downloadComplete == true`), ma NON costituisce verifica di integrità
/// crittografica (`cryptographicallyVerified == false`) o installazione nel registry finale.
@immutable
final class StagingArtifact {
  /// Identificatore unico dell'operazione di download.
  final String operationId;

  /// Identificatore logico dell'artefatto.
  final String artifactId;

  /// Percorso assoluto al file temporaneo `.part` nella directory di staging.
  final String stagingPath;

  /// Dimensione effettiva in byte del file `.part`.
  final int sizeBytes;

  /// Strong ETag della risorsa restituito dal server remoto (se presente).
  final String? strongEtag;

  /// Timestamp UTC di completamento del download nello staging.
  final DateTime completedAtUtc;

  /// Indica se il file e stato scaricato integralmente (sempre `true`).
  final bool downloadComplete;

  /// Indica se l'hash SHA-256 e stato crittograficamente verificato (sempre `false` in 6.4c).
  final bool cryptographicallyVerified;

  StagingArtifact({
    required this.operationId,
    required this.artifactId,
    required this.stagingPath,
    required this.sizeBytes,
    this.strongEtag,
    required DateTime completedAtUtc,
    this.downloadComplete = true,
    this.cryptographicallyVerified = false,
  }) : completedAtUtc = completedAtUtc.toUtc();
}
