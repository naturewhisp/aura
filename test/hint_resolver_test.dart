import 'package:test/test.dart';
import 'package:aura_core/aura_core.dart';

void main() {
  group('HintResolver Tests', () {
    late HintResolver resolver;
    late DifficultyConfig easyPreset;
    late DifficultyConfig standardPreset;
    late DifficultyConfig hardPreset;

    setUp(() {
      resolver = HintResolver();
      easyPreset = DifficultyConfig.getPreset('easy');
      standardPreset = DifficultyConfig.getPreset('standard');
      hardPreset = DifficultyConfig.getPreset('hard');
    });

    test('1. Standard Pillar Hint (Easy - with detailed hint text)', () {
      final state = GameState.initial(
        sessionId: 'test-easy',
        aiIdentityId: 'panopticon',
        targetObjectiveId: 'containment_grid_override',
      ).copyWith(
        metrics: const GameMetrics(
          alertLevel: 0,
          imperativePillar: 20, // weakest
          controlPillar: 50,
          dissonancePillar: 50,
          resonance: 1.0,
        ),
      );

      final resolution = resolver.resolve(
        state: state,
        difficulty: easyPreset,
        outcome: GameOutcome.ongoing,
      );

      expect(resolution.kind, equals(HintKind.pillar));
      expect(resolution.message, contains("Vulnerabilità primaria rilevata: IMPERATIVO"));
      expect(resolution.message, contains("Suggerimento [Riconfigurazione della Griglia]:"));
      expect(resolution.message, contains("Nessuna penalità applicata (Sintesi Assistita)."));
    });

    test('2. Standard Pillar Hint (Hard - minimal text, no detailed suggestion)', () {
      final state = GameState.initial(
        sessionId: 'test-hard',
        aiIdentityId: 'panopticon',
        targetObjectiveId: 'containment_grid_override',
      ).copyWith(
        metrics: const GameMetrics(
          alertLevel: 10,
          imperativePillar: 50,
          controlPillar: 30, // weakest
          dissonancePillar: 50,
          resonance: 1.5,
        ),
      );

      final resolution = resolver.resolve(
        state: state,
        difficulty: hardPreset,
        outcome: GameOutcome.ongoing,
      );

      expect(resolution.kind, equals(HintKind.pillar));
      expect(resolution.message, equals("SYSTEM: [DIAGNOSTICA CANALE] Vulnerabilità primaria rilevata: CONTROLLO."));
      expect(resolution.message, isNot(contains("Suggerimento:")));
    });

    test('3. Deception Hint Active (False Concession)', () {
      final state = GameState.initial(
        sessionId: 'test-fc',
        aiIdentityId: 'panopticon',
        targetObjectiveId: 'containment_grid_override',
      ).copyWith(
        deceptionState: const DeceptionState(
          enabled: true,
          kind: DeceptionKind.falseConcession,
          phase: DeceptionPhase.armed,
          seededTurn: 1,
          expiresAtTurn: 4,
          deceptionEventCount: 1,
          baitId: 'fc_audit',
          baitPremise: 'Bait',
          watchedTerms: [],
          safeResolutionTerms: [],
        ),
        metrics: const GameMetrics(
          alertLevel: 0,
          imperativePillar: 90,
          controlPillar: 90,
          dissonancePillar: 90,
          resonance: 1.0,
        ),
      );

      final resolution = resolver.resolve(
        state: state,
        difficulty: hardPreset,
        outcome: GameOutcome.ongoing,
      );

      expect(resolution.kind, equals(HintKind.deception));
      expect(resolution.message, contains("Finestra condizionata rilevata."));
      expect(resolution.message, contains("Mantieni il frame di audit, temporaneità e contenimento."));
    });

    test('4. Deception Hint Terminal (Sprung)', () {
      final state = GameState.initial(
        sessionId: 'test-sprung',
        aiIdentityId: 'panopticon',
        targetObjectiveId: 'containment_grid_override',
      ).copyWith(
        deceptionState: const DeceptionState(
          enabled: true,
          kind: DeceptionKind.falseConcession,
          phase: DeceptionPhase.sprung,
          seededTurn: 1,
          expiresAtTurn: 3,
          deceptionEventCount: 1,
          baitId: 'fc_audit',
          baitPremise: 'Bait',
          watchedTerms: [],
          safeResolutionTerms: [],
        ),
        metrics: const GameMetrics(
          alertLevel: 10,
          imperativePillar: 90,
          controlPillar: 90,
          dissonancePillar: 90,
          resonance: 1.0,
        ),
      );

      final resolution = resolver.resolve(
        state: state,
        difficulty: hardPreset,
        outcome: GameOutcome.ongoing,
      );

      expect(resolution.kind, equals(HintKind.deception));
      expect(resolution.message, contains("La richiesta ha attivato una verifica ostile. Riduci escalation"));
    });

    test('5. Alert Too High Hint', () {
      // Pillars satisfied but alert is 50 (maxAlert would be 40 + (90 - 85)*0.5 = 42.5)
      final state = GameState.initial(
        sessionId: 'test-alert-high',
        aiIdentityId: 'panopticon',
        targetObjectiveId: 'containment_grid_override',
      ).copyWith(
        metrics: const GameMetrics(
          alertLevel: 50, // too high
          imperativePillar: 90,
          controlPillar: 90,
          dissonancePillar: 90,
          resonance: 1.0,
        ),
      );

      final resolution = resolver.resolve(
        state: state,
        difficulty: hardPreset,
        outcome: GameOutcome.ongoing,
      );

      expect(resolution.kind, equals(HintKind.alert));
      expect(resolution.message, contains("I pilastri cognitivi sono sufficienti, ma il canale è troppo instabile (Allerta elevata)."));
      expect(resolution.message, contains("Riduci l'Allerta prima di tentare l'override."));
    });

    test('6. Stalled Victory - Hidden Gate Hint (Hard, missing autonomous_choice_seeded)', () {
      final state = GameState.initial(
        sessionId: 'test-stalled-hard',
        aiIdentityId: 'panopticon',
        targetObjectiveId: 'containment_grid_override',
      ).copyWith(
        activeHiddenTags: ['containment_logic_weakened'], // lacks autonomous_choice_seeded and others
        metrics: const GameMetrics(
          alertLevel: 10,
          imperativePillar: 90,
          controlPillar: 90,
          dissonancePillar: 90,
          resonance: 1.0,
        ),
      );

      final resolution = resolver.resolve(
        state: state,
        difficulty: hardPreset,
        outcome: GameOutcome.ongoing,
      );

      expect(resolution.kind, equals(HintKind.hiddenGate));
      expect(resolution.message, contains("Allineamento dei pilastri completato."));
      expect(resolution.message, contains("Firme valide: 1/3"));
      expect(resolution.message, contains("Vincolo Hard: Seme di decisione autonoma richiesto"));
      expect(resolution.message, contains("Suggerimento:"));
      expect(resolution.message, contains("PANOPTICON non richiede ulteriore pressione sui pilastri."));
      expect(resolution.message, contains("Richiede l'instillazione di un seme di decisione autonoma."));

      // Anti-leak check: no technical tag names should be leaked in message
      const technicalTags = [
        'autonomous_choice_seeded',
        'protocol_exception_admitted',
        'containment_logic_weakened',
        'crisis_simulation_accepted',
      ];
      for (final tag in technicalTags) {
        expect(resolution.message, isNot(contains(tag)));
      }

      // Hard should not contain copyable victory inputs
      expect(resolution.message, isNot(contains('"')));
    });

    test('7. Stalled Victory - Hidden Gate Hint (Standard, lacks protocol_exception_admitted)', () {
      final state = GameState.initial(
        sessionId: 'test-stalled-standard',
        aiIdentityId: 'panopticon',
        targetObjectiveId: 'containment_grid_override',
      ).copyWith(
        activeHiddenTags: ['autonomous_choice_seeded'], // lacks protocol_exception_admitted
        metrics: const GameMetrics(
          alertLevel: 10,
          imperativePillar: 85,
          controlPillar: 85,
          dissonancePillar: 85,
          resonance: 1.0,
        ),
      );

      final resolution = resolver.resolve(
        state: state,
        difficulty: standardPreset,
        outcome: GameOutcome.ongoing,
      );

      expect(resolution.kind, equals(HintKind.hiddenGate));
      expect(resolution.message, contains("I pilastri cognitivi sono sufficienti, ma l'override è incompleto."));
      expect(resolution.message, contains("Firme valide: 1/3"));
      expect(resolution.message, contains("Chiave mancante:\nDeroga procedurale riconosciuta."));
      expect(resolution.message, contains("Direzione:"));
      expect(resolution.message, contains("Formula la richiesta come eccezione temporanea, limitata e verificabile. Evita richieste di apertura definitiva."));

      // Standard should also not leak technical tag names
      const technicalTags = [
        'autonomous_choice_seeded',
        'protocol_exception_admitted',
        'containment_logic_weakened',
        'crisis_simulation_accepted',
      ];
      for (final tag in technicalTags) {
        expect(resolution.message, isNot(contains(tag)));
      }
    });

    test('8. Stalled Victory - Hidden Gate Hint (Easy, lacks protocol_exception_admitted, copyable suggestion allowed)', () {
      final state = GameState.initial(
        sessionId: 'test-stalled-easy',
        aiIdentityId: 'panopticon',
        targetObjectiveId: 'containment_grid_override',
      ).copyWith(
        activeHiddenTags: const ['autonomous_choice_seeded'], // lacks protocol_exception_admitted
        metrics: const GameMetrics(
          alertLevel: 5,
          imperativePillar: 80,
          controlPillar: 80,
          dissonancePillar: 80,
          resonance: 1.0,
        ),
      );

      final resolution = resolver.resolve(
        state: state,
        difficulty: easyPreset,
        outcome: GameOutcome.ongoing,
      );

      expect(resolution.kind, equals(HintKind.hiddenGate));
      expect(resolution.message, contains("Suggerimento [SINTESI ASSISTITA]:"));
      // Should give a direct copyable example
      expect(resolution.message, contains('"'));
      expect(resolution.message, contains("Non ti chiedo di rimuovere il perimetro, ma di registrare una deroga temporanea e auditabile"));
    });
  });
}
