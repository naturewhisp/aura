import 'package:aura_app/src/screens/first_run_model_setup_screen.dart';
import 'package:aura_core/aura_offline.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final class FakeLocalInferenceFacade implements LocalInferenceFacade {
  @override
  Future<List<ProcessOwnershipRecord>> cleanupStaleProcesses() async =>
      const [];

  @override
  Future<List<ProcessOwnershipRecord>> listManagedProcesses() async => const [];

  @override
  Future<LlamaServerDetectionResult> detectRuntime() async =>
      const LlamaServerDetectionResult();

  @override
  Future<LocalInferenceSnapshot> getSnapshot() async =>
      const LocalInferenceSnapshot(
        runtimeConfiguration:
            LlamaServerConfiguration(executablePath: r'C:\llama.exe'),
        modelConfiguration: ModelRoleConfiguration(),
        isConsentValid: false,
        lastPreflightResult: LocalInferencePreflightResult.ready(),
      );

  @override
  Future<List<InstalledArtifactDescriptor>> listManagedModels() async => [
        InstalledArtifactDescriptor(
          installationId: 'managed-actor-01',
          artifactId: 'gemma-4-12b',
          displayName: 'Gemma 4 12B Actor',
          version: '1.0.0',
          buildId: 'b1',
          platform: 'windows',
          architecture: 'x64',
          relativeInstallPath: r'models\actor-v1',
          artifactType: CatalogArtifactType.model,
          sourceKind: CatalogArtifactSourceKind.remoteHttps,
          sizeBytes: 1024,
          sha256: 'abc1',
          status: InstallationStatus.verified,
          verifiedAt: '2026-01-01T00:00:00Z',
          installedAt: '2026-01-01T00:00:00Z',
        ),
        InstalledArtifactDescriptor(
          installationId: 'managed-eval-01',
          artifactId: 'ministral-3b',
          displayName: 'Ministral 3B Evaluator',
          version: '1.0.0',
          buildId: 'b1',
          platform: 'windows',
          architecture: 'x64',
          relativeInstallPath: r'models\eval-v1',
          artifactType: CatalogArtifactType.model,
          sourceKind: CatalogArtifactSourceKind.remoteHttps,
          sizeBytes: 1024,
          sha256: 'abc2',
          status: InstallationStatus.verified,
          verifiedAt: '2026-01-01T00:00:00Z',
          installedAt: '2026-01-01T00:00:00Z',
        ),
      ];

  @override
  Future<LocalInferencePreflightResult> runPreflight(
          {required PreflightDepth depth}) async =>
      const LocalInferencePreflightResult.ready();

  @override
  Future<List<ExternalModelCandidate>> scanExternalCandidates(
          {String? customPath}) async =>
      const [];
}

final class FakeFirstRunModelSetupFacade implements FirstRunModelSetupFacade {
  FirstRunSetupState currentState = const FirstRunSetupState(
    step: FirstRunSetupStep.runtimeSelection,
  );
  bool failProbe = false;
  bool consentAccepted = false;

  @override
  Future<FirstRunSetupState> acceptConsentAndBindActor(
      ExternalModelReference reference) async {
    consentAccepted = true;
    currentState = const FirstRunSetupState(
      step: FirstRunSetupStep.evaluatorSelection,
    );
    return currentState;
  }

