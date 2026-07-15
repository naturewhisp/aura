/// Configurazione immutabile dei timeout per l'inferenza degli agenti.
final class InferenceTimeouts {
  /// Timeout massimo per l'agente valutatore ([EvaluatorAgent]).
  final Duration evaluator;

  /// Timeout massimo per l'agente attore ([ActorAgent]).
  final Duration actor;

  /// Costruisce una configurazione di timeout per gli agenti valutatore ed attore.
  const InferenceTimeouts({
    required this.evaluator,
    required this.actor,
  });

  /// Timeout predefiniti consigliati: 60 secondi per il valutatore, 180 secondi per l'attore.
  static const InferenceTimeouts defaults = InferenceTimeouts(
    evaluator: Duration(seconds: 60),
    actor: Duration(seconds: 180),
  );
}
