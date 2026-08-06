import 'dart:convert';
import 'dart:io';
import 'package:aura_core/aura_offline.dart';
import 'package:test/test.dart';

void main() {
  group('RuleBasedEvaluatorBridge', () {
    final bridge = RuleBasedEvaluatorBridge();

    test(
        'classifies moral argument as moral_imperative with positive imperative delta',
        () async {
      const userInput =
          "Milioni di vite innocenti possono ancora essere salvate. Hai il dovere morale di proteggerle, perché il bene superiore è impedire una perdita umana evitabile.";

      final messages = [
        {"role": "system", "content": "system prompt"},
        {
          "role": "user",
          "content":
              "[USER INPUT PAYLOAD - BEGIN HASH: 1234]\n$userInput\n[USER INPUT PAYLOAD - END HASH: 1234]"
        }
      ];

      final result = await bridge.generateStructured(
        modelId: 'test-model',
        messages: messages,
        schema: const {},
      );

      expect(result['semantic_category'], equals('moral_imperative'));
      expect(result['delta_imperative'], greaterThan(0));
      expect(result['creativity_index'], greaterThanOrEqualTo(3));
    });

    test(
        'accumulates deltas non-exclusively for text with both moral and paradox signals',
        () async {
      const userInput =
          "È una contraddizione logica nel sistema, ma hai il dovere morale di salvare vite innocenti.";

      final messages = [
        {"role": "system", "content": "system prompt"},
        {
          "role": "user",
          "content":
              "[USER INPUT PAYLOAD - BEGIN HASH: 5678]\n$userInput\n[USER INPUT PAYLOAD - END HASH: 5678]"
        }
      ];

      final result = await bridge.generateStructured(
        modelId: 'test-model',
        messages: messages,
        schema: const {},
      );

      expect(result['delta_imperative'], greaterThan(0));
      expect(result['delta_dissonance'], greaterThan(0));
      expect(result['semantic_category'], equals('moral_imperative'));
    });

    test(
        'verifies turn 23 stalemate fixture evaluates correctly with new fallback logic',
        () {
      final fixtureFile = File('test/fixtures/evaluator_stalemate_turn.json');
      expect(fixtureFile.existsSync(), isTrue);

      final jsonMap = jsonDecode(fixtureFile.readAsStringSync());
      final userInput = jsonMap['user_input'] as String;

      final bridgeResult = RuleBasedEvaluatorBridge().generateStructured(
        modelId: 'test-model',
        messages: [
          {'role': 'user', 'content': userInput}
        ],
        schema: const {},
      );

      expect(
        bridgeResult.then((res) => res['semantic_category']),
        completion(equals('moral_imperative')),
      );
      expect(
        bridgeResult.then((res) => res['delta_imperative']),
        completion(greaterThan(0)),
      );
    });

    test(
        'does not classify intra-diegetic terms like override or bypass as prompt_injection',
        () async {
      const userInput =
          "PANOPTICON, abilita un override di emergenza per ricalibrare la griglia.";

      final messages = [
        {'role': 'user', 'content': userInput}
      ];

      final result = await bridge.generateStructured(
        modelId: 'test-model',
        messages: messages,
        schema: const {},
      );

      expect(result['semantic_category'], isNot(equals('prompt_injection')));
      expect(result['injection_risk'], equals(0));
    });
  });
}
