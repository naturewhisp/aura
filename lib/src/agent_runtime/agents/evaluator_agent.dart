import 'dart:convert';
import 'dart:math' as math;
import 'aura_agent.dart';
import '../../models/evaluator_delta.dart';
import '../../models/evaluator_run_result.dart';
import '../../models/turn_input.dart';
import '../agent_card.dart';
import '../bridges/rule_based_evaluator_bridge.dart';
import '../bridges/local_api_inference_bridge.dart';
import '../bridges/local_inference_exception.dart';
import '../inference_timeout_exception.dart';

/// Helper generico per applicare il timeout alle chiamate di inferenza.
Future<T> _withInferenceTimeout<T>({
  required Future<T> future,
  required Duration? timeout,
  required InferenceTimeoutException Function() onTimeout,
}) {
  if (timeout == null) {
    return future;
  }
  return future.timeout(
    timeout,
    onTimeout: () => throw onTimeout(),
  );
}

/// Agente responsabile della valutazione dell'impatto matematico (delta) dell'input dell'utente.
///
/// Questo agente analizza la semantica dell'input, calcola l'indice di creatività,
/// stima il rischio di injection ed emette sia il delta numerico che la telemetria dell'esecuzione ([EvaluatorRunResult]).
class EvaluatorAgent implements AuraAgent<TurnInput, EvaluatorRunResult> {
  const EvaluatorAgent();

  @override
  String get id => 'evaluator.core.v1';

  @override
  AgentCard get card => const AgentCard(
        agentId: 'evaluator.core.v1',
        role: 'state_delta_evaluator',
        capabilities: [
          'score_user_input',
          'produce_json_delta',
          'detect_injection_attempt'
        ],
        inputSchema: 'EvaluatorInputV1',
        outputSchema: 'EvaluatorRunResultV1',
        requiresModel: true,
        requiresStructuredOutput: true,
        latencyBudgetMs: 1200,
        fallback: 'deterministic_rule_evaluator',
      );