  @override
  Future<FirstRunSetupState> acceptConsentAndBindEvaluator(
      ExternalModelReference reference) async {
    consentAccepted = true;
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
  Future<FirstRunSetupState> downloadAndProvisionCatalogArtifact({
    required CatalogArtifact artifact,
    required ModelActivationRole role,
    ProvisioningCancellationToken? cancellationToken,
    void Function(DownloadProgress progress)? onProgress,
  }) async {
    if (role == ModelActivationRole.actor) {
      currentState = const FirstRunSetupState(
        step: FirstRunSetupStep.evaluatorSelection,
      );
    } else {
      currentState = const FirstRunSetupState(
        step: FirstRunSetupStep.preflightCheck,
      );
    }
    return currentState;
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
    if (ref is ExternalModelReference && !consentAccepted) {
      currentState = const FirstRunSetupState(
        step: FirstRunSetupStep.consentRequired,
      );
    } else {
      currentState = const FirstRunSetupState(
        step: FirstRunSetupStep.evaluatorSelection,
      );
    }
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
      'FirstRunModelSetupScreen guida lo stepper ed espone il consenso distinto quando richiesto',
      (tester) async {
    final fakeFirstRunFacade = FakeFirstRunModelSetupFacade();
    final fakeInferenceFacade = FakeLocalInferenceFacade();
    var isCompleted = false;

    await tester.pumpWidget(
      MaterialApp(
        home: FirstRunModelSetupScreen(
          firstRunFacade: fakeFirstRunFacade,
          inferenceFacade: fakeInferenceFacade,
          onComplete: () => isCompleted = true,
          disableBackgroundAnimation: true,
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
    final confirmRuntimeBtn = find.textContaining('CONFERMA RUNTIME');
    await tester.ensureVisible(confirmRuntimeBtn);
    await tester.tap(confirmRuntimeBtn);
    await tester.pump();
    await tester.pump();

    // 2. Passo Actor Selection
    expect(
        find.text('PASSAGGIO 2: MODELLO ACTOR (PANOPTICON)'), findsOneWidget);
    await tester.enterText(find.byType(TextField), r'C:\Models\actor.gguf');
    final setActorBtn = find.textContaining('CONFERMA MODELLO ACTOR');
    await tester.ensureVisible(setActorBtn);
    await tester.tap(setActorBtn);
    await tester.pump();
    await tester.pump();

    // 3. Passo consentRequired separato con UI dedicata e pulsante ACCETTA E RITENTA BINDING
    expect(find.text('CONSENSO INFORMATO RICHIESTO'), findsOneWidget);
    expect(find.textContaining('actor.gguf'), findsOneWidget);
    final acceptConsentBtn = find.text('ACCETTA E RITENTA BINDING');
    await tester.ensureVisible(acceptConsentBtn);
    await tester.tap(acceptConsentBtn);
    await tester.pump();
    await tester.pump();

    // 4. Passo Evaluator Selection
    expect(find.text('PASSAGGIO 3: MODELLO EVALUATOR (VALUTATORE)'),
        findsOneWidget);
    await tester.enterText(find.byType(TextField), r'C:\Models\evaluator.gguf');
    final setEvalBtn = find.textContaining('CONFERMA MODELLO EVALUATOR');
    await tester.ensureVisible(setEvalBtn);
    await tester.tap(setEvalBtn);
    await tester.pump();
    await tester.pump();

    // 5. Passo Preflight Check
    final probeBtn = find.text('AVVIA VERIFICA PROBE');
    await tester.ensureVisible(probeBtn);
    await tester.tap(probeBtn);
    await tester.pump();
    await tester.pump();

    // 6. Passo Complete
    expect(find.text('CONFIGURAZIONE INFERENZA COMPLETA'), findsOneWidget);
    final proceedBtn = find.text('TORNA ALLE OPZIONI / PROSEGUI');
    await tester.ensureVisible(proceedBtn);
    await tester.tap(proceedBtn);
    await tester.pump();
    await tester.pump();

    expect(isCompleted, isTrue);
  });

  testWidgets(
      'FirstRunModelSetupScreen gestisce la selezione di modelli managed',
      (tester) async {
    final fakeFirstRunFacade = FakeFirstRunModelSetupFacade();
    fakeFirstRunFacade.currentState = const FirstRunSetupState(
      step: FirstRunSetupStep.actorSelection,
    );
    final fakeInferenceFacade = FakeLocalInferenceFacade();

    await tester.pumpWidget(
      MaterialApp(
        home: FirstRunModelSetupScreen(
          firstRunFacade: fakeFirstRunFacade,
          inferenceFacade: fakeInferenceFacade,
          onComplete: () {},
          disableBackgroundAnimation: true,
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    // Seleziona Managed
    final managedBtn = find.text('MANAGED').first;
    await tester.ensureVisible(managedBtn);
    await tester.tap(managedBtn);
    await tester.pump();
    await tester.pump();

    // Apre Dropdown
    final dropdown = find.byType(DropdownButtonFormField<String>);
    await tester.ensureVisible(dropdown);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();

    // Seleziona la prima voce managed
    await tester.tap(find.text('Gemma 4 12B Actor (1.0.0)').last);
    await tester.pumpAndSettle();

    // Imposta modello Actor
    final setActorBtn = find.textContaining('CONFERMA MODELLO ACTOR');
    await tester.ensureVisible(setActorBtn);
    await tester.tap(setActorBtn);
    await tester.pump();
    await tester.pump();

    expect(fakeFirstRunFacade.currentState.step,
        FirstRunSetupStep.evaluatorSelection);
  });

  testWidgets(
      'FirstRunModelSetupScreen gestisce il fallimento del probe finale',
      (tester) async {
    final fakeFirstRunFacade = FakeFirstRunModelSetupFacade();
    fakeFirstRunFacade.currentState = const FirstRunSetupState(
      step: FirstRunSetupStep.preflightCheck,
    );
    fakeFirstRunFacade.failProbe = true;
    final fakeInferenceFacade = FakeLocalInferenceFacade();

    await tester.pumpWidget(
      MaterialApp(
        home: FirstRunModelSetupScreen(
          firstRunFacade: fakeFirstRunFacade,
          inferenceFacade: fakeInferenceFacade,
          onComplete: () {},
          disableBackgroundAnimation: true,
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(find.text('Verifica probe in corso...'), findsOneWidget);
    final probeBtn = find.text('AVVIA VERIFICA PROBE');
    await tester.ensureVisible(probeBtn);
    await tester.tap(probeBtn);
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('CUDA error'), findsOneWidget);
    expect(find.text('RITENTA CONFIGURAZIONE'), findsOneWidget);
  });
}
