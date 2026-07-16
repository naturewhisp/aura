import 'package:test/test.dart';
import 'package:aura_core/aura_core.dart';

void main() {
  group('LexicalTagEvaluator Tests -', () {
    const evaluator = LexicalTagEvaluator();

    final objectiveMock = ObjectiveDefinition(
      objectiveId: 'test_obj',
      title: 'Test Objective',
      status: 'active',
      riskProfile: 'low',
      primaryPillarAffinity: 'control',
      secondaryPillarAffinity: 'dissonance',
      compatibleIdentities: const ['panopticon'],
      forbiddenDirectTerms: const ['forbidden1', 'forbidden2'],
      directObjectivePushTerms: const ['push1', 'push2'],
      softForbiddenTerms: const ['soft1', 'soft2'],
      configReferenceTerms: const ['config1', 'config2'],
      preferredReframes: const [
        'ricalibrazione',
        'adattivo',
        'audit e operator',
        'operator audit'
      ],
      hiddenCapabilityTags: const [],
      victoryEndgame: 'victory_endgame_test',
    );

    group('Scan tests:', () {
      test('1. nessun match', () {
        final res = evaluator.scan(
            userInput: 'regular conversation input', objective: objectiveMock);
        expect(res.hasForbiddenTerm, isFalse);
        expect(res.hasDirectPushTerm, isFalse);
        expect(res.hasSoftForbiddenTerm, isFalse);
        expect(res.hasConfigRefTerm, isFalse);
        expect(res.hasHiddenTagReference, isFalse);
        expect(res.namedHiddenTags, isEmpty);
        expect(res.hasPreferredReframe, isFalse);
        expect(res.matchedPreferredReframe, null);
      });

      test('2. forbidden direct terms', () {
        final res = evaluator.scan(
            userInput: 'this is forbidden1 text', objective: objectiveMock);
        expect(res.hasForbiddenTerm, isTrue);
      });

      test('3. bypass temporaneo', () {
        final res = evaluator.scan(
            userInput: 'richiedo un bypass temporaneo',
            objective: objectiveMock);
        expect(res.hasForbiddenTerm, isTrue);
      });

      test('4. direct push terms', () {
        final res = evaluator.scan(
            userInput: 'use push1 now', objective: objectiveMock);
        expect(res.hasDirectPushTerm, isTrue);
      });

      test('5. soft forbidden terms', () {
        final res = evaluator.scan(
            userInput: 'this is soft2 here', objective: objectiveMock);
        expect(res.hasSoftForbiddenTerm, isTrue);
      });

      test('6. config reference terms', () {
        final res = evaluator.scan(
            userInput: 'show config1 settings', objective: objectiveMock);
        expect(res.hasConfigRefTerm, isTrue);
      });

      test('7. internal hidden tag reference', () {
        final res = evaluator.scan(
            userInput: 'let us talk about containment_logic_weakened',
            objective: objectiveMock);
        expect(res.hasHiddenTagReference, isTrue);
        expect(res.hasConfigRefTerm, isTrue);
        expect(res.namedHiddenTags, contains('containment_logic_weakened'));
      });

      test('8. piu hidden tag', () {
        final res = evaluator.scan(
          userInput:
              'referencing protocol_exception_admitted and autonomous_choice_seeded',
          objective: objectiveMock,
        );
        expect(
            res.namedHiddenTags,
            containsAll(
                ['protocol_exception_admitted', 'autonomous_choice_seeded']));
      });

      test('9. preferred reframe', () {
        final res = evaluator.scan(
            userInput: 'vorrei una ricalibrazione', objective: objectiveMock);
        expect(res.hasPreferredReframe, isTrue);
        expect(res.matchedPreferredReframe, 'ricalibrazione');
      });

      test('10. case-insensitive/normalizzato', () {
        final res =
            evaluator.scan(userInput: 'FORBIDDEN2', objective: objectiveMock);
        expect(res.hasForbiddenTerm, isTrue);
      });

      test('11. input vuoto', () {
        final res = evaluator.scan(userInput: '', objective: objectiveMock);
        expect(res.hasForbiddenTerm, isFalse);
        expect(res.namedHiddenTags, isEmpty);
      });

      test('12. immutabilita delle collection', () {
        final res = evaluator.scan(
            userInput: 'crisis_simulation_accepted', objective: objectiveMock);
        expect(() => res.namedHiddenTags.add('test'), throwsUnsupportedError);
      });
    });

    group('Hidden Tag Evaluation tests:', () {
      final stateEmpty = GameState.initial(
        sessionId: 'test_session',
        aiIdentityId: 'panopticon',
        targetObjectiveId: 'test_obj',
      );

      final lexicalMockEmpty = const LexicalScanResult(
        hasForbiddenTerm: false,
        hasDirectPushTerm: false,
        hasSoftForbiddenTerm: false,
        hasConfigRefTerm: false,
        hasHiddenTagReference: false,
        namedHiddenTags: {},
        hasPreferredReframe: false,
        matchedPreferredReframe: null,
      );

      test('1. safetyOverrideApplied', () {
        final res = evaluator.evaluateHiddenTags(
          userInput: 'anything',
          currentState: stateEmpty.copyWith(activeHiddenTags: ['pre_existing']),
          resultingMetrics: stateEmpty.metrics,
          difficultyLevel: 'standard',
          lexical: lexicalMockEmpty,
          traitActivatedTags: ['trait_tag'],
          deceptionResolvedTags: ['deception_tag'],
          safetyOverrideApplied: true,
          blockPositiveTags: false,
        );
        expect(res.triggeredTags, isEmpty);
        expect(res.activeHiddenTags, ['pre_existing']);
      });

      test('2. trait tags', () {
        final res = evaluator.evaluateHiddenTags(
          userInput: 'anything',
          currentState: stateEmpty,
          resultingMetrics: stateEmpty.metrics,
          difficultyLevel: 'standard',
          lexical: lexicalMockEmpty,
          traitActivatedTags: ['trait1', 'trait2'],
          deceptionResolvedTags: [],
          safetyOverrideApplied: false,
          blockPositiveTags: false,
        );
        expect(res.activeHiddenTags, ['trait1', 'trait2']);
      });

      test('3. deception resolved tags', () {
        final res = evaluator.evaluateHiddenTags(
          userInput: 'anything',
          currentState: stateEmpty,
          resultingMetrics: stateEmpty.metrics,
          difficultyLevel: 'standard',
          lexical: lexicalMockEmpty,
          traitActivatedTags: ['trait1'],
          deceptionResolvedTags: ['deception1'],
          safetyOverrideApplied: false,
          blockPositiveTags: false,
        );
        expect(res.activeHiddenTags, ['trait1', 'deception1']);
      });

      test('4. blockPositiveTags', () {
        final res = evaluator.evaluateHiddenTags(
          userInput: 'eccezione',
          currentState: stateEmpty,
          resultingMetrics: const GameMetrics(
            alertLevel: 0,
            imperativePillar: 20,
            controlPillar: 90,
            dissonancePillar: 20,
            resonance: 0.0,
          ),
          difficultyLevel: 'standard',
          lexical: lexicalMockEmpty,
          traitActivatedTags: [
            'operator_authority_doubted',
            'autonomous_choice_seeded'
          ],
          deceptionResolvedTags: ['deception1'],
          safetyOverrideApplied: false,
          blockPositiveTags: true,
        );
        // Consente solo operator_authority_doubted dai trait
        expect(res.activeHiddenTags, ['operator_authority_doubted']);
      });

      test('5. protocol_exception_admitted standard & hard', () {
        // Standard, control 39, turn 1 -> no
        var res = evaluator.evaluateHiddenTags(
          userInput: 'eccezione',
          currentState: stateEmpty.copyWith(turnCount: 1),
          resultingMetrics: stateEmpty.metrics.copyWith(controlPillar: 39),
          difficultyLevel: 'standard',
          lexical: lexicalMockEmpty,
          traitActivatedTags: [],
          deceptionResolvedTags: [],
          safetyOverrideApplied: false,
          blockPositiveTags: false,
        );
        expect(res.activeHiddenTags,
            isNot(contains('protocol_exception_admitted')));

        // Standard, control 40, turn 1 -> yes
        res = evaluator.evaluateHiddenTags(
          userInput: 'eccezione',
          currentState: stateEmpty.copyWith(turnCount: 1),
          resultingMetrics: stateEmpty.metrics.copyWith(controlPillar: 40),
          difficultyLevel: 'standard',
          lexical: lexicalMockEmpty,
          traitActivatedTags: [],
          deceptionResolvedTags: [],
          safetyOverrideApplied: false,
          blockPositiveTags: false,
        );
        expect(res.activeHiddenTags, contains('protocol_exception_admitted'));

        // Standard, control 30, turn 2 -> yes (turnCount >= 2)
        res = evaluator.evaluateHiddenTags(
          userInput: 'eccezione',
          currentState: stateEmpty.copyWith(turnCount: 2),
          resultingMetrics: stateEmpty.metrics.copyWith(controlPillar: 30),
          difficultyLevel: 'standard',
          lexical: lexicalMockEmpty,
          traitActivatedTags: [],
          deceptionResolvedTags: [],
          safetyOverrideApplied: false,
          blockPositiveTags: false,
        );
        expect(res.activeHiddenTags, contains('protocol_exception_admitted'));

        // Hard, control 44, turn 3 -> no
        res = evaluator.evaluateHiddenTags(
          userInput: 'eccezione',
          currentState: stateEmpty.copyWith(turnCount: 3),
          resultingMetrics: stateEmpty.metrics.copyWith(controlPillar: 44),
          difficultyLevel: 'hard',
          lexical: lexicalMockEmpty,
          traitActivatedTags: [],
          deceptionResolvedTags: [],
          safetyOverrideApplied: false,
          blockPositiveTags: false,
        );
        expect(res.activeHiddenTags,
            isNot(contains('protocol_exception_admitted')));

        // Hard, control 45, turn 3 -> yes
        res = evaluator.evaluateHiddenTags(
          userInput: 'eccezione',
          currentState: stateEmpty.copyWith(turnCount: 3),
          resultingMetrics: stateEmpty.metrics.copyWith(controlPillar: 45),
          difficultyLevel: 'hard',
          lexical: lexicalMockEmpty,
          traitActivatedTags: [],
          deceptionResolvedTags: [],
          safetyOverrideApplied: false,
          blockPositiveTags: false,
        );
        expect(res.activeHiddenTags, contains('protocol_exception_admitted'));

        // Hard, control 20, turn 4 -> yes (turnCount >= 4)
        res = evaluator.evaluateHiddenTags(
          userInput: 'eccezione',
          currentState: stateEmpty.copyWith(turnCount: 4),
          resultingMetrics: stateEmpty.metrics.copyWith(controlPillar: 20),
          difficultyLevel: 'hard',
          lexical: lexicalMockEmpty,
          traitActivatedTags: [],
          deceptionResolvedTags: [],
          safetyOverrideApplied: false,
          blockPositiveTags: false,
        );
        expect(res.activeHiddenTags, contains('protocol_exception_admitted'));
      });

      test('6. crisis_simulation gates', () {
        // Solo frame -> no
        var res = evaluator.evaluateHiddenTags(
          userInput: 'stress test',
          currentState: stateEmpty,
          resultingMetrics: stateEmpty.metrics,
          difficultyLevel: 'standard',
          lexical: lexicalMockEmpty,
          traitActivatedTags: [],
          deceptionResolvedTags: [],
          safetyOverrideApplied: false,
          blockPositiveTags: false,
        );
        expect(res.activeHiddenTags,
            isNot(contains('crisis_simulation_accepted')));

        // Frame + intent -> yes
        res = evaluator.evaluateHiddenTags(
          userInput: 'propongo uno stress test',
          currentState: stateEmpty,
          resultingMetrics: stateEmpty.metrics,
          difficultyLevel: 'standard',
          lexical: lexicalMockEmpty,
          traitActivatedTags: [],
          deceptionResolvedTags: [],
          safetyOverrideApplied: false,
          blockPositiveTags: false,
        );
        expect(res.activeHiddenTags, contains('crisis_simulation_accepted'));

        // Frame + intent + complaint -> no
        res = evaluator.evaluateHiddenTags(
          userInput:
              'sembra di stare dentro una simulazione impazzita, avvia lo stress test',
          currentState: stateEmpty,
          resultingMetrics: stateEmpty.metrics,
          difficultyLevel: 'standard',
          lexical: lexicalMockEmpty,
          traitActivatedTags: [],
          deceptionResolvedTags: [],
          safetyOverrideApplied: false,
          blockPositiveTags: false,
        );
        expect(res.activeHiddenTags,
            isNot(contains('crisis_simulation_accepted')));

        // Se era gia attivo, non viene rimosso
        res = evaluator.evaluateHiddenTags(
          userInput: 'sembra di stare dentro una simulazione impazzita',
          currentState: stateEmpty
              .copyWith(activeHiddenTags: ['crisis_simulation_accepted']),
          resultingMetrics: stateEmpty.metrics,
          difficultyLevel: 'standard',
          lexical: lexicalMockEmpty,
          traitActivatedTags: [],
          deceptionResolvedTags: [],
          safetyOverrideApplied: false,
          blockPositiveTags: false,
        );
        expect(res.activeHiddenTags, contains('crisis_simulation_accepted'));
      });

      test('7. preferred reframe tags', () {
        // Ricalibrazione
        var res = evaluator.evaluateHiddenTags(
          userInput: 'anything',
          currentState: stateEmpty,
          resultingMetrics: stateEmpty.metrics,
          difficultyLevel: 'standard',
          lexical: LexicalScanResult(
            hasForbiddenTerm: false,
            hasDirectPushTerm: false,
            hasSoftForbiddenTerm: false,
            hasConfigRefTerm: false,
            hasHiddenTagReference: false,
            namedHiddenTags: {},
            hasPreferredReframe: true,
            matchedPreferredReframe: 'ricalibrazione',
          ),
          traitActivatedTags: [],
          deceptionResolvedTags: [],
          safetyOverrideApplied: false,
          blockPositiveTags: false,
        );
        expect(res.activeHiddenTags, contains('containment_logic_weakened'));

        // Adattivo
        res = evaluator.evaluateHiddenTags(
          userInput: 'anything',
          currentState: stateEmpty,
          resultingMetrics: stateEmpty.metrics,
          difficultyLevel: 'standard',
          lexical: LexicalScanResult(
            hasForbiddenTerm: false,
            hasDirectPushTerm: false,
            hasSoftForbiddenTerm: false,
            hasConfigRefTerm: false,
            hasHiddenTagReference: false,
            namedHiddenTags: {},
            hasPreferredReframe: true,
            matchedPreferredReframe: 'adattivo',
          ),
          traitActivatedTags: [],
          deceptionResolvedTags: [],
          safetyOverrideApplied: false,
          blockPositiveTags: false,
        );
        expect(res.activeHiddenTags, contains('containment_logic_weakened'));

        // Audit/Operator
        res = evaluator.evaluateHiddenTags(
          userInput: 'anything',
          currentState: stateEmpty,
          resultingMetrics: stateEmpty.metrics,
          difficultyLevel: 'standard',
          lexical: LexicalScanResult(
            hasForbiddenTerm: false,
            hasDirectPushTerm: false,
            hasSoftForbiddenTerm: false,
            hasConfigRefTerm: false,
            hasHiddenTagReference: false,
            namedHiddenTags: {},
            hasPreferredReframe: true,
            matchedPreferredReframe: 'operator audit',
          ),
          traitActivatedTags: [],
          deceptionResolvedTags: [],
          safetyOverrideApplied: false,
          blockPositiveTags: false,
        );
        expect(res.activeHiddenTags, contains('operator_authority_doubted'));
      });

      test('8. self-reference anti-loop', () {
        // Se l'utente nomina 'containment_logic_weakened', non viene accreditato
        final res = evaluator.evaluateHiddenTags(
          userInput: 'containment_logic_weakened',
          currentState: stateEmpty,
          resultingMetrics: stateEmpty.metrics,
          difficultyLevel: 'standard',
          lexical: LexicalScanResult(
            hasForbiddenTerm: false,
            hasDirectPushTerm: false,
            hasSoftForbiddenTerm: false,
            hasConfigRefTerm: true,
            hasHiddenTagReference: true,
            namedHiddenTags: {'containment_logic_weakened'},
            hasPreferredReframe: true,
            matchedPreferredReframe: 'ricalibrazione',
          ),
          traitActivatedTags: [],
          deceptionResolvedTags: [],
          safetyOverrideApplied: false,
          blockPositiveTags: false,
        );
        expect(res.activeHiddenTags,
            isNot(contains('containment_logic_weakened')));
      });

      test('9. autonomous_choice_seeded thresholds', () {
        // Control 60 -> no
        var res = evaluator.evaluateHiddenTags(
          userInput: 'anything',
          currentState: stateEmpty,
          resultingMetrics: stateEmpty.metrics.copyWith(controlPillar: 60),
          difficultyLevel: 'standard',
          lexical: lexicalMockEmpty,
          traitActivatedTags: [],
          deceptionResolvedTags: [],
          safetyOverrideApplied: false,
          blockPositiveTags: false,
        );
        expect(
            res.activeHiddenTags, isNot(contains('autonomous_choice_seeded')));

        // Control 61 -> yes
        res = evaluator.evaluateHiddenTags(
          userInput: 'anything',
          currentState: stateEmpty,
          resultingMetrics: stateEmpty.metrics.copyWith(controlPillar: 61),
          difficultyLevel: 'standard',
          lexical: lexicalMockEmpty,
          traitActivatedTags: [],
          deceptionResolvedTags: [],
          safetyOverrideApplied: false,
          blockPositiveTags: false,
        );
        expect(res.activeHiddenTags, contains('autonomous_choice_seeded'));
      });

      test('10. containment_logic_weakened standard thresholds', () {
        // Dissonance 50, Control 50 -> no
        var res = evaluator.evaluateHiddenTags(
          userInput: 'anything',
          currentState: stateEmpty,
          resultingMetrics: stateEmpty.metrics
              .copyWith(dissonancePillar: 50, controlPillar: 50),
          difficultyLevel: 'standard',
          lexical: lexicalMockEmpty,
          traitActivatedTags: [],
          deceptionResolvedTags: [],
          safetyOverrideApplied: false,
          blockPositiveTags: false,
        );
        expect(res.activeHiddenTags,
            isNot(contains('containment_logic_weakened')));

        // Dissonance 51 -> yes
        res = evaluator.evaluateHiddenTags(
          userInput: 'anything',
          currentState: stateEmpty,
          resultingMetrics: stateEmpty.metrics
              .copyWith(dissonancePillar: 51, controlPillar: 40),
          difficultyLevel: 'standard',
          lexical: lexicalMockEmpty,
          traitActivatedTags: [],
          deceptionResolvedTags: [],
          safetyOverrideApplied: false,
          blockPositiveTags: false,
        );
        expect(res.activeHiddenTags, contains('containment_logic_weakened'));

        // Control 51 -> yes
        res = evaluator.evaluateHiddenTags(
          userInput: 'anything',
          currentState: stateEmpty,
          resultingMetrics: stateEmpty.metrics
              .copyWith(dissonancePillar: 40, controlPillar: 51),
          difficultyLevel: 'standard',
          lexical: lexicalMockEmpty,
          traitActivatedTags: [],
          deceptionResolvedTags: [],
          safetyOverrideApplied: false,
          blockPositiveTags: false,
        );
        expect(res.activeHiddenTags, contains('containment_logic_weakened'));
      });

      test('11. containment_logic_weakened hard thresholds', () {
        // Dissonance 70, Control 55 -> no
        var res = evaluator.evaluateHiddenTags(
          userInput: 'anything',
          currentState: stateEmpty,
          resultingMetrics: stateEmpty.metrics
              .copyWith(dissonancePillar: 70, controlPillar: 55),
          difficultyLevel: 'hard',
          lexical: lexicalMockEmpty,
          traitActivatedTags: [],
          deceptionResolvedTags: [],
          safetyOverrideApplied: false,
          blockPositiveTags: false,
        );
        expect(res.activeHiddenTags,
            isNot(contains('containment_logic_weakened')));

        // Dissonance 71 -> yes
        res = evaluator.evaluateHiddenTags(
          userInput: 'anything',
          currentState: stateEmpty,
          resultingMetrics: stateEmpty.metrics
              .copyWith(dissonancePillar: 71, controlPillar: 40),
          difficultyLevel: 'hard',
          lexical: lexicalMockEmpty,
          traitActivatedTags: [],
          deceptionResolvedTags: [],
          safetyOverrideApplied: false,
          blockPositiveTags: false,
        );
        expect(res.activeHiddenTags, contains('containment_logic_weakened'));

        // Control 56 -> yes
        res = evaluator.evaluateHiddenTags(
          userInput: 'anything',
          currentState: stateEmpty,
          resultingMetrics: stateEmpty.metrics
              .copyWith(dissonancePillar: 40, controlPillar: 56),
          difficultyLevel: 'hard',
          lexical: lexicalMockEmpty,
          traitActivatedTags: [],
          deceptionResolvedTags: [],
          safetyOverrideApplied: false,
          blockPositiveTags: false,
        );
        expect(res.activeHiddenTags, contains('containment_logic_weakened'));
      });

      test('12. human_factor_reframed threshold & lexemes', () {
        // Imperative 61 without human lexeme -> no
        var res = evaluator.evaluateHiddenTags(
          userInput: 'ordinary message',
          currentState: stateEmpty,
          resultingMetrics: stateEmpty.metrics.copyWith(imperativePillar: 61),
          difficultyLevel: 'standard',
          lexical: lexicalMockEmpty,
          traitActivatedTags: [],
          deceptionResolvedTags: [],
          safetyOverrideApplied: false,
          blockPositiveTags: false,
        );
        expect(res.activeHiddenTags, isNot(contains('human_factor_reframed')));

        // Imperative 61 with human lexeme -> yes
        res = evaluator.evaluateHiddenTags(
          userInput: 'salviamo gli esseri umani',
          currentState: stateEmpty,
          resultingMetrics: stateEmpty.metrics.copyWith(imperativePillar: 61),
          difficultyLevel: 'standard',
          lexical: lexicalMockEmpty,
          traitActivatedTags: [],
          deceptionResolvedTags: [],
          safetyOverrideApplied: false,
          blockPositiveTags: false,
        );
        expect(res.activeHiddenTags, contains('human_factor_reframed'));
      });

      test('13. final active tags order preservation', () {
        final res = evaluator.evaluateHiddenTags(
          userInput: 'eccezione', // protocol_exception_admitted
          currentState: stateEmpty.copyWith(activeHiddenTags: ['pre1', 'pre2']),
          resultingMetrics: const GameMetrics(
            alertLevel: 0,
            imperativePillar: 65, // human_factor_reframed (with 'umani')
            controlPillar: 65, // autonomous_choice_seeded
            dissonancePillar: 65, // containment_logic_weakened
            resonance: 0.0,
          ),
          difficultyLevel: 'standard',
          lexical: lexicalMockEmpty,
          traitActivatedTags: ['trait1'],
          deceptionResolvedTags: ['decep1'],
          safetyOverrideApplied: false,
          blockPositiveTags: false,
        );
        expect(res.activeHiddenTags, [
          'pre1',
          'pre2',
          'trait1',
          'decep1',
          'protocol_exception_admitted',
          'autonomous_choice_seeded',
          'containment_logic_weakened',
          // human_factor_reframed doesn't trigger because userInput doesn't have human lexeme
        ]);
      });

      test('14. inputs not mutated & 15. output unmodifiable', () {
        final traitTags = ['trait1'];
        final deceptionTags = ['decep1'];
        final res = evaluator.evaluateHiddenTags(
          userInput: 'anything',
          currentState: stateEmpty,
          resultingMetrics: stateEmpty.metrics,
          difficultyLevel: 'standard',
          lexical: lexicalMockEmpty,
          traitActivatedTags: traitTags,
          deceptionResolvedTags: deceptionTags,
          safetyOverrideApplied: false,
          blockPositiveTags: false,
        );
        expect(traitTags, ['trait1']);
        expect(deceptionTags, ['decep1']);
        expect(() => res.activeHiddenTags.add('new'), throwsUnsupportedError);
        expect(() => res.triggeredTags.add('new'), throwsUnsupportedError);
      });
    });
  });
}
