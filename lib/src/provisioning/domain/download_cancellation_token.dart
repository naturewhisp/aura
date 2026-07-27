import 'dart:async';

/// Token cooperativo per richiedere l'interruzione ordinata di un download in corso.
final class DownloadCancellationToken {
  final Completer<void> _completer = Completer<void>();
  bool _isCancelled = false;
  String? _cancelReason;

  /// Invia il segnale di cancellazione.
  void cancel([String? reason]) {
    if (_isCancelled) return;
    _isCancelled = true;
    _cancelReason = reason ?? 'Download annullato dall\'utente.';
    if (!_completer.isCompleted) {
      _completer.complete();
    }
  }

  /// Indica se e stato richiesto l'annullamento.
  bool get isCancelled => _isCancelled;

  /// Restituisce la motivazione dell'annullamento se disponibile.
  String? get cancelReason => _cancelReason;

  /// Future che si completa immediatamente quando viene chiamato [cancel].
  Future<void> get whenCancelled => _completer.future;
}
