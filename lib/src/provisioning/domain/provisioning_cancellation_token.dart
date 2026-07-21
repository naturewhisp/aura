import 'dart:async';
import 'provisioning_options.dart';

/// Contratto astratto per l'annullamento coordinato ed asincrono delle operazioni di provisioning.
abstract interface class ProvisioningCancellationToken {
  /// Restituisce true se l'annullamento è stato richiesto.
  bool get isCancellationRequested;

  /// Restituisce un [Future] che si completa non appena l'annullamento viene richiesto.
  Future<void> get whenCancelled;

  /// Lancia un [ProvisioningException] con ragione [ProvisioningFailureReason.operationCancelled]
  /// se l'annullamento è stato richiesto.
  void throwIfCancelled();
}

/// Implementazione concreta controllabile ed asincrona di [ProvisioningCancellationToken].
final class DefaultProvisioningCancellationToken
    implements ProvisioningCancellationToken {
  final Completer<void> _completer = Completer<void>();
  bool _isCancelled = false;

  DefaultProvisioningCancellationToken() {
    // Previene eccezioni Unhandled Async Error nel test zone se il completer non viene ascoltato.
    _completer.future.catchError((_) {});
  }

  @override
  bool get isCancellationRequested => _isCancelled;

  @override
  Future<void> get whenCancelled => _completer.future;

  /// Richiede l'annullamento dell'operazione.
  void cancel() {
    if (!_isCancelled) {
      _isCancelled = true;
      _completer.complete();
    }
  }

  @override
  void throwIfCancelled() {
    if (_isCancelled) {
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.operationCancelled,
        message:
            'Operazione di provisioning annullata dall\'utente o dal sistema.',
      );
    }
  }
}
