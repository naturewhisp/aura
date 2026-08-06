import '../../models/evaluator_run_result.dart';
import '../inference_bridge.dart';
import 'structured_inference_result.dart';

/// Errore lanciato quando un [modelId] non corrisponde né al modello Actor
/// né a quello Evaluator configurati nel [DualModelInferenceBridge].
class DualModelRoutingException implements Exception {
  final String requestedModelId;
  final String actorModelId;
  final String evaluatorModelId;
  final String operation;

  const DualModelRoutingException({
    required this.requestedModelId,
    required this.actorModelId,
    required this.evaluatorModelId,
    required this.operation,
  });

  @override
  String toString() =>
      'DualModelRoutingException: modelId "$requestedModelId" non corrisponde né ad Actor '
      '("$actorModelId") né ad Evaluator ("$evaluatorModelId") per l\'operazione "$operation". '
      'Nessun fallback automatico tra bridge.';
}

/// Bridge di inferenza dual-role che aggrega due [InferenceBridge] distinti:
/// uno per il ruolo Actor (generazione testo diegetico) e uno per il ruolo
/// Evaluator (generazione JSON strutturato).
///
/// Lo smistamento è basato sul [modelId] passato a ciascun metodo:
/// - [generateText] accetta esclusivamente [actorModelId];
/// - [generateStructured] accetta esclusivamente [evaluatorModelId];
/// - Un [modelId] non riconosciuto produce un [DualModelRoutingException] tipizzato;
/// - Non esiste alcun fallback automatico da un bridge all'altro.
///
/// [discoverModels] restituisce l'unione ordinata dei modelli di entrambi i bridge.
final class DualModelInferenceBridge
    implements InferenceBridge, StructuredInferenceMetadataBridge {
  /// Bridge HTTP del ruolo Actor.
  final InferenceBridge actorBridge;

  /// Bridge HTTP del ruolo Evaluator.
  final InferenceBridge evaluatorBridge;

  /// Identificatore logico del modello Actor.
  final String actorModelId;

  /// Identificatore logico del modello Evaluator.
  final String evaluatorModelId;

  const DualModelInferenceBridge({
    required this.actorBridge,
    required this.evaluatorBridge,
    required this.actorModelId,
    required this.evaluatorModelId,
  });

  bool _isActorModel(String requestedId) {
    if (requestedId == actorModelId) return true;
    if (actorModelId == 'aura.actor.primary' ||
        requestedId == 'aura.actor.primary') {
      return requestedId == 'aura.actor.primary' ||
          requestedId == 'gemma-4-12b-it-qat-q4-0' ||
          requestedId == 'google/gemma-4-12b' ||
          requestedId == 'qwen/qwen3.5-9b';
    }
    return false;
  }

  bool _isEvaluatorModel(String requestedId) {
    if (requestedId == evaluatorModelId) return true;
    if (evaluatorModelId == 'aura.evaluator.primary' ||
        requestedId == 'aura.evaluator.primary') {
      return requestedId == 'aura.evaluator.primary' ||
          requestedId == 'mistralai/ministral-3-3b';
    }
    return false;
  }

  @override
  Future<String> generateText({
    required String modelId,
    required List<Map<String, String>> messages,
    double temperature = 0.7,
    int maxTokens = 150,
    bool? thinking,
  }) {
    if (!_isActorModel(modelId)) {
      throw DualModelRoutingException(
        requestedModelId: modelId,
        actorModelId: actorModelId,
        evaluatorModelId: evaluatorModelId,
        operation: 'generateText',
      );
    }
    return actorBridge.generateText(
      modelId: modelId,
      messages: messages,
      temperature: temperature,
      maxTokens: maxTokens,
      thinking: thinking,
    );
  }

  @override
  Future<Map<String, dynamic>> generateStructured({
    required String modelId,
    required List<Map<String, String>> messages,
    required Map<String, dynamic> schema,
    double temperature = 0.0,
    bool? thinking,
  }) {
    if (!_isEvaluatorModel(modelId)) {
      throw DualModelRoutingException(
        requestedModelId: modelId,
        actorModelId: actorModelId,
        evaluatorModelId: evaluatorModelId,
        operation: 'generateStructured',
      );
    }
    return evaluatorBridge.generateStructured(
      modelId: modelId,
      messages: messages,
      schema: schema,
      temperature: temperature,
      thinking: thinking,
    );
  }

  @override
  Future<StructuredInferenceResult> generateStructuredWithMetadata({
    required String modelId,
    required List<Map<String, String>> messages,
    required Map<String, dynamic> schema,
    double temperature = 0.0,
    bool? thinking,
  }) {
    if (!_isEvaluatorModel(modelId)) {
      throw DualModelRoutingException(
        requestedModelId: modelId,
        actorModelId: actorModelId,
        evaluatorModelId: evaluatorModelId,
        operation: 'generateStructuredWithMetadata',
      );
    }
    final eBridge = evaluatorBridge;
    if (eBridge is StructuredInferenceMetadataBridge) {
      return (eBridge as StructuredInferenceMetadataBridge)
          .generateStructuredWithMetadata(
        modelId: modelId,
        messages: messages,
        schema: schema,
        temperature: temperature,
        thinking: thinking,
      );
    }
    return eBridge
        .generateStructured(
          modelId: modelId,
          messages: messages,
          schema: schema,
          temperature: temperature,
          thinking: thinking,
        )
        .then((val) => StructuredInferenceResult(
              value: val,
              mode: EvaluatorExecutionMode.llmJsonSchema,
              attempts: [
                EvaluatorAttemptTelemetry(
                  mode: EvaluatorExecutionMode.llmJsonSchema,
                  resultStatus: 'success',
                  durationMs: 0,
                ),
              ],
            ));
  }

  @override
  Future<List<String>> discoverModels() async {
    final actorModels = await actorBridge.discoverModels();
    final evaluatorModels = await evaluatorBridge.discoverModels();
    final seen = <String>{};
    return [
      ...actorModels.where(seen.add),
      ...evaluatorModels.where(seen.add),
    ];
  }
}
