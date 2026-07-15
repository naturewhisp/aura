/// Eccezione sollevata quando una chiamata LLM di inferenza primaria scade oltre il limite configurato.
final class InferenceTimeoutException implements Exception {
  /// L'identificatore dell'agente che ha subito il timeout.
  final String agentId;

  /// L'identificatore del modello che era in esecuzione.
  final String modelId;

  /// La durata impostata come limite massimo prima della scadenza.
  final Duration timeout;

  /// L'operazione del bridge che ha subito il timeout (es. 'generateStructured' o 'generateText').
  final String operation;

  const InferenceTimeoutException({
    required this.agentId,
    required this.modelId,
    required this.timeout,
    required this.operation,
  });

  @override
  String toString() {
    return 'InferenceTimeoutException: L\'agente $agentId ha superato il timeout di ${timeout.inSeconds} secondi durante $operation (Modello: $modelId).';
  }
}
