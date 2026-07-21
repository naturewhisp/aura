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
