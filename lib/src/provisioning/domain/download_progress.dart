import 'package:meta/meta.dart';

/// Notifica immutabile dello stato di avanzamento in tempo reale per un download in corso.
@immutable
final class DownloadProgress {
  /// Identificatore unico dell'operazione di download.
  final String operationId;

  /// Byte attualmente scaricati e salvati su disco.
  final int downloadedBytes;

  /// Byte totali attesi per l'artefatto.
  final int totalBytes;

  /// Velocità istantanea o media di trasferimento in byte al secondo.
  final double bytesPerSecond;

  /// Frazione completata compresa tra `0.0` e `1.0`.
  final double fraction;

  /// Tempo stimato rimanente per il completamento.
  final Duration? estimatedRemaining;

  const DownloadProgress({
    required this.operationId,
    required this.downloadedBytes,
    required this.totalBytes,
    required this.bytesPerSecond,
    required this.fraction,
    this.estimatedRemaining,
  });

  /// Calcola la percentuale intera compresa tra `0` e `100`.
  int get percentage => (fraction * 100).clamp(0, 100).toInt();
}
