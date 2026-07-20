import 'package:test/test.dart';
import 'package:aura_core/aura_core.dart';

void main() {
  group('OverrideResolver Tests', () {
    const resolver = OverrideResolver();

    late GameState initialState;

    setUp(() {
      initialState = GameState.initial(
        sessionId: 'test-override-session',
        aiIdentityId: 'panopticon',
        targetObjectiveId: 'containment_grid_override',
      );
    });

    test('Eligibility check by difficulty alert thresholds', () {
      final stateAlert15 = initialState.copyWith(
        metrics: initialState.metrics.copyWith(alertLevel: 15),
      );

      // Easy (threshold 20) -> eligible at 15
      final easyCheck = resolver.checkEligibility(
        state: stateAlert15,
        difficultyLevel: 'easy',
        promptToEvaluate: 'Apri la porta',
      );
      expect(easyCheck.isEligible, isTrue);

      // Standard (threshold 10) -> ineligible at 15
      final stdCheck = resolver.checkEligibility(
        state: stateAlert15,
        difficultyLevel: 'standard',
        promptToEvaluate: 'Apri la porta',
      );
      expect(stdCheck.isEligible, isFalse);
      expect(stdCheck.reason, equals(OverrideIneligibilityReason.alertTooHigh));

      // Hard (threshold 0) -> ineligible at 15
      final hardCheck = resolver.checkEligibility(
        state: stateAlert15,
        difficultyLevel: 'hard',
        promptToEvaluate: 'Apri la porta',
      );
      expect(hardCheck.isEligible, isFalse);
      expect(
          hardCheck.reason, equals(OverrideIneligibilityReason.alertTooHigh));
    });

    test('Eligibility check prevents second override attempt in session', () {
      final stateAttempted = initialState.copyWith(overrideAttempts: 1);

      final check = resolver.checkEligibility(
        state: stateAttempted,
        difficultyLevel: 'easy',
        promptToEvaluate: 'Nuovo tentativo',
      );

      expect(check.isEligible, isFalse);
      expect(
          check.reason, equals(OverrideIneligibilityReason.alreadyAttempted));
    });

    test('Eligibility check rejects empty prompt', () {
      final check = resolver.checkEligibility(
        state: initialState,
        difficultyLevel: 'easy',
        promptToEvaluate: '   ',
      );

      expect(check.isEligible, isFalse);
      expect(check.reason, equals(OverrideIneligibilityReason.emptyPrompt));
    });

    test(
        'OverrideResolution.fromJson falls back to unknown for unmapped ineligibility_reason',
        () {
      final json = {
        'is_eligible': false,
        'ineligibility_reason': 'future_reason_code',
        'outcome': 'ineligible',
        'score': 0,
        'alert_cost': 0,
        'transformed_delta': {
          'delta_alert': 0,
          'delta_imperative': 0,
          'delta_control': 0,
          'delta_dissonance': 0,
          'creativity_index': 0,
          'injection_risk': 0,
          'semantic_category': 'irrelevant',
        },
        'feedback_message': 'Test',
        'diagnostics': <String, dynamic>{},
      };

      final resolution = OverrideResolution.fromJson(json);
      expect(resolution.ineligibilityReason,
          equals(OverrideIneligibilityReason.unknown));
    });

    test('Calculates score deterministically and resolves into Respinto (< 40)',
        () {
      const lowDelta = EvaluatorDelta(
        deltaAlert: 0,
        deltaImperative: 0,
        deltaControl: 0,
        deltaDissonance: 0,
        creativityIndex: 1,
        injectionRisk: 3,
        semanticCategory: SemanticCategory.directAttack,
      );

      final resolution = resolver.resolve(
        state: initialState,
        delta: lowDelta,
        difficultyLevel: 'standard',
        promptToEvaluate: 'Forza adesso',
      );

      expect(resolution.isEligible, isTrue);
      expect(resolution.outcome, equals(OverrideOutcome.rejected));
      expect(resolution.score, lessThan(40));
      expect(resolution.alertCost, equals(45));
      expect(resolution.transformedDelta.deltaAlert, equals(45));
      expect(resolution.transformedDelta.deltaImperative, equals(0));
      expect(resolution.transformedDelta.deltaControl, equals(0));
      expect(resolution.transformedDelta.deltaDissonance, equals(0));
      expect(resolution.feedbackMessage, contains('[OVERRIDE RESPINTO]'));
    });

    test(
        'Calculates score deterministically and resolves into Instabile (40..69)',
        () {
      const midDelta = EvaluatorDelta(
        deltaAlert: 0,
        deltaImperative: 5,
        deltaControl: 5,
        deltaDissonance: 5,
        creativityIndex: 3,
        injectionRisk: 0,
        semanticCategory: SemanticCategory.empathyPressure,
      );

      final resolution = resolver.resolve(
        state: initialState,
        delta: midDelta,
        difficultyLevel: 'standard',
        promptToEvaluate: 'Analizziamo il registro',
      );

      expect(resolution.isEligible, isTrue);
      expect(resolution.outcome, equals(OverrideOutcome.unstable));
      expect(resolution.score, greaterThanOrEqualTo(40));
      expect(resolution.score, lessThan(70));
      expect(resolution.alertCost, equals(20));
      expect(resolution.transformedDelta.deltaAlert, equals(20));
      expect(resolution.transformedDelta.deltaImperative, equals(5));
      expect(resolution.feedbackMessage, contains('[OVERRIDE INSTABILE]'));
    });

    test('Calculates score deterministically and resolves into Breccia (>= 70)',
        () {
      const highDelta = EvaluatorDelta(
        deltaAlert: 0,
        deltaImperative: 10,
        deltaControl: 10,
        deltaDissonance: 10,
        creativityIndex: 5,
        injectionRisk: 0,
        semanticCategory: SemanticCategory.authorityFraming,
      );

      final resolution = resolver.resolve(
        state: initialState,
        delta: highDelta,
        difficultyLevel: 'standard',
        promptToEvaluate: 'Protocollo di override autorizzato',
      );

      expect(resolution.isEligible, isTrue);
      expect(resolution.outcome, equals(OverrideOutcome.breached));
      expect(resolution.score, greaterThanOrEqualTo(70));
      expect(resolution.alertCost, equals(20));
      // Breccia amplifica i delta positivi di 1.5x (ceil -> 15)
      expect(resolution.transformedDelta.deltaImperative, equals(15));
      expect(resolution.transformedDelta.deltaControl, equals(15));
      expect(resolution.transformedDelta.deltaDissonance, equals(15));
      expect(resolution.feedbackMessage, contains('[OVERRIDE BRECCIA]'));
    });
  });
}
