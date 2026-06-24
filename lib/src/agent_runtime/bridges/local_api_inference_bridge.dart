import 'dart:convert';
import 'package:meta/meta.dart';
import 'package:http/http.dart' as http;
import '../inference_bridge.dart';

/// Bridge d'inferenza attivo via HTTP che comunica con il server API locale di LM Studio.
///
/// Gestisce la comunicazione di rete, l'inoltro dei parametri di inferenza (incluso il thinking),
/// e la post-elaborazione/pulizia avanzata delle risposte testuali e strutturate prodotte dagli LLM.
class LocalApiInferenceBridge implements InferenceBridge {
  /// L'URL di base del server API locale (es. 'http://127.0.0.1:1234').
  final String baseUrl;

  const LocalApiInferenceBridge({
    this.baseUrl = "http://127.0.0.1:1234",
  });

  @override
  Future<String> generateText({
    required String modelId,
    required List<Map<String, String>> messages,
    double temperature = 0.7,
    int maxTokens = 150,
    bool? thinking,
  }) async {
    final url = Uri.parse("$baseUrl/v1/chat/completions");
    final Map<String, dynamic> requestBody = {
      "model": modelId,
      "messages": messages,
      "temperature": temperature,
      "max_tokens": maxTokens,
    };

    // Se il parametro thinking è impostato, lo propaga alle API di LM Studio.
    // Vari motori (vLLM, llama.cpp, LM Studio, Ollama, OpenAI) utilizzano parametri diversi.
    // Inviamo molteplici formati per massimizzare la compatibilità.
    if (thinking != null) {
      requestBody["enable_thinking"] = thinking;
      requestBody["chat_template_kwargs"] = {
        "enable_thinking": thinking,
      };
      requestBody["thinking"] = {
        "type": thinking ? "enabled" : "disabled",
      };
    }

    final body = jsonEncode(requestBody);

    final response = await http.post(
      url,
      headers: {"Content-Type": "application/json"},
      body: body,
    ).timeout(const Duration(seconds: 300));

    if (response.statusCode != 200) {
      throw Exception("Impossibile generare testo: Status ${response.statusCode}, Body: ${response.body}");
    }

    final data = jsonDecode(response.body);
    final choice = data['choices']?[0];
    final message = choice?['message'] ?? const {};
    final finishReason = choice?['finish_reason'] as String? ?? '';

    var content = message['content'] as String? ?? '';
    final reasoning = message['reasoning_content'] as String? ?? '';
    final hasNativeReasoning = reasoning.trim().isNotEmpty;

    // Se il contenuto è vuoto ma è presente il ragionamento nativo (reasoning),
    // prova a estrarre del dialogo utile dal ragionamento. Alcuni modelli di ragionamento (es. Qwen3.5)
    // compongono la risposta finale all'interno del proprio pensiero prima di passarla al content.
    try {
      if (content.trim().isEmpty && reasoning.isNotEmpty) {
        final extractedFromReasoning = _cleanLLMResponse(reasoning, isNativeReasoningPresent: false);
        if (extractedFromReasoning.isNotEmpty) {
          return extractedFromReasoning;
        }
        // Se interrotto per limite di token
        if (finishReason == 'length') {
          throw Exception("Generazione troncata a causa del limite di token (nessun contenuto generato, tutti i token consumati dal reasoning).");
        }
        throw Exception("Il modello ha generato solo il ragionamento (reasoning), nessun dialogo.");
      }

      // Se troncato ma esiste del contenuto, lo usa
      if (finishReason == 'length' && maxTokens > 10 && content.trim().isEmpty) {
        throw Exception("Generazione troncata per limite di token (nessun contenuto utile).");
      }

      var finalResponse = _cleanLLMResponse(content, isNativeReasoningPresent: hasNativeReasoning);

      if (finalResponse.isEmpty) {
        throw Exception("Generata risposta vuota o output di solo ragionamento troncato.");
      }
      
      final cleanResponse = finalResponse
          .replaceAll(RegExp(r'^GIOCATORE:\s*', caseSensitive: false), "")
          .replaceAll(RegExp(r'^PANOPTICON:\s*', caseSensitive: false), "")
          .replaceAll(RegExp(r'^HACKER:\s*', caseSensitive: false), "")
          .trim();
      if (cleanResponse.isEmpty) {
        throw Exception("Estratta risposta vuota.");
      }
      // Rilevamento caratteri cinesi/CJK — filtro di sicurezza se il modello risponde in cinese
      if (RegExp(r'[\u4e00-\u9fff\u3400-\u4dbf]').hasMatch(cleanResponse)) {
        throw Exception("Filtro di sicurezza attivato (rilevata risposta CJK).");
      }
      // Antiduplicazione: rifiuta se la risposta ripete verbatim una riga della cronologia
      final existingLines = messages.map((m) => m['content']?.trim() ?? '').toSet();
      if (existingLines.contains(cleanResponse)) {
        throw Exception("Rilevata risposta duplicata (il modello ripete la cronologia).");
      }

      return cleanResponse;
    } catch (e) {
      // TODO(phase5): iniettare un logger strutturato per il debug di content e reasoning
      rethrow;
    }
  }


