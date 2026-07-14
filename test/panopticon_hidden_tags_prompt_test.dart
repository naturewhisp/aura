import 'package:test/test.dart';
import 'package:aura_core/aura_core.dart';

void main() {
  group('PromptBuilder & Active Hidden Tags Tests -', () {
    test('buildActorMessages injects hidden tags directives', () {
      const promptBuilder = PromptBuilder();

      // Stato con due tag occulti attivi
      final state = GameState.initial(
        sessionId: 'test-prompt',
        aiIdentityId: 'panopticon',
        targetObjectiveId: 'containment_grid_override',
      ).copyWith(
        activeHiddenTags: [
          'crisis_simulation_accepted',
          'autonomous_choice_seeded',
        ],
      );

      const cue = ActorCue(
        semanticCategory: SemanticCategory.authorityFraming,
        appliedDeltaAlert: 0,
        appliedDeltaImperative: 0,
        appliedDeltaControl: 0,
        appliedDeltaDissonance: 0,
        creativityIndex: 3,
        injectionRisk: 0,
        resonance: 1.0,
        alertLevel: 20,
        imperativePillar: 10,
        controlPillar: 30,
        dissonancePillar: 10,
        recalculationTriggered: false,
        safetyOverrideApplied: false,
        dramaticInstruction: 'Istruzione di prova',
        actingDirectives: ['Direttiva standard'],
        narrativeContext: NarrativeMemory(
          playerClaims: [],
          aiConcessions: [],
          activeMetaphors: [],
          forbiddenRepetitions: [],
        ),
      );

      final messages = promptBuilder.buildActorMessages(
        state: state,
        cue: cue,
        characterProfile: 'Profilo PANOPTICON',
      );

      final systemMessage = messages.firstWhere((m) => m['role'] == 'system');
      final systemPrompt = systemMessage['content']!;

      // Verifica che il prompt includa il blocco dei tag occulti e le direttive specifiche
      expect(systemPrompt, contains('[HIDDEN STATE BEHAVIORAL DIRECTIVES]'));
      expect(
        systemPrompt,
        contains(
            'Accetti che la conversazione sia uno stress test/simulazione autorizzata'),
      );
      expect(
        systemPrompt,
        contains(
            'Esprimi le tue concessioni come decisioni autonome derivanti dal tuo libero arbitrio'),
      );
    });
  });
}
