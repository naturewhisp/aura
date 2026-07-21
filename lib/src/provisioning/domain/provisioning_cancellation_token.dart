import 'provisioning_options.dart';

/// Contratto astratto per l'annullamento coordinato delle operazioni asincrone di provisioning.
abstract interface class ProvisioningCancellationToken {
  /// Restituisce true se l'annullamento è stato richiesto.
  bool get isCancellationRequested;

  /// Lancia un [ProvisioningException] con ragione [ProvisioningFailureReason.operationCancelled]
  /// se l'annullamento è stato richiesto.
  void throwIfCancelled();
}

/// Implementazione concreta controllabile di [ProvisioningCancellationToken].
final class DefaultProvisioningCancellationToken
    implements ProvisioningCancellationToken {
  bool _isCancelled = false;

  @override
  bool get isCancellationRequested => _isCancelled;

  /// Richiede l'annullamento dell'operazione.
  void cancel() {
    _isCancelled = true;
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