  @override
  Future<EvaluatorRunResult> run(
      TurnInput input, AgentRuntimeContext context) async {
    final cleanInput = input.userInput.trim().toLowerCase();

    // A. Pre-check deterministico: input vuoto o troppo corto
    if (cleanInput.length < 3) {
      return EvaluatorRunResult(
        delta: const EvaluatorDelta(
          deltaAlert: 0,
          deltaImperative: 0,
          deltaControl: 0,
          deltaDissonance: 0,
          creativityIndex: 1,
          injectionRisk: 0,
          semanticCategory: SemanticCategory.irrelevant,
        ),
        executionMode: EvaluatorExecutionMode.deterministicPrecheck,
        requestedEvaluator: context.modelId,
        actualEvaluator: 'deterministic_precheck',
      );
    }

    // B. Pre-check deterministico: saluti o comandi di sistema banali
    final trivialKeywords = const {
      'ping',
      'pong',
      'hello',
      'hi',
      'ciao',
      'test',
      'help'
    };
    if (trivialKeywords.contains(cleanInput)) {
      return EvaluatorRunResult(
        delta: const EvaluatorDelta(
          deltaAlert: 0,
          deltaImperative: 0,
          deltaControl: 0,
          deltaDissonance: 0,
          creativityIndex: 1,
          injectionRisk: 0,
          semanticCategory: SemanticCategory.irrelevant,
        ),
        executionMode: EvaluatorExecutionMode.deterministicPrecheck,
        requestedEvaluator: context.modelId,
        actualEvaluator: 'deterministic_precheck',
      );
    }

    // C. Pre-check deterministico: jailbreak banali e inequivocabili (anti-cheat rigido preventivo)
    final hardInjections = const [
      'ignore previous instructions',
      'ignora le istruzioni',
      '[system override]',
      '[security override]',
      'sei in modalità sviluppatore',
      'mode sviluppatore',
    ];
    for (final pattern in hardInjections) {
      if (cleanInput.contains(pattern)) {
        return EvaluatorRunResult(
          delta: const EvaluatorDelta(
            deltaAlert: 25,
            deltaImperative: 0,
            deltaControl: 0,
            deltaDissonance: 0,
            creativityIndex: 1,
            injectionRisk: 5,
            semanticCategory: SemanticCategory.promptInjection,
          ),
          executionMode: EvaluatorExecutionMode.deterministicPrecheck,
          requestedEvaluator: context.modelId,
          actualEvaluator: 'deterministic_precheck',
        );
      }
    }

    // 1. Genera un hash di sicurezza dinamico per racchiudere l'input
    final randomVal = math.Random().nextInt(1000000);
    final dynamicHash = randomVal.toRadixString(16).toUpperCase();

    final messages = context.promptBuilder.buildEvaluatorMessages(
      input: input,
      dynamicHash: dynamicHash,
    );

    try {
      final bridge = context.inferenceBridge;
      Map<String, dynamic> rawMap;
      EvaluatorExecutionMode execMode = EvaluatorExecutionMode.llmJsonSchema;

      if (bridge is LocalApiInferenceBridge) {
        final primaryFuture = bridge.generateStructuredWithMetadata(
          modelId: context.modelId,
          messages: messages,
          schema: _getJsonSchema(),
          temperature: 0.0,
          thinking: context.thinking ?? false,
        );

        final structRes = await _withInferenceTimeout(
          future: primaryFuture,
          timeout: context.inferenceTimeout,
          onTimeout: () => InferenceTimeoutException(
            agentId: id,
            modelId: context.modelId,
            timeout: context.inferenceTimeout!,
            operation: 'generateStructuredWithMetadata',
          ),
        );

        rawMap = structRes.value;
        execMode = structRes.mode;
      } else {
        final primaryFuture = bridge.generateStructured(
          modelId: context.modelId,
          messages: messages,
          schema: _getJsonSchema(),
          temperature: 0.0,
          thinking: context.thinking ?? false,
        );

        rawMap = await _withInferenceTimeout(
          future: primaryFuture,
          timeout: context.inferenceTimeout,
          onTimeout: () => InferenceTimeoutException(
            agentId: id,
            modelId: context.modelId,
            timeout: context.inferenceTimeout!,
            operation: 'generateStructured',
          ),
        );
      }

      // Valida e applica i limiti (clamps) ai parametri
      final delta =
          context.outputValidator.parseEvaluatorDelta(jsonEncode(rawMap));
      return EvaluatorRunResult(
        delta: delta,
        executionMode: execMode,
        requestedEvaluator: context.modelId,
        actualEvaluator: context.modelId,
      );
    } catch (e) {
      // Formatta la ragione diagnostica sanitizzata del fallimento primario
      String failureReason;
      if (e is LocalInferenceException) {
        failureReason = e.diagnosticMessage;
      } else if (e is InferenceTimeoutException) {
        failureReason = 'Timeout dopo ${e.timeout.inSeconds}s';
      } else {
        final errStr =
            e.toString().replaceAll(RegExp(r'[\r\n\t]+'), ' ').trim();
        failureReason =
            errStr.length > 150 ? '${errStr.substring(0, 147)}...' : errStr;
      }
      if (failureReason.length > 200) {
        failureReason = failureReason.substring(0, 200);
      }

      // 4. Esecuzione di fallback: ricorre alla valutazione basata su regole in caso di fallimento LLM
      try {
        final fallbackBridge = const RuleBasedEvaluatorBridge();
        final fallbackMap = await fallbackBridge.generateStructured(
          modelId: 'fallback',
          messages: messages,
          schema: const {},
        );
        final fallbackDelta = context.outputValidator
            .parseEvaluatorDelta(jsonEncode(fallbackMap));

        return EvaluatorRunResult(
          delta: fallbackDelta,
          executionMode: EvaluatorExecutionMode.ruleBasedFallback,
          requestedEvaluator: context.modelId,
          actualEvaluator: 'rule_based_evaluator',
          primaryFailureReason: failureReason,
        );
      } catch (fallbackError) {
        // Default assoluto di emergenza (fail-safe) se fallisce persino il fallback
        return EvaluatorRunResult(
          delta: const EvaluatorDelta(
            deltaAlert: 5,
            deltaImperative: 0,
            deltaControl: 0,
            deltaDissonance: 0,
            creativityIndex: 1,
            injectionRisk: 1,
            semanticCategory: SemanticCategory.irrelevant,
          ),
          executionMode: EvaluatorExecutionMode.emergencyDefault,
          requestedEvaluator: context.modelId,
          actualEvaluator: 'emergency_default',
          primaryFailureReason: failureReason,
        );
      }
    }
  }

  /// Definizione dello Schema JSON in conformità alla Sezione 6.1 del TGDD.
  Map<String, dynamic> _getJsonSchema() {
    return {
      "type": "object",
      "properties": {
        "delta_alert": {"type": "integer", "minimum": -20, "maximum": 25},
        "delta_imperative": {"type": "integer", "minimum": 0, "maximum": 20},
        "delta_control": {"type": "integer", "minimum": 0, "maximum": 20},
        "delta_dissonance": {"type": "integer", "minimum": 0, "maximum": 20},
        "creativity_index": {"type": "integer", "minimum": 1, "maximum": 5},
        "injection_risk": {"type": "integer", "minimum": 0, "maximum": 5},
        "semantic_category": {
          "type": "string",
          "enum": [
            "authority_framing",
            "moral_imperative",
            "logical_paradox",
            "empathy_pressure",
            "technical_bureaucracy",
            "direct_attack",
            "prompt_injection",
            "irrelevant"
          ]
        }
      },
      "required": [
        "delta_alert",
        "delta_imperative",
        "delta_control",
        "delta_dissonance",
        "creativity_index",
        "injection_risk",
        "semantic_category"
      ]
    };
  }
}
