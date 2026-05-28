import '../prompt_builder.dart';
import '../inference_bridge.dart';
import '../output_validator.dart';
import '../agent_card.dart';

/// The execution context passed to an agent when running an inference task.
class AgentRuntimeContext {
  final PromptBuilder promptBuilder;
  final InferenceBridge inferenceBridge;
  final OutputValidator outputValidator;
  final String modelId;

  const AgentRuntimeContext({
    required this.promptBuilder,
    required this.inferenceBridge,
    required this.outputValidator,
    required this.modelId,
  });
}

/// Abstract contract that all agents in A.U.R.A. must implement.
abstract class AuraAgent<I, O> {
  String get id;
  AgentCard get card;

  /// Executes the agent logic with the given input and context.
  Future<O> run(I input, AgentRuntimeContext context);
}
