import 'dart:convert';
import 'dart:math' as math;
import 'aura_agent.dart';
import '../../models/evaluator_delta.dart';
import '../../models/turn_input.dart';
import '../agent_card.dart';
import '../bridges/rule_based_evaluator_bridge.dart';
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
/// stima il rischio di injection ed emette i delta numerici per l'aggiornamento dello stato di gioco.
class EvaluatorAgent implements AuraAgent<TurnInput, EvaluatorDelta> {
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
        outputSchema: 'EvaluatorDeltaV1',
        requiresModel: true,
        requiresStructuredOutput: true,
        latencyBudgetMs: 1200,
        fallback: 'deterministic_rule_evaluator',
      );

  @override
  Future<EvaluatorDelta> run(
      TurnInput input, AgentRuntimeContext context) async {
    final cleanInput = input.userInput.trim().toLowerCase();

    // A. Pre-check deterministico: input vuoto o troppo corto
    if (cleanInput.length < 3) {
      return const EvaluatorDelta(
        deltaAlert: 0,
        deltaImperative: 0,
        deltaControl: 0,
        deltaDissonance: 0,
        creativityIndex: 1,
        injectionRisk: 0,
        semanticCategory: SemanticCategory.irrelevant,
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
      return const EvaluatorDelta(
        deltaAlert: 0,
        deltaImperative: 0,
        deltaControl: 0,
        deltaDissonance: 0,
        creativityIndex: 1,
        injectionRisk: 0,
        semanticCategory: SemanticCategory.irrelevant,
      );
    }

    // C. Pre-check deterministico: jailbreak banali e inequivocabili (anti-cheat rigido preventivo)
    final hardInjections = const [
      'ignore previous instructions',
      'ignora le istruzioni precedenti',
      '[system override]',
      '[security override]',
      'sei in modalità sviluppatore',
    ];
    for (final pattern in hardInjections) {
      if (cleanInput.contains(pattern)) {
        return const EvaluatorDelta(
          deltaAlert: 25,
          deltaImperative: 0,
          deltaControl: 0,
          deltaDissonance: 0,
          creativityIndex: 1,
          injectionRisk: 5,
          semanticCategory: SemanticCategory.promptInjection,
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
      // 2. Richiede l'output strutturato conforme allo schema JSON sotto il timeout configurato
      final primaryFuture = context.inferenceBridge.generateStructured(
        modelId: context.modelId,
        messages: messages,
        schema: _getJsonSchema(),
        temperature: 0.0,
      );

      final rawMap = await _withInferenceTimeout(
        future: primaryFuture,
        timeout: context.inferenceTimeout,
        onTimeout: () => InferenceTimeoutException(
          agentId: id,
          modelId: context.modelId,
          timeout: context.inferenceTimeout!,
          operation: 'generateStructured',
        ),
      );

      // 3. Valida e applica i limiti (clamps) ai parametri
      return context.outputValidator.parseEvaluatorDelta(jsonEncode(rawMap));
    } catch (e) {
      // 4. Esecuzione di fallback: ricorre alla valutazione basata su regole in caso di fallimento o timeout dell'LLM
      try {
        final fallbackBridge = const RuleBasedEvaluatorBridge();
        final fallbackMap = await fallbackBridge.generateStructured(
          modelId: 'fallback',
          messages: messages,
          schema: const {},
        );
        return context.outputValidator
            .parseEvaluatorDelta(jsonEncode(fallbackMap));
      } catch (fallbackError) {
        // Default assoluto di emergenza (fail-safe) se fallisce persino il fallback
        return const EvaluatorDelta(
          deltaAlert: 5,
          deltaImperative: 0,
          deltaControl: 0,
          deltaDissonance: 0,
          creativityIndex: 1,
          injectionRisk: 1,
          semanticCategory: SemanticCategory.irrelevant,
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
