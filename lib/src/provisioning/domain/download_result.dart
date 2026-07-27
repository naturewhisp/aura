import 'package:meta/meta.dart';
import 'download_checkpoint.dart';
import 'staging_artifact.dart';

/// Categorizzazione delle ragioni di fallimento o interruzione di un download.
enum DownloadFailureReason {
  /// Connessione di rete persa o socket error (retryable).
  networkDisconnected,

  /// Timeout di rete durante la richiesta o lo streaming (retryable).
  networkTimeout,

  /// Spazio su disco insufficiente nella directory di staging (non retryable).
  insufficientStorage,

  /// ETag mismatch durante il resume o risposta 206 non valida (handlable via reset).
  etagMismatch,

  /// Errore di status HTTP diverso da 200, 206, 416 (es. 404, 500).
  httpStatusError,

  /// URL non valido o scheme non HTTP/HTTPS.
  invalidUrl,

  /// Operazione annullata esplicitamente dal chiamante (cancelled).
  cancelled,

  /// Errore di I/O o scrittura file locale.
  ioFailure,

  /// Checkpoint corrotto o non coerente col file locale.
  checkpointCorrupted,

  /// Troppi redirect HTTP consecutivi (superato il limite di 5).
  tooManyRedirects,

  /// Tentativo di redirect non sicuro da HTTPS a HTTP (vietato).
  insecureRedirect,

  /// Tentativo di download simultaneo su uno stesso target gia in esecuzione.
  destinationLocked,
}

/// Contenitore immutabile dell'esito dell'operazione di download.
@immutable
final class DownloadResult {
  /// Descrittore dell'artefatto nello staging in caso di successo (`null` in caso di fallimento/cancellazione).
  final StagingArtifact? stagingArtifact;

  /// Causa del fallimento in caso di errore o cancellazione (`null` in caso di successo).
  final DownloadFailureReason? failureReason;

  /// Messaggio descrittivo sanitizzato sull'esito.
  final String? message;

  /// Checkpoint registrato al momento del completamento, interruzione o cancellazione.
  final DownloadCheckpoint? checkpoint;

  /// Indica se il fallimento e di natura temporanea e consente un nuovo tentativo.
  final bool isRetryable;

  const DownloadResult._({
    this.stagingArtifact,
    this.failureReason,
    this.message,
    this.checkpoint,
    this.isRetryable = false,
  });

  /// Crea un esito positivo con l'artefatto salvato nello staging.
  factory DownloadResult.success(StagingArtifact artifact) {
    return DownloadResult._(stagingArtifact: artifact);
  }

  /// Crea un esito negativo per errore di rete, I/O o HTTP.
  factory DownloadResult.failure({
    required DownloadFailureReason reason,
    required String message,
    DownloadCheckpoint? checkpoint,
    bool isRetryable = false,
  }) {
    return DownloadResult._(
      failureReason: reason,
      message: message,
      checkpoint: checkpoint,
      isRetryable: isRetryable,
    );
  }

  /// Crea un esito di cancellazione cooperativa tramite [DownloadCancellationToken].
  factory DownloadResult.cancelled({
    required String message,
    DownloadCheckpoint? checkpoint,
  }) {
    return DownloadResult._(
      failureReason: DownloadFailureReason.cancelled,
      message: message,
      checkpoint: checkpoint,
      isRetryable: true,
    );
  }

  /// Indica se il download si e completato con successo.
  bool get isSuccess => stagingArtifact != null;

  /// Indica se il download e fallito per un errore non di cancellazione.
  bool get isFailure =>
      failureReason != null && failureReason != DownloadFailureReason.cancelled;

  /// Indica se il download e stato annullato cooperativamente.
  bool get isCancelled => failureReason == DownloadFailureReason.cancelled;
}
