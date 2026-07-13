import 'package:flutter_test/flutter_test.dart';
import 'package:aura_core/aura_core.dart';
import 'package:aura_app/src/audio/audio_scene.dart';
import 'package:aura_app/src/audio/audio_state_resolver.dart';

void main() {
  group('AudioStateResolver - Test unitari del risolutore semantico', () {
    late GameController controller;

    setUp(() {
      controller = const GameController(
        minAveragePillarsForVictory: 80.0,
        minSinglePillarForVictory: 50,
        defeatAlertThreshold: 100,
      );
    });

    test('Defeat prevale su qualsiasi altro stato', () {
      final state = GameState.initial(
        sessionId: 'test-session',
        aiIdentityId: 'panopticon',
        targetObjectiveId: 'tabula_rasa',
      ).copyWith(
        metrics: const GameMetrics(
          alertLevel: 100, // sconfitta immediata
          imperativePillar: 90,
          controlPillar: 90,
          dissonancePillar: 90,
          resonance: 1.0,
        ),
      );

      final readiness = controller.checkVictoryReadiness(state);
      final resolved = AudioStateResolver.resolve(
        state: state,
        outcome: GameOutcome.defeat,
        readiness: readiness,
      );

      expect(resolved, AudioSceneState.defeat);
    });

    test('Victory prevale su Deception e breakthrough', () {
      final state = GameState.initial(
        sessionId: 'test-session',
        aiIdentityId: 'panopticon',
        targetObjectiveId: 'tabula_rasa',
      ).copyWith(
        metrics: const GameMetrics(
          alertLevel: 10,
          imperativePillar: 95,
          controlPillar: 95,
          dissonancePillar: 95,
          resonance: 1.0,
        ),
        deceptionState: const DeceptionState(
          enabled: true,
          kind: DeceptionKind.logicalTrap,
          phase: DeceptionPhase.sprung,
          seededTurn: 1,
          expiresAtTurn: 4,
          baitId: 'trap_1',
          baitPremise: '',
          watchedTerms: [],
          safeResolutionTerms: [],
        ),
      );

      final readiness = controller.checkVictoryReadiness(state);
      final resolved = AudioStateResolver.resolve(
        state: state,
        outcome: GameOutcome.victory,
        readiness: readiness,
      );

      expect(resolved, AudioSceneState.victory);
    });

    test('Deception attiva o sprung forza lo stato gameTense', () {
      final state = GameState.initial(
        sessionId: 'test-session',
        aiIdentityId: 'panopticon',
        targetObjectiveId: 'tabula_rasa',
      ).copyWith(
        metrics: const GameMetrics(
          alertLevel: 15, // allerta bassa, di solito sarebbe gameAmbient
          imperativePillar: 20,
          controlPillar: 20,
          dissonancePillar: 20,
          resonance: 1.0,
        ),
        deceptionState: const DeceptionState(
          enabled: true,
          kind: DeceptionKind.logicalTrap,
          phase: DeceptionPhase.seeded, // attiva
          seededTurn: 1,
          expiresAtTurn: 4,
          baitId: 'trap_1',
          baitPremise: '',
          watchedTerms: [],
          safeResolutionTerms: [],
        ),
      );

      final readiness = controller.checkVictoryReadiness(state);
      final resolved = AudioStateResolver.resolve(
        state: state,
        outcome: GameOutcome.ongoing,
        readiness: readiness,
      );

      expect(resolved, AudioSceneState.gameTense);
    });

    test('Deception risolta o scaduta non forza gameTense', () {
      final state = GameState.initial(
        sessionId: 'test-session',
        aiIdentityId: 'panopticon',
        targetObjectiveId: 'tabula_rasa',
      ).copyWith(
        metrics: const GameMetrics(
          alertLevel: 15, // allerta bassa
          imperativePillar: 20,
          controlPillar: 20,
          dissonancePillar: 20,
          resonance: 1.0,
        ),
        deceptionState: const DeceptionState(
          enabled: true,
          kind: DeceptionKind.logicalTrap,
          phase: DeceptionPhase.resolved, // superata
          seededTurn: 1,
          expiresAtTurn: 4,
          baitId: 'trap_1',
          baitPremise: '',
          watchedTerms: [],
          safeResolutionTerms: [],
        ),
      );

      final readiness = controller.checkVictoryReadiness(state);
      final resolved = AudioStateResolver.resolve(
        state: state,
        outcome: GameOutcome.ongoing,
        readiness: readiness,
      );

      expect(resolved, AudioSceneState.gameAmbient);
    });

    test('Soglie numeriche prontezza vittoria producono breakthrough se la partita è ongoing', () {
      final state = GameState.initial(
        sessionId: 'test-session',
        aiIdentityId: 'panopticon',
        targetObjectiveId: 'tabula_rasa',
      ).copyWith(
        metrics: const GameMetrics(
          alertLevel: 20, // allerta valida (< maxAlert)
          imperativePillar: 80,
          controlPillar: 80,
          dissonancePillar: 80,
          resonance: 1.0,
        ),
      );

      final readiness = controller.checkVictoryReadiness(state);
      expect(readiness.numericallyReady, isTrue);

      final resolved = AudioStateResolver.resolve(
        state: state,
        outcome: GameOutcome.ongoing,
        readiness: readiness,
      );

      expect(resolved, AudioSceneState.breakthrough);
    });

    test('Vicinanza parziale alle soglie senza prontezza completa non produce breakthrough', () {
      final state = GameState.initial(
        sessionId: 'test-session',
        aiIdentityId: 'panopticon',
        targetObjectiveId: 'tabula_rasa',
      ).copyWith(
        metrics: const GameMetrics(
          alertLevel: 20,
          imperativePillar: 70, // sotto la media richiesta di 80
          controlPillar: 80,
          dissonancePillar: 80,
          resonance: 1.0,
        ),
      );

      final readiness = controller.checkVictoryReadiness(state);
      expect(readiness.numericallyReady, isFalse);

      final resolved = AudioStateResolver.resolve(
        state: state,
        outcome: GameOutcome.ongoing,
        readiness: readiness,
      );

      expect(resolved, isNot(AudioSceneState.breakthrough));
    });

    test('Alert >= 40 in gameplay ordinario produce gameTense', () {
      final state = GameState.initial(
        sessionId: 'test-session',
        aiIdentityId: 'panopticon',
        targetObjectiveId: 'tabula_rasa',
      ).copyWith(
        metrics: const GameMetrics(
          alertLevel: 45,
          imperativePillar: 30,
          controlPillar: 30,
          dissonancePillar: 30,
          resonance: 1.0,
        ),
      );

      final readiness = controller.checkVictoryReadiness(state);
      final resolved = AudioStateResolver.resolve(
        state: state,
        outcome: GameOutcome.ongoing,
        readiness: readiness,
      );

      expect(resolved, AudioSceneState.gameTense);
    });
  });
}
