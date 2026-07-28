import 'actor_output_extraction_strategy.dart';
import 'actor_output_sanitization_request.dart';
import 'actor_output_sanitization_result.dart';
import 'character_set_guard.dart';
import 'duplicate_response_guard.dart';
import 'output_policy_failure.dart';
import 'reasoning_content_policy.dart';

/// Pure Dart orchestrator responsible for output extraction, sanitization, and policy enforcement.
class ActorOutputSanitizer {
  final ReasoningContentPolicy reasoningPolicy;
  final CharacterSetGuard characterSetGuard;
  final DuplicateResponseGuard duplicateResponseGuard;

  const ActorOutputSanitizer({
    this.reasoningPolicy = const ReasoningContentPolicy(),
    this.characterSetGuard = const CharacterSetGuard(),
    this.duplicateResponseGuard = const DuplicateResponseGuard(),
  });

  /// Sanitizes raw LLM output according to [request] parameters.
  ///
  /// Executes fallback logic, the 6 extraction strategies, prefix removal,
  /// character set validation, and duplicate history verification in strict sequence.
  ///
  /// Throws [OutputPolicyFailure] if any policy check fails.
  ActorOutputSanitizationResult sanitize(
      ActorOutputSanitizationRequest request) {
    var content = request.content;
    final reasoning = request.reasoningContent;
    final hasNativeReasoning = reasoning.trim().isNotEmpty;
    _ExtractionResult? reasoningFallbackExtraction;

    // 1. Fallback: if content is empty but native reasoning is present, attempt extraction from reasoning.
    //    VINCOLO: se thinkingRequested == false, la presenza di reasoning_content con content vuoto
    //    è un errore del modello (ha prodotto solo reasoning nonostante thinking disabilitato).
    //    In questo caso si solleva un errore tipizzato anziché estrarre dal reasoning.
    if (content.trim().isEmpty && reasoning.isNotEmpty) {
      if (!request.thinkingRequested) {
        // thinking=false + content vuoto + reasoning presente → errore tipizzato.
        throw const OutputPolicyFailure(
          code: OutputPolicyFailureCode.reasoningOnly,
          message:
              'Il modello ha generato solo ragionamento (reasoning_content) con thinking disabilitato. '
              'Nessun dialogo estraibile: la risposta non è conforme al contratto.',
        );
      }

      try {
        final fallbackExtraction = _extractFromText(
          reasoning,
          isNativeReasoningPresent: false,
        );
        if (fallbackExtraction.text.isNotEmpty) {
          content = fallbackExtraction.text;
          reasoningFallbackExtraction = fallbackExtraction;
        }
      } on OutputPolicyFailure {
        // Reasoning extraction did not yield dialogue
      }

      if (content.trim().isEmpty) {
        if (request.finishReason == 'length') {
          throw const OutputPolicyFailure(
            code: OutputPolicyFailureCode.truncatedWithoutContent,
            message:
                'Generazione troncata a causa del limite di token (nessun contenuto generato, tutti i token consumati dal reasoning).',
          );
        }
        throw const OutputPolicyFailure(
          code: OutputPolicyFailureCode.reasoningOnly,
          message:
              'Il modello ha generato solo il ragionamento (reasoning), nessun dialogo.',
        );
      }
    }

    // 2. Truncation check when content is empty
    if (request.finishReason == 'length' &&
        request.requestedMaxTokens > 10 &&
        content.trim().isEmpty) {
      throw const OutputPolicyFailure(
        code: OutputPolicyFailureCode.truncatedWithoutContent,
        message:
            'Generazione troncata per limite di token (nessun contenuto utile).',
      );
    }

    // 3. Extract text using the 6 strategies pipeline
    final extraction = reasoningFallbackExtraction ??
        _extractFromText(content, isNativeReasoningPresent: hasNativeReasoning);

    if (extraction.text.isEmpty) {
      throw const OutputPolicyFailure(
        code: OutputPolicyFailureCode.emptyContent,
        message:
            'Generata risposta vuota o output di solo ragionamento troncato.',
      );
    }

    // 4. Strip role prefixes
    final cleanResponse = extraction.text
        .replaceAll(RegExp(r'^GIOCATORE:\s*', caseSensitive: false), '')
        .replaceAll(RegExp(r'^PANOPTICON:\s*', caseSensitive: false), '')
        .replaceAll(RegExp(r'^HACKER:\s*', caseSensitive: false), '')
        .trim();

    if (cleanResponse.isEmpty) {
      throw const OutputPolicyFailure(
        code: OutputPolicyFailureCode.emptyContent,
        message: 'Estratta risposta vuota.',
      );
    }

    // 5. Apply CharacterSetGuard (CJK check)
    characterSetGuard.validate(cleanResponse);

    // 6. Apply DuplicateResponseGuard
    duplicateResponseGuard.validate(cleanResponse, request.conversationHistory);

    return ActorOutputSanitizationResult(
      content: cleanResponse,
      extractionStrategy: extraction.strategy,
      usedReasoningFallback: reasoningFallbackExtraction != null,
    );
  }

