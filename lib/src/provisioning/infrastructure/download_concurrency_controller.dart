/// Governa la concorrenza dei download e garantisce l'isolamento ed il lock esclusivo per destinazione.
final class DownloadConcurrencyController {
  final int maxConcurrentDownloads;
  final Set<String> _activeOperations = <String>{};
  int _activeCount = 0;

  DownloadConcurrencyController({this.maxConcurrentDownloads = 1}) {
    assert(maxConcurrentDownloads > 0,
        'maxConcurrentDownloads deve essere maggiore di 0.');
  }

  /// Tenta di acquisire il lock esclusivo per un'operazione di download [operationId].
  ///
  /// Restituisce `true` se il lock e stato acquisito con successo.
  /// Restituisce `false` se un download per la stessa operazione e gia in corso o se il limite di concorrenza e raggiunto.
  bool tryAcquireLock(String operationId) {
    if (_activeOperations.contains(operationId)) {
      return false;
    }
    if (_activeCount >= maxConcurrentDownloads) {
      return false;
    }
    _activeOperations.add(operationId);
    _activeCount++;
    return true;
  }

  /// Rilascia il lock esclusivo per l'operazione [operationId].
  void releaseLock(String operationId) {
    if (_activeOperations.remove(operationId)) {
      _activeCount = (_activeCount - 1).clamp(0, maxConcurrentDownloads);
    }
  }

  /// Restituisce `true` se l'operazione [operationId] e attualmente attiva.
  bool isOperationActive(String operationId) =>
      _activeOperations.contains(operationId);
}
