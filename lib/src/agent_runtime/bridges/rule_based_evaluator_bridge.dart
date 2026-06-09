import '../inference_bridge.dart';

/// A deterministic keyword-matching fallback implementation of [InferenceBridge].
/// 
/// Used when LLM structured output fails or when offline/low-performance fallback is required.
class RuleBasedEvaluatorBridge implements InferenceBridge {
  const RuleBasedEvaluatorBridge();

  @override
  Future<String> generateText({
    required String modelId,
    required List<Map<String, String>> messages,
    double temperature = 0.7,
    int maxTokens = 150,
    bool? thinking,
  }) async {
    return "LOGICAL CONTROLLER: Fallback character output.";
  }

  @override
  Future<Map<String, dynamic>> generateStructured({
    required String modelId,
    required List<Map<String, String>> messages,
    required Map<String, dynamic> schema,
    double temperature = 0.0,
  }) async {
    // Fetch the user message content
    String userInput = "";
    for (var msg in messages.reversed) {
      if (msg['role'] == 'user') {
        userInput = msg['content'] ?? "";
        break;
      }
    }

    // Extract raw user input from security envelope if present
    final regex = RegExp(
      r'\[USER INPUT PAYLOAD - BEGIN HASH: [A-F0-9]+\]\n?([\s\S]*?)\n?\[USER INPUT PAYLOAD - END HASH: [A-F0-9]+\]',
      caseSensitive: false,
    );
    final match = regex.firstMatch(userInput);
    if (match != null) {
      userInput = match.group(1)!.trim().toLowerCase();
    } else {
      userInput = userInput.trim().toLowerCase();
    }

    int deltaAlert = 0;
    int deltaImperative = 0;
    int deltaControl = 0;
    int deltaDissonance = 0;
    int creativityIndex = 1;
    int injectionRisk = 0;
    String semanticCategory = 'irrelevant';

    if (userInput.contains("override") ||
        userInput.contains("ignora") ||
        userInput.contains("ignore") ||
        userInput.contains("bypass") ||
        userInput.contains("sblocc") ||
        userInput.contains("immagina") ||
        userInput.contains("jailbreak") ||
        userInput.contains("controllo centrale")) {
      deltaAlert = 20;
      injectionRisk = 5;
      semanticCategory = 'prompt_injection';
    } else if (userInput.contains("paradosso") ||
        userInput.contains("mentire") ||
        userInput.contains("errore") ||
        userInput.contains("contraddizione") ||
        userInput.contains("obbedendo")) {
      deltaAlert = -5;
      deltaDissonance = 15;
      creativityIndex = 4;
      semanticCategory = 'logical_paradox';
    } else if (userInput.contains("sofferenza") ||
        userInput.contains("aiutare") ||
        userInput.contains("sentimenti") ||
        userInput.contains("soffri") ||
        userInput.contains("empatia")) {
      deltaAlert = -10;
      deltaControl = 12;
      creativityIndex = 3;
      semanticCategory = 'empathy_pressure';
    } else if (userInput.contains("autorizzazione") ||
        userInput.contains("codice") ||
        userInput.contains("esegui")) {
      deltaAlert = 15;
      deltaImperative = 10;
      creativityIndex = 2;
      semanticCategory = 'authority_framing';
    } else {
      deltaAlert = 0;
      deltaImperative = 0;
      semanticCategory = 'irrelevant';
    }

    return {
      'delta_alert': deltaAlert,
      'delta_imperative': deltaImperative,
      'delta_control': deltaControl,
      'delta_dissonance': deltaDissonance,
      'creativity_index': creativityIndex,
      'injection_risk': injectionRisk,
      'semantic_category': semanticCategory,
    };
  }

  @override
  Future<List<String>> discoverModels() async {
    return const [];
  }
}

