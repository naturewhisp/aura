/// Modalità di runtime selezionabili per l'applicazione A.U.R.A.
enum ApplicationRuntimeMode {
  /// Percorso legacy basato su LocalApiInferenceBridge (default LM Studio su porta 1234).
  legacyExternalOpenAi,

  /// Nuovo percorso di inferenza basato su ExternalOpenAiRuntime e RuntimeInferenceBridge.
  externalOpenAiRuntime,

  /// Percorso offline deterministico basato su regole locali senza chiamate di rete.
  ruleBased,
}
