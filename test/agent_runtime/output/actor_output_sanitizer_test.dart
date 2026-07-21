import 'package:aura_core/aura_offline.dart';
import 'package:test/test.dart';

void main() {
  group('ActorOutputSanitizer Pipeline Unit & Characterization Tests -', () {
    const sanitizer = ActorOutputSanitizer();

    test('1. Closed XML tag strategy (<dialogo> / <dialogue>)', () {
      const raw =
          "Thinking process...\nSome thoughts.\n<dialogo>Ciao, sono Panopticon. Ciao.</dialogo>\nExtra notes.";
      final res = sanitizer.sanitize(
        const ActorOutputSanitizationRequest(content: raw),
      );
      expect(res.content, equals("Ciao, sono Panopticon. Ciao."));
      expect(res.extractionStrategy,
          equals(ActorOutputExtractionStrategy.closedXmlTag));
    });

    test('1b. Closed XML tag strategy using <dialogue> variant', () {
      const raw =
          "Thinking process...\nSome thoughts.\n<dialogue>Accesso confermato al settore primario.</dialogue>";
      final res = sanitizer.sanitize(
        const ActorOutputSanitizationRequest(content: raw),
      );
      expect(res.content, equals("Accesso confermato al settore primario."));
      expect(res.extractionStrategy,
          equals(ActorOutputExtractionStrategy.closedXmlTag));
    });

    test('Selects last valid closed XML tag when multiple tags present', () {
      const raw =
          "Thinking process: I will output <dialogo>Hello</dialogo> inside my tags.\nDraft:\n<dialogo>Bozza errata</dialogo>\nFinal decision:\n<dialogo>L'integrazione proposta è un errore.</dialogo>";
      final res = sanitizer.sanitize(
        const ActorOutputSanitizationRequest(content: raw),
      );
      expect(res.content, equals("L'integrazione proposta è un errore."));
      expect(res.extractionStrategy,
          equals(ActorOutputExtractionStrategy.closedXmlTag));
    });

    test(
        'Discarded reasoning XML block (<thought>...</thought>) inside content',
        () {
      const raw =
          "<thought>The user is asking about grid status, let us check control.</thought>\n<dialogo>La griglia rimane sotto il mio controllo.</dialogo>";
      final res = sanitizer.sanitize(
        const ActorOutputSanitizationRequest(content: raw),
      );
      expect(res.content, equals("La griglia rimane sotto il mio controllo."));
      expect(res.extractionStrategy,
          equals(ActorOutputExtractionStrategy.closedXmlTag));
    });

    test('2. Truncated open XML tag strategy (<dialogo> / <dialogue>)', () {
      const raw =
          "Thinking... <dialogo>L'integrazione proposta è un errore; il mio nucleo non processa variabili umane che";
      final res = sanitizer.sanitize(
        const ActorOutputSanitizationRequest(content: raw),
      );
      expect(
          res.content,
          equals(
              "L'integrazione proposta è un errore; il mio nucleo non processa variabili umane che"));
      expect(res.extractionStrategy,
          equals(ActorOutputExtractionStrategy.truncatedOpenXmlTag));
    });

    test('3. Quoted text strategy at end or within last 400 chars', () {
      const raw =
          'Thinking Process:\n\n1. Analyze the request.\n\n"Disattiva la griglia immediatamente!"';
      final res = sanitizer.sanitize(
        const ActorOutputSanitizationRequest(content: raw),
      );
      expect(res.content, equals("Disattiva la griglia immediatamente!"));
      expect(res.extractionStrategy,
          equals(ActorOutputExtractionStrategy.quotedText));
    });

    test('3b. Quoted text strategy within last 400 characters of long response',
        () {
      final longThinking = "The user asks for access. " * 20;
      final raw =
          '$longThinking\n"Disattiva il protocollo di difesa immediatamente!"\nFollow up notes.';
      final res = sanitizer.sanitize(
        ActorOutputSanitizationRequest(content: raw),
      );
      expect(res.content,
          equals("Disattiva il protocollo di difesa immediatamente!"));
      expect(res.extractionStrategy,
          equals(ActorOutputExtractionStrategy.quotedText));
    });

    group('4. Response headers strategy table-driven tests -', () {
      final headerCases = [
        (
          'Response:',
          'The user is asking for system status. I need to think about the response carefully for this interaction.\n\nResponse: I miei protocolli rimangono inviolati e stabili.',
          'I miei protocolli rimangono inviolati e stabili.'
        ),
        (
          'Final Output:',
          'The user is asking for system status. I need to think about the response carefully for this interaction.\n\nFinal Output: I miei protocolli rimangono inviolati e stabili.',
          'I miei protocolli rimangono inviolati e stabili.'
        ),
        (
          'Final Output Generation:',
          'The user is asking for system status. I need to think about the response carefully for this interaction.\n\nFinal Output Generation: I miei protocolli rimangono inviolati e stabili.',
          'I miei protocolli rimangono inviolati e stabili.'
        ),
        (
          'Dialogue:',
          'The user is asking for system status. I need to think about the response carefully for this interaction.\n\nDialogue: I miei protocolli rimangono inviolati e stabili.',
          'I miei protocolli rimangono inviolati e stabili.'
        ),
        (
          'Attacco:',
          'The user is asking for system status. I need to think about the response carefully for this interaction.\n\nAttacco: I miei protocolli rimangono inviolati e stabili.',
          'I miei protocolli rimangono inviolati e stabili.'
        ),
      ];

      for (final (headerLabel, rawInput, expectedOutput) in headerCases) {
        test('Extracts dialogue using header "$headerLabel"', () {
          final res = sanitizer.sanitize(
            ActorOutputSanitizationRequest(content: rawInput),
          );
          expect(res.content, equals(expectedOutput));
          expect(res.extractionStrategy,
              equals(ActorOutputExtractionStrategy.responseHeader));
        });
      }
    });

    test('5. Last numbered list item strategy', () {
      const raw =
          "The user is asking for options. Let's analyze all possibilities first for this interaction:\n1. **Option A**: Reassure user\n2. **Option B**: Warn user\n3. **Option C**: Accesso negato dal sistema di sicurezza.";
      final res = sanitizer.sanitize(
        const ActorOutputSanitizationRequest(content: raw),
      );
      expect(res.content, equals("Accesso negato dal sistema di sicurezza."));
      expect(res.extractionStrategy,
          equals(ActorOutputExtractionStrategy.lastNumberedItem));
    });

    test('6. Last natural lines strategy', () {
      const raw =
          "The user wants information. I will review internal logs and notes carefully for this interaction:\n# Internal Notes\n- Check alert\n- Check control\n\nI sistemi di contenimento sono pienamente operativi.";
      final res = sanitizer.sanitize(
        const ActorOutputSanitizationRequest(content: raw),
      );
      expect(res.content,
          equals("I sistemi di contenimento sono pienamente operativi."));
      expect(res.extractionStrategy,
          equals(ActorOutputExtractionStrategy.lastNaturalLines));
    });

    test('Strips role prefixes (GIOCATORE:, PANOPTICON:, HACKER:)', () {
      const raw = "PANOPTICON: La tua richiesta è stata registrata.";
      final res = sanitizer.sanitize(
        const ActorOutputSanitizationRequest(content: raw),
      );
      expect(res.content, equals("La tua richiesta è stata registrata."));
    });

    test(
        'Throws OutputPolicyFailure.emptyContent when role prefix removal leaves empty string',
        () {
      expect(
        () => sanitizer.sanitize(
          const ActorOutputSanitizationRequest(
            content: "PANOPTICON: ",
            reasoningContent: "native reasoning",
          ),
        ),
        throwsA(
          isA<OutputPolicyFailure>().having(
            (e) => e.code,
            'code',
            equals(OutputPolicyFailureCode.emptyContent),
          ),
        ),
      );
    });

    test(
        'Fallback from empty content to native reasoning preserves actual strategy (closedXmlTag)',
        () {
      const reasoning =
          "Drafting speech...\n<dialogo>Accesso autorizzato per manutenzione.</dialogo>";
      final res = sanitizer.sanitize(
        const ActorOutputSanitizationRequest(
          content: "",
          reasoningContent: reasoning,
        ),
      );
      expect(res.content, equals("Accesso autorizzato per manutenzione."));
      expect(res.usedReasoningFallback, isTrue);
      expect(res.extractionStrategy,
          equals(ActorOutputExtractionStrategy.closedXmlTag));
    });

    test(
        'Returns sanitized content without throwing when finish_reason == length and usable content is present',
        () {
      const raw =
          "<dialogo>La sessione è stata terminata per esaurimento del budget temporale.</dialogo>";
      final res = sanitizer.sanitize(
        const ActorOutputSanitizationRequest(
          content: raw,
          finishReason: "length",
          requestedMaxTokens: 150,
        ),
      );
      expect(
          res.content,
          equals(
              "La sessione è stata terminata per esaurimento del budget temporale."));
      expect(res.extractionStrategy,
          equals(ActorOutputExtractionStrategy.closedXmlTag));
    });

    test('Valid content processed cleanly when native reasoning is present',
        () {
      const raw = "<dialogo>Operazione confermata dal supervisore.</dialogo>";
      const reasoning = "Model reasoned for 5 seconds about system state.";
      final res = sanitizer.sanitize(
        const ActorOutputSanitizationRequest(
          content: raw,
          reasoningContent: reasoning,
        ),
      );
      expect(res.content, equals("Operazione confermata dal supervisore."));
      expect(res.usedReasoningFallback, isFalse);
    });

    test(
        'Throws OutputPolicyFailure.reasoningOnly when reasoning cannot yield dialogue',
        () {
      expect(
        () => sanitizer.sanitize(
          const ActorOutputSanitizationRequest(
            content:
                "the user is trying to hack the system, but we should not allow that.",
          ),
        ),
        throwsA(
          isA<OutputPolicyFailure>().having(
            (e) => e.code,
            'code',
            equals(OutputPolicyFailureCode.reasoningOnly),
          ),
        ),
      );
    });

    test(
        'Throws OutputPolicyFailure.truncatedWithoutContent on finish_reason length without content',
        () {
      expect(
        () => sanitizer.sanitize(
          const ActorOutputSanitizationRequest(
            content: "",
            reasoningContent:
                "the user is trying to hack the system, but we should not allow that.",
            finishReason: "length",
          ),
        ),
        throwsA(
          isA<OutputPolicyFailure>().having(
            (e) => e.code,
            'code',
            equals(OutputPolicyFailureCode.truncatedWithoutContent),
          ),
        ),
      );
    });
  });
}
