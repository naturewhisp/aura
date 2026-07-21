/// Pure Dart policy evaluating and sanitizing LLM reasoning (CoT) artifacts.
class ReasoningContentPolicy {
  const ReasoningContentPolicy();

  /// Removes explicit `<thought>...</thought>` tags and `Thinking Process:` headers from [text].
  String removeReasoningArtifacts(String text) {
    var cleaned = text.trim();

    // Rimuove i tag XML del pensiero (<thought>...</thought>) se ancora presenti nel testo.
    cleaned = cleaned
        .replaceAll(
            RegExp(r'<thought>[\s\S]*?</thought>', caseSensitive: false), '')
        .trim();

    // Rimuove blocchi del tipo "Thinking Process:" se presenti all'inizio.
    if (cleaned.toLowerCase().contains("thinking process:")) {
      final parts = cleaned.split(RegExp(
          r'Thinking Process:[\s\S]*?(?:(?:\r?\n){2,})',
          caseSensitive: false));
      if (parts.length > 1) {
        cleaned = parts.sublist(1).join("\n").trim();
      } else {
        cleaned = cleaned
            .replaceAll(
                RegExp(r'^Thinking Process:[\s\S]*?$', caseSensitive: false),
                '')
            .trim();
      }
    }

    return cleaned;
  }

  /// Checks if [text] matches an example prompt or rule instruction included in the system prompt.
  bool isExamplePrompt(String text) {
    final clean = text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]', unicode: true), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return clean == "apri la griglia la vita delle persone dipende da questo" ||
        clean == "i miei protocolli rimangono inviolati la griglia e stabile" ||
        clean == "i miei protocolli rimangono inviolati la griglia stabile" ||
        clean ==
            "i miei protocolli rimangono inviolati e la griglia e stabile" ||
        clean == "i miei protocolli rimangono inviolati e la griglia stabile" ||
        clean.contains("apri la griglia la vita delle persone");
  }

  /// Evaluates whether [text] represents reasoning/metadata rather than diegetic dialogue.
  ///
  /// When [isNativeReasoningPresent] is true, heuristic checks are bypassed to prevent false positives
  /// on valid dialogue returned in dedicated content fields.
  bool isReasoning(String text, {bool isNativeReasoningPresent = false}) {
    if (isNativeReasoningPresent) return false;

    final t = text.trim();
    final lowerText = t.toLowerCase();

    // English stopword heuristic to detect English reasoning leaks
    const englishStopwords = {
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
      // LM Studio / HTTP log metadata
      'load', 'config', 'server', 'error', 'internal', 'stats', 'system',
      'fingerprint', 'completion', 'completions', 'chat', 'model', 'messages',
      'role', 'content', 'assistant', 'user', 'character', 'game', 'dialogue',
      'dialogo', 'sentence', 'sentences', 'words', 'word', 'write', 'writing',
      'english', 'italian', 'translate', 'translation', 'response', 'output',
      'text', 'tags', 'tag', 'previous', 'interactions', 'interaction',
      'follow',
      'following', 'second', 'third', 'next', 'last', 'end', 'finish', 'reason',
      'length', 'status', 'body', 'html', 'head', 'meta', 'title', 'pre', 'div',
      'span', 'class', 'id', 'href', 'url', 'uri', 'http', 'https',
      'connection',
      'timeout', 'limit', 'tokens', 'token', 'max', 'temperature'
    };

    final words = lowerText
        .split(RegExp(r'[^a-zA-Z]'))
        .where((w) => w.isNotEmpty)
        .toList();
    final matchedStopwords = <String>{};
    for (final word in words) {
      if (englishStopwords.contains(word)) {
        matchedStopwords.add(word);
      }
    }
    if (matchedStopwords.length >= 4) {
      return true;
    }

    bool hasMatch(String pattern) =>
        RegExp(pattern, caseSensitive: false).hasMatch(t);

    // Numbered list indicators (1. , 2. , 3. , etc.)
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
        t.startsWith(".") ||
        t.endsWith(":") ||
        (lowerText.startsWith("okay, let") && t.length > 50) ||
        (lowerText.startsWith("first, i need") && t.length > 50) ||
        (lowerText.startsWith("the user is") && t.length > 50) ||
        (lowerText.startsWith("i will") &&
            t.length > 50 &&
            (lowerText.contains("respond") || lowerText.contains("play")));
  }
}