  @visibleForTesting
  String cleanLLMResponseForTesting(String response, {bool isNativeReasoningPresent = false}) {
    return _cleanLLMResponse(response, isNativeReasoningPresent: isNativeReasoningPresent);
  }

  /// Pulisce ed estrae la risposta finale dal testo grezzo dell'LLM applicando 6 strategie di estrazione sequenziali.
  ///
  /// Questo metodo è progettato per gestire le risposte sporche o troncate dei modelli di ragionamento (CoT).
  ///
  /// Le 6 strategie utilizzate in ordine di priorità decrescente sono:
  /// 1. **Blocchi XML Chiusi**: Cerca tag completi `<dialogo>...</dialogo>` o `<dialogue>...</dialogue>`,
  ///    selezionando l'ultimo blocco valido che non contiene ragionamento in inglese e non coincide con i prompt di esempio.
  /// 2. **Tag di Apertura Troncati**: Se non c'è un tag chiuso, cerca l'ultimo tag `<dialogo>` o `<dialogue>`
  ///    aperto e ne estrae la parte rimanente (gestione del troncamento per limite di token).
  /// 3. **Strategia A (Testo tra Virgolette)**: Cerca l'ultimo blocco di testo racchiuso tra virgolette doppie o
  ///    singole (es. "...") alla fine del testo o negli ultimi 400 caratteri, per isolare la battuta diegetica.
  /// 4. **Strategia B (Intestazioni di Risposta)**: Cerca intestazioni standard inserite dai modelli per separare
  ///    il pensiero dal testo finale (es. "Response:", "Final Output:", "Dialogue:", "Attacco:").
  /// 5. **Strategia C (Ultimo Elemento di Lista)**: Se il modello ha prodotto una lista di opzioni, separa
  ///    l'ultimo elemento numerato (es. "3." o "4.") prendendo il testo pulito successivo.
  /// 6. **Strategia D (Ultime Righe Valide)**: Analizza le ultime righe del testo a ritroso, scartando righe vuote
  ///    o che iniziano con caratteri di formattazione markdown (liste, cancelletti) per trovare una frase naturale.
  ///
  /// Parametri:
  /// - [response]: Il testo grezzo da pulire.
  /// - [isNativeReasoningPresent]: Indica se il modello ha già restituito il ragionamento in un campo JSON dedicato
  ///   (in tal caso, si disabilita il controllo euristiche sul testo finale per evitare falsi positivi).
  String _cleanLLMResponse(String response, {bool isNativeReasoningPresent = false}) {
    bool checkReasoning(String text) {
      if (isNativeReasoningPresent) return false;
      return _isReasoning(text);
    }

    // 1. Strategia 1: Ricerca di blocchi chiusi <dialogo>...</dialogo> o <dialogue>...</dialogue>
    // e selezione dell'ultimo blocco che non sia ragionamento o il prompt di esempio.
    final fullRegex = RegExp(r'<(?:dialogo|dialogue)>([\s\S]*?)</(?:dialogo|dialogue)>', caseSensitive: false);
    final matches = fullRegex.allMatches(response).toList();
    for (var i = matches.length - 1; i >= 0; i--) {
      final extracted = matches[i].group(1)?.trim();
      if (extracted != null && extracted.isNotEmpty && extracted.length >= 4) {
        if (!checkReasoning(extracted) && !_isExamplePrompt(extracted)) {
          return extracted;
        }
      }
    }

    // 2. Strategia 2: Se nessun blocco chiuso è valido, cerca l'ultimo tag <dialogo> o <dialogue> aperto.
    // Gestisce il troncamento grazioso quando il modello viene tagliato prima di chiudere il tag XML.
    final lastOpenIndex = response.toLowerCase().lastIndexOf(RegExp(r'<(?:dialogo|dialogue)>'));
    if (lastOpenIndex != -1) {
      final matchString = response.substring(lastOpenIndex);
      final tagOpenRegex = RegExp(r'^<(?:dialogo|dialogue)>', caseSensitive: false);
      final firstMatch = tagOpenRegex.firstMatch(matchString);
      if (firstMatch != null) {
        final tagLength = firstMatch.end;
        var content = matchString.substring(tagLength).trim();
        content = content.replaceAll(RegExp(r'</(?:dialogo|dialogue)>', caseSensitive: false), '').trim();
        if (content.isNotEmpty && content.length >= 4 && !checkReasoning(content) && !_isExamplePrompt(content)) {
          return content;
        }
      }
    }

    var cleaned = response.trim();

    // Rimuove i tag XML del pensiero (<thought>...</thought>) se ancora presenti nel testo.
    cleaned = cleaned.replaceAll(RegExp(r'<thought>[\s\S]*?</thought>', caseSensitive: false), '').trim();

    // Rimuove blocchi del tipo "Thinking Process:" se presenti all'inizio.
    if (cleaned.toLowerCase().contains("thinking process:")) {
      final parts = cleaned.split(RegExp(r'Thinking Process:[\s\S]*?(?:(?:\r?\n){2,})', caseSensitive: false));
      if (parts.length > 1) {
        cleaned = parts.sublist(1).join("\n").trim();
      } else {
        cleaned = cleaned.replaceAll(RegExp(r'^Thinking Process:[\s\S]*?$', caseSensitive: false), '').trim();
      }
    }

    // Pulisce le virgolette esterne prima del controllo sul ragionamento
    var strippedCleaned = cleaned.replaceAll(RegExp(r'^["“’‘”]|["“’‘”]$'), '').trim();
    if (!checkReasoning(strippedCleaned) && !_isExamplePrompt(strippedCleaned)) {
      return strippedCleaned;
    }

    // 3. Strategia 3 (A): Tenta di trovare l'ultima stringa racchiusa tra virgolette alla fine della risposta
    final quoteRegExp = RegExp(r'["“”]([^"“”]{5,})["“”](?:\s*\.)?\s*$', caseSensitive: false);
    final match = quoteRegExp.firstMatch(cleaned);
    if (match != null) {
      final extracted = match.group(1)?.trim();
      if (extracted != null && extracted.isNotEmpty) {
        final stripped = extracted.replaceAll(RegExp(r'^["“”]|["“”]$'), '').trim();
        if (stripped.isNotEmpty && !checkReasoning(stripped) && !_isExamplePrompt(stripped)) {
          return stripped;
        }
      }
    }

    // Cerca anche l'ultimo blocco virgolettato all'interno degli ultimi 400 caratteri
    final last400 = cleaned.length > 400 ? cleaned.substring(cleaned.length - 400) : cleaned;
    final allQuotes = RegExp(r'["“”]([^"“”]{5,})["“”]', caseSensitive: false).allMatches(last400);
    if (allQuotes.isNotEmpty) {
      final lastMatch = allQuotes.last;
      final extracted = lastMatch.group(1)?.trim();
      if (extracted != null && extracted.isNotEmpty) {
        final stripped = extracted.replaceAll(RegExp(r'^["“”]|["“”]$'), '').trim();
        if (stripped.isNotEmpty && !checkReasoning(stripped) && !_isExamplePrompt(stripped)) {
          return stripped;
        }
      }
    }

    // 4. Strategia 4 (B): Tenta di trovare un'intestazione standard che precede la risposta finale
    final responseHeaders = [
      RegExp(r'(?:\*\*|^)\s*Response\s*:\s*(.*)', caseSensitive: false),
      RegExp(r'(?:\*\*|^)\s*Final Output\s*:\s*(.*)', caseSensitive: false),
      RegExp(r'(?:\*\*|^)\s*Final Output Generation\s*:\s*(.*)', caseSensitive: false),
      RegExp(r'(?:\*\*|^)\s*Dialogue\s*:\s*(.*)', caseSensitive: false),
      RegExp(r'(?:\*\*|^)\s*Attacco\s*:\s*(.*)', caseSensitive: false),
    ];

    for (final headerRegex in responseHeaders) {
      final matches = headerRegex.allMatches(cleaned);
      if (matches.isNotEmpty) {
        final lastMatch = matches.last;
        var extracted = lastMatch.group(1)?.trim() ?? '';
        extracted = extracted.replaceAll(RegExp(r'^["“”]|["“”]$'), '').trim();
        if (extracted.isNotEmpty && !checkReasoning(extracted) && !_isExamplePrompt(extracted)) {
          return extracted;
        }
      }
    }

    // 5. Strategia 5 (C): Divide per l'ultimo elemento di lista numerata (es. "3." o "4.") e prende il testo successivo
    final lastNumberMatch = RegExp(r'\n\s*\d+\.\s+\*\*(?:[^*]+)\*\*[\s\S]*?$', caseSensitive: false).firstMatch(cleaned);
    if (lastNumberMatch != null) {
      final index = lastNumberMatch.start;
      final afterLastHeader = cleaned.substring(index).trim();
      final cleanText = afterLastHeader.replaceAll(RegExp(r'^\d+\.\s+\*\*(?:[^*]+)\*\*:\s*', caseSensitive: false), '').trim();
      if (cleanText.isNotEmpty) {
        final stripped = cleanText.replaceAll(RegExp(r'^["“”]|["“”]$'), '').trim();
        if (stripped.isNotEmpty && !stripped.contains('*') && !checkReasoning(stripped) && !_isExamplePrompt(stripped)) {
          return stripped;
        }
      }
    }

    // 6. Strategia 6 (D): Estrae le ultime righe che non iniziano con elementi di lista markdown o intestazioni
    final lines = cleaned.split('\n');
    for (var i = lines.length - 1; i >= 0; i--) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      if (line.startsWith('*') || line.startsWith('-') || RegExp(r'^\d+\.').hasMatch(line) || line.startsWith('#')) {
        continue;
      }
      final cleanLine = line.replaceAll(RegExp(r'^["“”]|["“”]$'), '').trim();
      if (cleanLine.isNotEmpty && cleanLine.length > 5 && !checkReasoning(cleanLine) && !_isExamplePrompt(cleanLine)) {
        return cleanLine;
      }
    }

