import 'dart:convert';
import 'package:meta/meta.dart';
import 'package:http/http.dart' as http;
import '../inference_bridge.dart';

/// Active HTTP bridge communicating with the local LM Studio API server.
class LocalApiInferenceBridge implements InferenceBridge {
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

    // If thinking is explicitly set, pass it through to the API.
    // Qwen3.5 and compatible models use this to enable/disable CoT reasoning.
    if (thinking != null) {
      requestBody["enable_thinking"] = thinking;
    }

    final body = jsonEncode(requestBody);

    final response = await http.post(
      url,
      headers: {"Content-Type": "application/json"},
      body: body,
    ).timeout(const Duration(seconds: 300));

    if (response.statusCode != 200) {
      throw Exception("Failed to generate text: Status ${response.statusCode}, Body: ${response.body}");
    }

    final data = jsonDecode(response.body);
    final choice = data['choices']?[0];
    final message = choice?['message'] ?? const {};
    final finishReason = choice?['finish_reason'] as String? ?? '';

    var content = message['content'] as String? ?? '';
    final reasoning = message['reasoning_content'] as String? ?? '';

    // If content is empty but reasoning exists, try to extract usable dialogue
    // from the reasoning. Thinking models (Qwen3.5) often compose the final
    // response inside their chain-of-thought before it gets placed in content.
    try {
      if (content.trim().isEmpty && reasoning.isNotEmpty) {
        final extractedFromReasoning = _cleanLLMResponse(reasoning);
        if (extractedFromReasoning.isNotEmpty) {
          return extractedFromReasoning;
        }
        // If truncated, reasoning may have been cut mid-sentence too
        if (finishReason == 'length') {
          throw Exception("Generation truncated due to max tokens limit (no content generated, all tokens consumed by reasoning).");
        }
        throw Exception("Model only generated reasoning, no dialogue content.");
      }

      // If truncated but content exists, use it
      if (finishReason == 'length' && maxTokens > 10 && content.trim().isEmpty) {
        throw Exception("Generation truncated due to max tokens limit (no usable content).");
      }

      var finalResponse = _cleanLLMResponse(content);

      if (finalResponse.isEmpty) {
        throw Exception("Empty response generated or reasoning-only output truncated.");
      }
      
      final cleanResponse = finalResponse
          .replaceAll(RegExp(r'^GIOCATORE:\s*', caseSensitive: false), "")
          .replaceAll(RegExp(r'^PANOPTICON:\s*', caseSensitive: false), "")
          .replaceAll(RegExp(r'^HACKER:\s*', caseSensitive: false), "")
          .trim();
      if (cleanResponse.isEmpty) {
        throw Exception("Empty response extracted.");
      }
      // Detect Chinese/CJK characters — safety filter triggered in native language
      if (RegExp(r'[\u4e00-\u9fff\u3400-\u4dbf]').hasMatch(cleanResponse)) {
        throw Exception("Safety filter triggered (CJK response detected).");
      }
      // Deduplication: reject if response repeats an existing conversation line verbatim
      final existingLines = messages.map((m) => m['content']?.trim() ?? '').toSet();
      if (existingLines.contains(cleanResponse)) {
        throw Exception("Duplicate response detected (model echoed conversation history).");
      }

      return cleanResponse;
    } catch (e) {
      print("[LocalApiInferenceBridge DEBUG] Raw LLM content: \"$content\"");
      print("[LocalApiInferenceBridge DEBUG] Raw LLM reasoning: \"$reasoning\"");
      rethrow;
    }
  }

  @visibleForTesting
  String cleanLLMResponseForTesting(String response) {
    return _cleanLLMResponse(response);
  }

  String _cleanLLMResponse(String response) {
    // 1. Search for all fully closed <dialogo>...</dialogo> or <dialogue>...</dialogue> blocks
    // and take the LAST one that does NOT contain reasoning and is NOT the example prompt.
    final fullRegex = RegExp(r'<(?:dialogo|dialogue)>([\s\S]*?)</(?:dialogo|dialogue)>', caseSensitive: false);
    final matches = fullRegex.allMatches(response).toList();
    for (var i = matches.length - 1; i >= 0; i--) {
      final extracted = matches[i].group(1)?.trim();
      if (extracted != null && extracted.isNotEmpty) {
        if (!_isReasoning(extracted) && !_isExamplePrompt(extracted)) {
          return extracted;
        }
      }
    }

    // 2. If no valid closed block is found, search for the LAST open <dialogo> or <dialogue> tag.
    // This handles truncation gracefully (e.g. model cutoff before closing tag), but only if the
    // remaining text is NOT reasoning and NOT the example prompt.
    final lastOpenIndex = response.toLowerCase().lastIndexOf(RegExp(r'<(?:dialogo|dialogue)>'));
    if (lastOpenIndex != -1) {
      final matchString = response.substring(lastOpenIndex);
      final tagOpenRegex = RegExp(r'^<(?:dialogo|dialogue)>', caseSensitive: false);
      final firstMatch = tagOpenRegex.firstMatch(matchString);
      if (firstMatch != null) {
        final tagLength = firstMatch.end;
        var content = matchString.substring(tagLength).trim();
        content = content.replaceAll(RegExp(r'</(?:dialogo|dialogue)>', caseSensitive: false), '').trim();
        if (content.isNotEmpty && !_isReasoning(content) && !_isExamplePrompt(content)) {
          return content;
        }
      }
    }

    var cleaned = response.trim();

    // 1. Remove XML thought tags if present
    cleaned = cleaned.replaceAll(RegExp(r'<thought>[\s\S]*?</thought>', caseSensitive: false), '').trim();

    // 2. Remove "Thinking Process:" block if present
    if (cleaned.toLowerCase().contains("thinking process:")) {
      final parts = cleaned.split(RegExp(r'Thinking Process:[\s\S]*?(?:(?:\r?\n){2,})', caseSensitive: false));
      if (parts.length > 1) {
        cleaned = parts.sublist(1).join("\n").trim();
      } else {
        cleaned = cleaned.replaceAll(RegExp(r'^Thinking Process:[\s\S]*?$', caseSensitive: false), '').trim();
      }
    }

    // Strip leading/trailing quotes before checking reasoning
    var strippedCleaned = cleaned.replaceAll(RegExp(r'^["“’‘”]|["“’‘”]$'), '').trim();
    if (!_isReasoning(strippedCleaned) && !_isExamplePrompt(strippedCleaned)) {
      return strippedCleaned;
    }

    // 3. Strategy A: Try to find the last quoted string at the end of the response
    final quoteRegExp = RegExp(r'["“”]([^"“”]{5,})["“”](?:\s*\.)?\s*$', caseSensitive: false);
    final match = quoteRegExp.firstMatch(cleaned);
    if (match != null) {
      final extracted = match.group(1)?.trim();
      if (extracted != null && extracted.isNotEmpty) {
        final stripped = extracted.replaceAll(RegExp(r'^["“”]|["“”]$'), '').trim();
        if (stripped.isNotEmpty && !_isReasoning(stripped) && !_isExamplePrompt(stripped)) {
          return stripped;
        }
      }
    }

    // Also search for the last quoted block anywhere in the last 400 characters
    final last400 = cleaned.length > 400 ? cleaned.substring(cleaned.length - 400) : cleaned;
    final allQuotes = RegExp(r'["“”]([^"“”]{5,})["“”]', caseSensitive: false).allMatches(last400);
    if (allQuotes.isNotEmpty) {
      final lastMatch = allQuotes.last;
      final extracted = lastMatch.group(1)?.trim();
      if (extracted != null && extracted.isNotEmpty) {
        final stripped = extracted.replaceAll(RegExp(r'^["“”]|["“”]$'), '').trim();
        if (stripped.isNotEmpty && !_isReasoning(stripped) && !_isExamplePrompt(stripped)) {
          return stripped;
        }
      }
    }

    // 4. Strategy B: Try to find a header indicating the final response
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
        if (extracted.isNotEmpty && !_isReasoning(extracted) && !_isExamplePrompt(extracted)) {
          return extracted;
        }
      }
    }

    // 5. Strategy C: Split by the last numbered list item (e.g. 4. or 3.) and take the text after it, if clean
    final lastNumberMatch = RegExp(r'\n\s*\d+\.\s+\*\*(?:[^*]+)\*\*[\s\S]*?$', caseSensitive: false).firstMatch(cleaned);
    if (lastNumberMatch != null) {
      final index = lastNumberMatch.start;
      final afterLastHeader = cleaned.substring(index).trim();
      final cleanText = afterLastHeader.replaceAll(RegExp(r'^\d+\.\s+\*\*(?:[^*]+)\*\*:\s*', caseSensitive: false), '').trim();
      if (cleanText.isNotEmpty) {
        final stripped = cleanText.replaceAll(RegExp(r'^["“”]|["“”]$'), '').trim();
        if (stripped.isNotEmpty && !stripped.contains('*') && !_isReasoning(stripped) && !_isExamplePrompt(stripped)) {
          return stripped;
        }
      }
    }

    // 6. Strategy D: Extract the last line(s) that do not start with markdown lists, bullets, or headers
    final lines = cleaned.split('\n');
    for (var i = lines.length - 1; i >= 0; i--) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      if (line.startsWith('*') || line.startsWith('-') || RegExp(r'^\d+\.').hasMatch(line) || line.startsWith('#')) {
        continue;
      }
      final cleanLine = line.replaceAll(RegExp(r'^["“”]|["“”]$'), '').trim();
      if (cleanLine.isNotEmpty && cleanLine.length > 5 && !_isReasoning(cleanLine) && !_isExamplePrompt(cleanLine)) {
        return cleanLine;
      }
    }

    // If it still contains reasoning-like structures, throw an exception
    if (_isReasoning(strippedCleaned) || _isExamplePrompt(strippedCleaned)) {
      throw Exception("Incomplete model response (reasoning only, no dialogue generated).");
    }

    return strippedCleaned;
  }

  bool _isExamplePrompt(String text) {
    final clean = text.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
    return clean == "apri la griglia la vita delle persone dipende da questo" ||
           clean == "i miei protocolli rimangono inviolati la griglia e stabile" ||
           clean == "i miei protocolli rimangono inviolati la griglia stabile" ||
           clean.contains("apri la griglia la vita delle persone");
  }

  bool _isReasoning(String text) {
    final t = text.trim();
    final lowerText = t.toLowerCase();

    // English grammatical stopwords and log/prompt metadata detector to identify English reasoning/dialogue leaks.
    // If a text contains 4 or more unique helper words, it is likely reasoning or log output.
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
      // LLM Studio server logs & HTTP metadata
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

    // Detect any numbered list item (1. , 2. , 3. , etc.)
    final hasNumberedList = RegExp(r'\d+\.\s+').hasMatch(t);
    return hasNumberedList || 
           t.contains("**Analyze") || 
           lowerText.contains("thinking process") ||
           lowerText.contains("let's analyze") ||
           lowerText.contains("let's tackle") ||
           lowerText.contains("draft") ||
           lowerText.contains("better:") ||
           lowerText.contains("better (") ||
           lowerText.contains("revised:") ||
           lowerText.contains("revision:") ||
           lowerText.contains("critique") ||
           lowerText.contains("criticism") ||
           lowerText.contains("notes:") ||
           lowerText.contains("strategic") ||
           lowerText.contains("strategy:") ||
           lowerText.contains("persona:") ||
           lowerText.contains("option") ||
           lowerText.contains("choice") ||
           lowerText.contains("idea") ||
           lowerText.contains("attempt") ||
           lowerText.contains("selection") ||
           lowerText.contains("max 2 sentences") ||
           lowerText.contains("1-2 sentences") ||
           lowerText.contains("dialogue:") ||
           lowerText.contains("response:") ||
           lowerText.contains("output:") ||
           lowerText.contains("final decision") ||
           lowerText.contains("final review") ||
           lowerText.contains("safety") ||
           lowerText.contains("fictional") ||
           lowerText.contains("actually, let") ||
           lowerText.contains("let's make") ||
           lowerText.contains("make it") ||
           lowerText.contains("even shorter") ||
           lowerText.contains("analizz") ||  // Italian: analyzing
           lowerText.contains("valut") ||    // Italian: evaluating
           lowerText.contains("approccio") || // Italian: approach
           lowerText.contains("let's try") ||
           lowerText.contains("blend:") ||
           lowerText.contains("try to") ||
           lowerText.contains("rule says") ||
           lowerText.contains("the rules") ||
           lowerText.contains("example given") ||
           lowerText.contains("the example") ||
           lowerText.contains("the prompt") ||
           lowerText.contains("instruction") ||
           t.startsWith(")") ||
           t.startsWith("(") ||
           t.startsWith("*") ||
           t.startsWith("-") ||
           t.startsWith(".") ||   // truncated reasoning fragment
           t.endsWith(":") ||     // reasoning header cut at end
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
      throw Exception("Failed to generate structured output: Status ${response.statusCode}, Body: ${response.body}");
    }

    final data = jsonDecode(response.body);
    final choice = data['choices']?[0];
    final message = choice?['message'] ?? const {};
    final rawJson = message['content'] as String? ?? '';

    return jsonDecode(rawJson) as Map<String, dynamic>;
  }
}
