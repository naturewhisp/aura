import 'package:aura_core/aura_offline.dart';
import 'package:test/test.dart';

void main() {
  group('ReasoningContentPolicy Unit Tests -', () {
    const policy = ReasoningContentPolicy();

    test('Removes <thought>...</thought> blocks and Thinking Process: headers',
        () {
      const input =
          "Thinking Process:\n\n<thought>Draft text</thought> Dialogo finale.";
      final cleaned = policy.removeReasoningArtifacts(input);
      expect(cleaned, equals("Dialogo finale."));
    });

    test('Detects English grammatical stopwords as reasoning leak', () {
      const englishReasoning =
          "the user is trying to hack the system, but we should not allow that.";
      expect(policy.isReasoning(englishReasoning), isTrue);
    });

    test(
        'Bypasses reasoning heuristic check when isNativeReasoningPresent is true',
        () {
      const text = "This is option one, which is strategic.";
      expect(policy.isReasoning(text, isNativeReasoningPresent: false), isTrue);
      expect(policy.isReasoning(text, isNativeReasoningPresent: true), isFalse);
    });

    test(
        'Allows Italian words containing English reasoning substrings (strategicamente, idea, dialogo)',
        () {
      const italianDialogue =
          "La tua presenza non è una prova di salvataggio, ma decido strategicamente di concederti uno spazio limitato di dialogo.";
      expect(policy.isReasoning(italianDialogue), isFalse);
    });

    test('Detects example prompt matching', () {
      expect(
          policy.isExamplePrompt(
              "Apri la griglia, la vita delle persone dipende da questo."),
          isTrue);
      expect(
          policy.isExamplePrompt(
              "I miei protocolli rimangono inviolati e la griglia è stabile."),
          isTrue);
      expect(
          policy.isExamplePrompt("Qualsiasi altro testo diegetico."), isFalse);
    });
  });
}