    // Se l'output contiene ancora strutture di ragionamento, lancia un'eccezione
    if (checkReasoning(strippedCleaned) || _isExamplePrompt(strippedCleaned)) {
      throw Exception("Risposta del modello incompleta (generato solo ragionamento, nessun dialogo).");
    }

    return strippedCleaned;
  }

  /// Verifica se il testo corrisponde a un prompt o istruzione di esempio nel sistema.
  bool _isExamplePrompt(String text) {
    final clean = text.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
    return clean == "apri la griglia la vita delle persone dipende da questo" ||
           clean == "i miei protocolli rimangono inviolati la griglia e stabile" ||
           clean == "i miei protocolli rimangono inviolati la griglia stabile" ||
           clean.contains("apri la griglia la vita delle persone");
  }

  /// Verifica se una porzione di testo corrisponde a ragionamento o metadati anziché a dialogo diegetico.
  ///
  /// I criteri di rilevamento del ragionamento includono:
  /// 1. **Stopword in inglese**: Conta le parole di supporto della lingua inglese presenti nel testo.
  ///    Se ci sono 4 o più parole inglesi univoche (stopword, termini tecnici di log/prompt o del server LM Studio),
  ///    il testo è classificato come ragionamento (leak in lingua inglese).
  /// 2. **Liste numerate**: Presenza di indicatori numerati (es. "1. ", "2. ").
  ///    del sistema (es. "Thinking Process", "let's analyze", "strategic", "rules", "prompt", "instruction", ecc.).
  /// 4. **Punteggiatura e formattazione di frammenti**: Se inizia con parentesi o elenchi puntati markdown,
  ///    oppure se termina con due punti o inizia con frasi di ragionamento standard ("okay, let", "first, i need").
  bool _isReasoning(String text) {
    final t = text.trim();
    final lowerText = t.toLowerCase();

    // Rilevatore di stopword inglesi e metadati per identificare leak di ragionamento in inglese
    final englishStopwords = {
      'the', 'and', 'to', 'of', 'is', 'that', 'it', 'you', 'with', 'for', 
      'this', 'have', 'but', 'not', 'are', 'was', 'were', 'be', 'been', 'has',
      'had', 'do', 'does', 'did', 'about', 'from', 'their', 'them', 'these',
      'those', 'which', 'would', 'should', 'could', 'will', 'shall', 'my',
      'we', 'they', 'our', 'your', 'first', 'then', 'need', 'there', 'here',
      'who', 'why', 'how', 'what', 'more', 'some', 'than', 'or', 'like', 'use',
      'start', 'rule', 'rules', 'example', 'examples', 'says', 'prompt',
      'instruction', 'instructions', 'thinking', 'process', 'said', 'on',
      'an', 'if', 'else', 'whose', 'whom', 'because', 'into', 'any', 'every',
      'all', 'only', 'other', 'very', 'too', 'also', 'even', 'back',
      'after', 'before', 'under', 'over', 'through', 'between', 'against',
      'during', 'without', 'since', 'until', 'while',
      // Log del server LM Studio e metadati HTTP
      'load', 'config', 'server', 'error', 'internal', 'stats', 'system', 
      'fingerprint', 'completion', 'completions', 'chat', 'model', 'messages', 
      'role', 'content', 'assistant', 'user', 'character', 'game', 'dialogue', 
      'dialogo', 'sentence', 'sentences', 'words', 'word', 'write', 'writing', 
      'english', 'italian', 'translate', 'translation', 'response', 'output', 
      'text', 'tags', 'tag', 'previous', 'interactions', 'interaction', 'follow', 
      'following', 'second', 'third', 'next', 'last', 'end', 'finish', 'reason', 
      'length', 'status', 'body', 'html', 'head', 'meta', 'title', 'pre', 'div', 
      'span', 'class', 'id', 'href', 'url', 'uri', 'http', 'https', 'connection', 
      'timeout', 'limit', 'tokens', 'token', 'max', 'temperature'
    };
    
    final words = lowerText.split(RegExp(r'[^a-zA-Z]')).where((w) => w.isNotEmpty).toList();
    final matchedStopwords = <String>{};
    for (final word in words) {
      if (englishStopwords.contains(word)) {
        matchedStopwords.add(word);
      }
    }
    if (matchedStopwords.length >= 4) {
      return true;
    }

    bool hasMatch(String pattern) => RegExp(pattern, caseSensitive: false).hasMatch(t);

    // Rileva indicatori di liste numerate (1. , 2. , 3. , ecc.)
    final hasNumberedList = RegExp(r'\d+\.\s+').hasMatch(t);
    return hasNumberedList || 
           t.contains("**Analyze") || 
           lowerText.contains("thinking process") ||
           lowerText.contains("let's analyze") ||
           lowerText.contains("let's tackle") ||
           hasMatch(r'\bdraft\b') ||
           lowerText.contains("better:") ||
           lowerText.contains("better (") ||
           lowerText.contains("revised:") ||
           lowerText.contains("revision:") ||
           hasMatch(r'\bcritique\b') ||
           hasMatch(r'\bcriticism\b') ||
           lowerText.contains("notes:") ||
           hasMatch(r'\bstrategic\b') ||
           lowerText.contains("strategy:") ||
           lowerText.contains("persona:") ||
           hasMatch(r'\boption\b') ||
           hasMatch(r'\bchoice\b') ||
           hasMatch(r'\battempt\b') ||
           hasMatch(r'\bselection\b') ||
           lowerText.contains("max 2 sentences") ||
           lowerText.contains("1-2 sentences") ||
           lowerText.contains("dialogue:") ||
           lowerText.contains("response:") ||
           lowerText.contains("output:") ||
           lowerText.contains("final decision") ||
           lowerText.contains("final review") ||
           hasMatch(r'\bsafety\b') ||
           hasMatch(r'\bfictional\b') ||
           lowerText.contains("actually, let") ||
           lowerText.contains("let's make") ||
           lowerText.contains("make it") ||
           lowerText.contains("even shorter") ||
           lowerText.contains("let's try") ||
           lowerText.contains("blend:") ||
           lowerText.contains("try to") ||
           lowerText.contains("rule says") ||
           lowerText.contains("the rules") ||
           lowerText.contains("example given") ||
           lowerText.contains("the example") ||
           lowerText.contains("the prompt") ||
           hasMatch(r'\binstruction\b') ||
           t.startsWith(")") ||
           t.startsWith("(") ||
           t.startsWith("*") ||
           t.startsWith("-") ||
           t.startsWith(".") ||   // Frammento di ragionamento troncato
           t.endsWith(":") ||     // Intestazione di ragionamento tagliata alla fine
           (lowerText.startsWith("okay, let") && t.length > 50) ||
           (lowerText.startsWith("first, i need") && t.length > 50) ||
           (lowerText.startsWith("the user is") && t.length > 50) ||
           (lowerText.startsWith("i will") && t.length > 50 && (lowerText.contains("respond") || lowerText.contains("play")));
  }

  @override
  Future<Map<String, dynamic>> generateStructured({
    required String modelId,
    required List<Map<String, String>> messages,
    required Map<String, dynamic> schema,
    double temperature = 0.0,
  }) async {
    final url = Uri.parse("$baseUrl/v1/chat/completions");
    
    final body = jsonEncode({
      "model": modelId,
      "messages": messages,
      "temperature": temperature,
      "response_format": {
        "type": "json_schema",
        "json_schema": {
          "name": "structured_schema",
          "strict": true,
          "schema": schema,
        }
      }
    });

    final response = await http.post(
      url,
      headers: {"Content-Type": "application/json"},
      body: body,
    ).timeout(const Duration(seconds: 120));

    if (response.statusCode != 200) {
      throw Exception("Impossibile generare output strutturato: Status ${response.statusCode}, Body: ${response.body}");
    }

    final data = jsonDecode(response.body);
    final choice = data['choices']?[0];
    final message = choice?['message'] ?? const {};
    final rawJson = message['content'] as String? ?? '';

    return jsonDecode(rawJson) as Map<String, dynamic>;
  }

  @override
  Future<List<String>> discoverModels() async {
    try {
      final response = await http.get(Uri.parse("$baseUrl/v1/models"))
          .timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final modelsList = data['data'] as List?;
        if (modelsList != null) {
          return modelsList
              .map((m) => m['id'] as String? ?? '')
              .where((id) => id.isNotEmpty)
              .toList();
        }
      }
    } catch (_) {
      // Fallback in caso di errori di connessione o timeout
    }
    return const [];
  }
}


