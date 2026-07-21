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

    test(
        '4. Response headers strategy (Response:, Final Output:, Dialogue:, Attacco:)',
        () {
      const raw =
          "The user is asking for system status. I need to think about the response carefully for this interaction.\n\n**Response:** I miei protocolli rimangono inviolati e stabili.";
      final res = sanitizer.sanitize(
        const ActorOutputSanitizationRequest(content: raw),
      );
      expect(res.content,
          equals("I miei protocolli rimangono inviolati e stabili."));
      expect(res.extractionStrategy,
          equals(ActorOutputExtractionStrategy.responseHeader));
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

    test('Fallback from empty content to native reasoning content', () {
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
        'Throws OutputPolicyFailure.truncatedWithoutContent on finish_reason length',
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
