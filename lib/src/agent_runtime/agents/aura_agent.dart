import '../prompt_builder.dart';
import '../inference_bridge.dart';
import '../output_validator.dart';
import '../agent_card.dart';

/// Il contesto di esecuzione passato a un agente durante l'esecuzione di un task di inferenza.
class AgentRuntimeContext {
  /// Il generatore di prompt utilizzato per assemblare i messaggi di sistema e utente.
  final PromptBuilder promptBuilder;

  /// Il bridge di inferenza per comunicare con il modello di linguaggio (LLM).
  final InferenceBridge inferenceBridge;

  /// Il validatore dell'output per garantire che la risposta sia conforme allo schema atteso.
  final OutputValidator outputValidator;

  /// L'identificatore del modello da utilizzare per l'inferenza.
  final String modelId;

  /// Flag opzionale per abilitare/disabilitare esplicitamente il ragionamento nativo (thinking).
  final bool? thinking;

  /// Flag per richiedere una Chain of Thought (CoT) concisa e limitata nel prompt.
  final bool conciseReasoning;

  /// Timeout massimo opzionale per l'esecuzione dell'inferenza primaria dell'agente.
  final Duration? inferenceTimeout;

  const AgentRuntimeContext({
    required this.promptBuilder,
    required this.inferenceBridge,
    required this.outputValidator,
    required this.modelId,
    this.thinking,
    this.conciseReasoning = false,
    this.inferenceTimeout,
  });
}

/// Contratto astratto che tutti gli agenti in A.U.R.A. devono implementare.
///
/// Rappresenta l'interfaccia comune per gli agenti sia analitici che narrativi.
abstract class AuraAgent<I, O> {
  /// L'identificatore univoco dell'agente.
  String get id;

  /// La scheda descrittiva dell'agente (scheda tecnica).
  AgentCard get card;

  /// Esegue la logica dell'agente con l'input e il contesto di runtime forniti.
  /// Ritorna un [Future] contenente l'output tipizzato [O].
  Future<O> run(I input, AgentRuntimeContext context);
}
