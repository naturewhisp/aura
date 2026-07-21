/// Codici di errore tipizzati per la gestione del ciclo di vita del runtime `llama-server`.
enum ManagedLlamaServerFailureCode {
  executableMissing,
  executableNotFile,
  modelMissing,
  modelNotFile,
  invalidPort,
  invalidConfiguration,
  unsupportedHost,
  processLaunchFailed,
  processExitedEarly,
  startupTimeout,
  healthCheckFailed,
  shutdownTimeout,
  forcedTerminationFailed,
  unexpectedProcessState,
}

/// Eccezione tipizzata sollevata durante la gestione del ciclo di vita di `llama-server`.
class ManagedLlamaServerException implements Exception {
  final ManagedLlamaServerFailureCode code;
  final String message;
  final Object? cause;

  const ManagedLlamaServerException({
    required this.code,
    required this.message,
    this.cause,
  });

  @override
  String toString() => 'ManagedLlamaServerException: $message (code: $code)';
}
