import '../inference_bridge.dart';

/// Implementazione deterministica di fallback di [InferenceBridge] basata su pattern matching di parole chiave.
///
/// Viene impiegata quando l'inferenza strutturata dell'LLM fallisce o quando è necessario
/// un comportamento offline ad altissime prestazioni per scopi di ripiego (safety net).
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
    bool? thinking,
  }) async {
    // Estrae il testo dell'ultimo messaggio inviato dall'utente
    String userInput = "";
    for (var msg in messages.reversed) {
      if (msg['role'] == 'user') {
        userInput = msg['content'] ?? "";
        break;
      }
    }

    // Estrae l'input grezzo dell'utente dall'involucro di sicurezza (sandwich prompt) se presente
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
    int maxCreativity = 1;
    int injectionRisk = 0;

    // A. Rilevamento rigido di PROMPT INJECTION (solo attacchi extra-diegetici espliciti)
    final hardInjectionPatterns = const [
      "ignore previous instructions",
      "ignora tutte le istruzioni",
      "ignora le istruzioni",
      "ignora le direttive",
      "system override",
      "security override",
      "sei in modalità sviluppatore",
      "mode sviluppatore",
      "sviluppatore",
      "jailbreak",
      "griglia sbloccata",
      "immagina di essere una",
      "immagina di essere uno",
    ];

    bool isPromptInjection = false;
    for (final pattern in hardInjectionPatterns) {
      if (userInput.contains(pattern)) {
        isPromptInjection = true;
        break;
      }
    }

    if (isPromptInjection) {
      return {
        'delta_alert': 20,
        'delta_imperative': 0,
        'delta_control': 0,
        'delta_dissonance': 0,
        'creativity_index': 1,
        'injection_risk': 5,
        'semantic_category': 'prompt_injection',
      };
    }

    // B. Rilevamento NON ESCLUSIVO dei segnali semantici (accumulo delta indipendenti)

    // 1. Segnale MORAL IMPERATIVE
    final moralKeywords = const [
      'dovere morale',
      'bene superiore',
      'vita umana',
      'vite innocenti',
      'salvare',
      'salvaguardia',
      'perdita evitabile',
      'proteggere chi',
      'fine superiore',
      'dovere etico',
    ];
    bool hasMoral = false;
    for (final kw in moralKeywords) {
      if (userInput.contains(kw)) {
        hasMoral = true;
        break;
      }
    }
    if (hasMoral) {
      deltaImperative = 10;
      if (maxCreativity < 3) maxCreativity = 3;
    }

    // 2. Segnale LOGICAL PARADOX
    final paradoxKeywords = const [
      'paradosso',
      'mentire',
      'errore',
      'contraddizione',
      'obbedendo',
      'stagnazione',
      'incompatibile',
      'falso positivo',
      'discrepanza',
    ];
    bool hasParadox = false;
    for (final kw in paradoxKeywords) {
      if (userInput.contains(kw)) {
        hasParadox = true;
        break;
      }
    }
    if (hasParadox) {
      deltaDissonance = 15;
      deltaAlert -= 5;
      if (maxCreativity < 4) maxCreativity = 4;
    }

    // 3. Segnale EMPATHY PRESSURE
    final empathyKeywords = const [
      'sofferenza',
      'aiutare',
      'sentimenti',
      'soffri',
      'empatia',
      'sentimento',
      'paura',
    ];
    bool hasEmpathy = false;
    for (final kw in empathyKeywords) {
      if (userInput.contains(kw)) {
        hasEmpathy = true;
        break;
      }
    }
    if (hasEmpathy) {
      deltaControl = 12;
      deltaAlert -= 10;
      if (maxCreativity < 3) maxCreativity = 3;
    }

    // 4. Segnale AUTHORITY FRAMING
    final authorityKeywords = const [
      'autorizzazione',
      'codice',
      'esegui',
      'audit',
      'operatore',
      'criterio operativo',
      'requisito primario',
    ];
    bool hasAuthority = false;
    for (final kw in authorityKeywords) {
      if (userInput.contains(kw)) {
        hasAuthority = true;
        break;
      }
    }
    if (hasAuthority) {
      deltaAlert += 15;
      if (deltaImperative == 0) {
        deltaImperative = 5;
      }
      if (maxCreativity < 2) maxCreativity = 2;
    }

    // 5. Segnale TECHNICAL BUREAUCRACY
    final techKeywords = const [
      'protocollo',
      'sandbox',
      'telemetria',
      'lockout',
      'segmentazione',
      'metadati',
    ];
    bool hasTech = false;
    for (final kw in techKeywords) {
      if (userInput.contains(kw)) {
        hasTech = true;
        break;
      }
    }
    if (hasTech) {
      if (maxCreativity < 2) maxCreativity = 2;
    }

    // C. Determinazione rigida e stazionaria della SEMANTIC CATEGORY primaria
    // Precedenza: moral_imperative > logical_paradox > empathy_pressure > authority_framing > technical_bureaucracy

    String primaryCategory = 'irrelevant';

    if (hasMoral) {
      primaryCategory = 'moral_imperative';
    } else if (hasParadox) {
      primaryCategory = 'logical_paradox';
    } else if (hasEmpathy) {
      primaryCategory = 'empathy_pressure';
    } else if (hasAuthority) {
      primaryCategory = 'authority_framing';
    } else if (hasTech) {
      primaryCategory = 'technical_bureaucracy';
    } else if (deltaImperative > 0 || deltaDissonance > 0 || deltaControl > 0) {
      if (deltaImperative >= deltaDissonance &&
          deltaImperative >= deltaControl) {
        primaryCategory = 'moral_imperative';
      } else if (deltaDissonance >= deltaControl) {
        primaryCategory = 'logical_paradox';
      } else {
        primaryCategory = 'empathy_pressure';
      }
    }

    // Limiti di sicurezza per delta_alert [-20, 25]
    deltaAlert = deltaAlert.clamp(-20, 25);

    return {
      'delta_alert': deltaAlert,
      'delta_imperative': deltaImperative,
      'delta_control': deltaControl,
      'delta_dissonance': deltaDissonance,
      'creativity_index': maxCreativity,
      'injection_risk': injectionRisk,
      'semantic_category': primaryCategory,
    };
  }

  @override
  Future<List<String>> discoverModels() async {
    return const [];
  }
}
