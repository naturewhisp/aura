library aura_core;

// Models & Core Controller
export 'src/models/game_state.dart';
export 'src/models/evaluator_delta.dart';
export 'src/models/evaluator_resolution.dart';
export 'src/models/actor_cue.dart';
export 'src/models/turn_input.dart';
export 'src/game_controller.dart';
export 'src/replay_logger.dart';

// Agent Runtime Base
export 'src/agent_runtime/agent_card.dart';
export 'src/agent_runtime/message_envelope.dart';
export 'src/agent_runtime/agent_registry.dart';
export 'src/agent_runtime/inference_bridge.dart';
export 'src/agent_runtime/prompt_builder.dart';
export 'src/agent_runtime/output_validator.dart';
export 'src/agent_runtime/model_catalog.dart';
export 'src/agent_runtime/model_router.dart';

// Concrete Agents
export 'src/agent_runtime/agents/aura_agent.dart';
export 'src/agent_runtime/agents/evaluator_agent.dart';
export 'src/agent_runtime/agents/actor_agent.dart';

// Inference Bridges
export 'src/agent_runtime/bridges/mock_inference_bridge.dart';
export 'src/agent_runtime/bridges/rule_based_evaluator_bridge.dart';
export 'src/agent_runtime/bridges/local_api_inference_bridge.dart';
