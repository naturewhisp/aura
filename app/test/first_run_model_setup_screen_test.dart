import 'package:aura_app/src/screens/first_run_model_setup_screen.dart';
import 'package:aura_core/aura_offline.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final class FakeFirstRunModelSetupFacade implements FirstRunModelSetupFacade {
  FirstRunSetupState currentState = const FirstRunSetupState(
    step: FirstRunSetupStep.runtimeSelection,
  );
  bool failProbe = false;

  @override
  Future<FirstRunSetupState> acceptConsentAndBindActor(
      ExternalModelReference reference) async {
    currentState = const FirstRunSetupState(
      step: FirstRunSetupStep.evaluatorSelection,
    );
    return currentState;
  }

  @override
  Future<FirstRunSetupState> acceptConsentAndBindEvaluator(
      ExternalModelReference reference) async {
    currentState = const FirstRunSetupState(
      step: FirstRunSetupStep.complete,
    );
    return currentState;
  }

  @override
  Future<FirstRunSetupState> acceptConsentAndRetry({
    required ModelActivationRole role,
    required ExternalModelReference reference,
  }) async {
    if (role == ModelActivationRole.actor) {
      return acceptConsentAndBindActor(reference);
    } else {
      return acceptConsentAndBindEvaluator(reference);
    }
  }

  @override
  Future<FirstRunSetupState> configureRuntime(String executablePath) async {
    currentState = const FirstRunSetupState(
      step: FirstRunSetupStep.actorSelection,
    );
    return currentState;
  }

  @override
  Future<FirstRunSetupState> evaluateInitialState() async {
    return currentState;
  }

  @override
  Future<FirstRunSetupState> runFinalPreflight() async {
    if (failProbe) {
      currentState = const FirstRunSetupState(
        step: FirstRunSetupStep.failed,
        errorMessage:
            'Il probe processuale di llama-server è fallito: CUDA error.',
      );
    } else {
      currentState = const FirstRunSetupState(
        step: FirstRunSetupStep.complete,
      );
    }
    return currentState;
  }

  @override
  Future<FirstRunSetupState> selectActorModel(
      ConfiguredModelReference ref) async {
    currentState = const FirstRunSetupState(
      step: FirstRunSetupStep.consentRequired,
    );
    return currentState;
  }

  @override
  Future<FirstRunSetupState> selectEvaluatorModel(
      ConfiguredModelReference ref) async {
    currentState = const FirstRunSetupState(
      step: FirstRunSetupStep.complete,
    );
    return currentState;
  }
}

void main() {
  testWidgets(
      'FirstRunModelSetupScreen guida lo stepper: runtime -> actor -> consenso -> evaluator -> complete',
      (tester) async {
    final fakeFacade = FakeFirstRunModelSetupFacade();
    var isCompleted = false;

    await tester.pumpWidget(
      MaterialApp(
        home: FirstRunModelSetupScreen(
          firstRunFacade: fakeFacade,
          onComplete: () => isCompleted = true,
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    // 1. Passo Runtime Selection
    expect(find.text('PASSAGGIO 1: SELEZIONE RUNTIME LLAMA-SERVER'),
        findsOneWidget);
    await tester.enterText(
        find.byType(TextField), r'C:\llama.cpp\llama-server.exe');
    await tester.tap(find.text('CONFERMA RUNTIME'));
    await tester.pump();
    await tester.pump();

    // 2. Passo Actor Selection
    expect(
        find.text('PASSAGGIO 2: MODELLO ACTOR (PANOPTICON)'), findsOneWidget);
    await tester.enterText(find.byType(TextField), r'C:\Models\actor.gguf');
    await tester.tap(find.text('IMPOSTA MODELLO ACTOR'));
    await tester.pump();
    await tester.pump();

    // 3. Dialogo di consenso informato
    expect(find.text('Consenso Modello Esterno'), findsOneWidget);
    await tester.tap(find.text('ACCETTA E CONTINUA'));
    await tester.pump();
    await tester.pump();

    // 4. Passo Evaluator Selection
    expect(find.text('PASSAGGIO 3: MODELLO EVALUATOR (VALUTATORE)'),
        findsOneWidget);
    await tester.enterText(find.byType(TextField), r'C:\Models\evaluator.gguf');
    await tester.tap(find.text('IMPOSTA MODELLO EVALUATOR'));
    await tester.pump();
    await tester.pump();

    // 5. Passo Complete
    expect(find.text('CONFIGURAZIONE INFERENZA COMPLETA'), findsOneWidget);
    await tester.tap(find.text('PROSEGUI AL TERMINALE'));
    await tester.pump();
    await tester.pump();

    expect(isCompleted, isTrue);
  });

  testWidgets(
      'FirstRunModelSetupScreen gestisce il fallimento del probe finale',
      (tester) async {
    final fakeFacade = FakeFirstRunModelSetupFacade();
    fakeFacade.currentState = const FirstRunSetupState(
      step: FirstRunSetupStep.preflightCheck,
    );
    fakeFacade.failProbe = true;

    await tester.pumpWidget(
      MaterialApp(
        home: FirstRunModelSetupScreen(
          firstRunFacade: fakeFacade,
          onComplete: () {},
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(find.text('Verifica probe in corso...'), findsOneWidget);
    await tester.tap(find.text('AVVIA VERIFICA PROBE'));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('CUDA error'), findsOneWidget);
    expect(find.text('RITENTA CONFIGURAZIONE'), findsOneWidget);
  });
}
