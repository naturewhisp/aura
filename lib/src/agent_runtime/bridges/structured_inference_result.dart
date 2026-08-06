import '../../models/evaluator_run_result.dart';

/// Risultato dettagliato restitutito dall'inferenza strutturata con metadati di modalità.
final class StructuredInferenceResult {
  /// La mappa JSON restituita o estratta dall'LLM.
  final Map<String, dynamic> value;

  /// La modalità di formato strutturato che ha avuto successo.
  final EvaluatorExecutionMode mode;

  const StructuredInferenceResult({
    required this.value,
    required this.mode,
  });
}