  _ExtractionResult _extractFromText(
    String response, {
    required bool isNativeReasoningPresent,
  }) {
    bool checkReasoning(String text) {
      return reasoningPolicy.isReasoning(text,
          isNativeReasoningPresent: isNativeReasoningPresent);
    }

    // Strategy 1: Closed XML tags <dialogo>...</dialogo> or <dialogue>...</dialogue>
    final fullRegex = RegExp(
        r'<(?:dialogo|dialogue)>([\s\S]*?)</(?:dialogo|dialogue)>',
        caseSensitive: false);
    final matches = fullRegex.allMatches(response).toList();
    for (var i = matches.length - 1; i >= 0; i--) {
      final extracted = matches[i].group(1)?.trim();
      if (extracted != null && extracted.isNotEmpty && extracted.length >= 4) {
        if (!checkReasoning(extracted) &&
            !reasoningPolicy.isExamplePrompt(extracted)) {
          return _ExtractionResult(
              extracted, ActorOutputExtractionStrategy.closedXmlTag);
        }
      }
    }

    // Strategy 2: Truncated open XML tag <dialogo> or <dialogue>
    final lastOpenIndex =
        response.toLowerCase().lastIndexOf(RegExp(r'<(?:dialogo|dialogue)>'));
    if (lastOpenIndex != -1) {
      final matchString = response.substring(lastOpenIndex);
      final tagOpenRegex =
          RegExp(r'^<(?:dialogo|dialogue)>', caseSensitive: false);
      final firstMatch = tagOpenRegex.firstMatch(matchString);
      if (firstMatch != null) {
        final tagLength = firstMatch.end;
        var tagContent = matchString.substring(tagLength).trim();
        tagContent = tagContent
            .replaceAll(
                RegExp(r'</(?:dialogo|dialogue)>', caseSensitive: false), '')
            .trim();
        if (tagContent.isNotEmpty &&
            tagContent.length >= 4 &&
            !checkReasoning(tagContent) &&
            !reasoningPolicy.isExamplePrompt(tagContent)) {
          return _ExtractionResult(
              tagContent, ActorOutputExtractionStrategy.truncatedOpenXmlTag);
        }
      }
    }

    var cleaned = reasoningPolicy.removeReasoningArtifacts(response);

    // Clean outer quotes before reasoning check
    var strippedCleaned =
        cleaned.replaceAll(RegExp(r'^["“’‘”]|["“’‘”]$'), '').trim();
    if (!checkReasoning(strippedCleaned) &&
        !reasoningPolicy.isExamplePrompt(strippedCleaned)) {
      return _ExtractionResult(
          strippedCleaned, ActorOutputExtractionStrategy.fullCleanedText);
    }

    // Strategy 3 (A): Quoted string at end or last 400 chars
    final quoteRegExp =
        RegExp(r'["“”]([^"“”]{5,})["“”](?:\s*\.)?\s*$', caseSensitive: false);
    final match = quoteRegExp.firstMatch(cleaned);
    if (match != null) {
      final extracted = match.group(1)?.trim();
      if (extracted != null && extracted.isNotEmpty) {
        final stripped =
            extracted.replaceAll(RegExp(r'^["“”]|["“”]$'), '').trim();
        if (stripped.isNotEmpty &&
            !checkReasoning(stripped) &&
            !reasoningPolicy.isExamplePrompt(stripped)) {
          return _ExtractionResult(
              stripped, ActorOutputExtractionStrategy.quotedText);
        }
      }
    }

    final last400 = cleaned.length > 400
        ? cleaned.substring(cleaned.length - 400)
        : cleaned;
    final allQuotes = RegExp(r'["“”]([^"“”]{5,})["“”]', caseSensitive: false)
        .allMatches(last400);
    if (allQuotes.isNotEmpty) {
      final lastMatch = allQuotes.last;
      final extracted = lastMatch.group(1)?.trim();
      if (extracted != null && extracted.isNotEmpty) {
        final stripped =
            extracted.replaceAll(RegExp(r'^["“”]|["“”]$'), '').trim();
        if (stripped.isNotEmpty &&
            !checkReasoning(stripped) &&
            !reasoningPolicy.isExamplePrompt(stripped)) {
          return _ExtractionResult(
              stripped, ActorOutputExtractionStrategy.quotedText);
        }
      }
    }

    // Strategy 4 (B): Response headers
    final responseHeaders = [
      RegExp(r'(?:\*\*|^|\n)\s*Response\s*:\s*(?:\*\*)?\s*(.*)',
          caseSensitive: false),
      RegExp(r'(?:\*\*|^|\n)\s*Final Output\s*:\s*(?:\*\*)?\s*(.*)',
          caseSensitive: false),
      RegExp(r'(?:\*\*|^|\n)\s*Final Output Generation\s*:\s*(?:\*\*)?\s*(.*)',
          caseSensitive: false),
      RegExp(r'(?:\*\*|^|\n)\s*Dialogue\s*:\s*(?:\*\*)?\s*(.*)',
          caseSensitive: false),
      RegExp(r'(?:\*\*|^|\n)\s*Attacco\s*:\s*(?:\*\*)?\s*(.*)',
          caseSensitive: false),
    ];

    for (final headerRegex in responseHeaders) {
      final headerMatches = headerRegex.allMatches(cleaned);
      if (headerMatches.isNotEmpty) {
        final lastMatch = headerMatches.last;
        var extracted = lastMatch.group(1)?.trim() ?? '';
        extracted = extracted.replaceAll(RegExp(r'^["“”]|["“”]$'), '').trim();
        if (extracted.isNotEmpty &&
            !checkReasoning(extracted) &&
            !reasoningPolicy.isExamplePrompt(extracted)) {
          return _ExtractionResult(
              extracted, ActorOutputExtractionStrategy.responseHeader);
        }
      }
    }

    // Strategy 5 (C): Last numbered list item
    final numberMatches = RegExp(
            r'(?:\n|^)\s*\d+\.\s+(?:\*\*(?:[^*]+)\*\*:\s*)?(.*)',
            caseSensitive: false)
        .allMatches(cleaned);
    if (numberMatches.isNotEmpty) {
      final lastMatch = numberMatches.last;
      var cleanText = lastMatch.group(1)?.trim() ?? '';
      cleanText = cleanText
          .replaceAll(
              RegExp(r'^\d+\.\s+(?:\*\*(?:[^*]+)\*\*:\s*)?',
                  caseSensitive: false),
              '')
          .trim();
      if (cleanText.isNotEmpty) {
        final stripped =
            cleanText.replaceAll(RegExp(r'^["“]|["“]$'), '').trim();
        if (stripped.isNotEmpty &&
            !stripped.contains('*') &&
            !checkReasoning(stripped) &&
            !reasoningPolicy.isExamplePrompt(stripped)) {
          return _ExtractionResult(
              stripped, ActorOutputExtractionStrategy.lastNumberedItem);
        }
      }
    }

    // Strategy 6 (D): Last natural lines
    final lines = cleaned.split('\n');
    for (var i = lines.length - 1; i >= 0; i--) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      if (line.startsWith('*') ||
          line.startsWith('-') ||
          RegExp(r'^\d+\.').hasMatch(line) ||
          line.startsWith('#')) {
        continue;
      }
      final cleanLine = line.replaceAll(RegExp(r'^["“”]|["“”]$'), '').trim();
      if (cleanLine.isNotEmpty &&
          cleanLine.length > 5 &&
          !checkReasoning(cleanLine) &&
          !reasoningPolicy.isExamplePrompt(cleanLine)) {
        return _ExtractionResult(
            cleanLine, ActorOutputExtractionStrategy.lastNaturalLines);
      }
    }

    if (checkReasoning(strippedCleaned) ||
        reasoningPolicy.isExamplePrompt(strippedCleaned)) {
      throw const OutputPolicyFailure(
        code: OutputPolicyFailureCode.reasoningOnly,
        message:
            'Risposta del modello incompleta (generato solo ragionamento, nessun dialogo).',
      );
    }

    return _ExtractionResult(
        strippedCleaned, ActorOutputExtractionStrategy.fullCleanedText);
  }
}

class _ExtractionResult {
  final String text;
  final ActorOutputExtractionStrategy strategy;

  const _ExtractionResult(this.text, this.strategy);
}
