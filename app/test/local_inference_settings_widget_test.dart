import 'package:aura_app/src/settings/local_inference_settings_widget.dart';
import 'package:aura_core/aura_offline.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final class FakeLocalInferenceFacade implements LocalInferenceFacade {
  LocalInferenceSnapshot snapshot = const LocalInferenceSnapshot(
    runtimeConfiguration:
        LlamaServerConfiguration(executablePath: r'C:\llama.exe'),
    modelConfiguration: ModelRoleConfiguration(),
    isConsentValid: false,
    lastPreflightResult: LocalInferencePreflightResult.ready(),
  );

  List<InstalledArtifactDescriptor> managedModels = [
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

  bool shouldThrowOnPreflight = false;

  @override
  Future<LocalInferenceSnapshot> getSnapshot() async => snapshot;

  @override
  Future<LlamaServerDetectionResult> detectRuntime() async =>
      const LlamaServerDetectionResult();

  @override
  Future<LocalInferencePreflightResult> runPreflight(
      {required PreflightDepth depth}) async {
    if (shouldThrowOnPreflight) {
      throw Exception('Hardware failure during probe');
    }
    return const LocalInferencePreflightResult.ready(
      runtimeConfiguration: LlamaServerConfiguration(
        executablePath: r'C:\llama.exe',
        detectedVersion: 'b3450',
      ),
    );
  }

  @override
  Future<List<ExternalModelCandidate>> scanExternalCandidates(
          {String? customPath}) async =>
      const [];

  @override
  Future<List<InstalledArtifactDescriptor>> listManagedModels() async =>
      managedModels;
}

final class FakeRuntimeModelSettingsFacade
    implements RuntimeModelSettingsFacade {
  bool consentValid = false;
  bool actorCleared = false;
  bool evaluatorCleared = false;
  bool runtimeCleared = false;

  ConfiguredModelReference? boundActor;
  ConfiguredModelReference? boundEvaluator;

  @override
  Future<ModelBindingValidationResult> bindActor(
      ConfiguredModelReference ref) async {
    boundActor = ref;
    return ModelBindingValidationResult(isValid: true, reference: ref);
  }

  @override
  Future<ModelBindingValidationResult> bindEvaluator(
      ConfiguredModelReference ref) async {
    boundEvaluator = ref;
    return ModelBindingValidationResult(isValid: true, reference: ref);
  }

  @override
  Future<void> clearActorBinding() async {
    actorCleared = true;
    boundActor = null;
  }

  @override
  Future<void> clearEvaluatorBinding() async {
    evaluatorCleared = true;
    boundEvaluator = null;
  }

  @override
  Future<void> clearRuntimeExecutable() async {
    runtimeCleared = true;
  }

  @override
  Future<InstallationAssistance> getWinGetAssistance(
      {String? customPackageId}) async {
    return const InstallationAssistance(
      isWinGetAvailable: true,
      command: 'winget install ggerganov.llama.cpp',
      packageId: 'ggerganov.llama.cpp',
      requiresUserConfirmation: true,
    );
  }

  @override
  Future<bool> isConsentValid() async => consentValid;

  @override
  Future<bool> isWinGetAvailable() async => true;

  @override
  Future<ExternalModelConsent> recordConsent() async {
    consentValid = true;
    return ExternalModelConsent.now();
  }

  @override
  Future<LlamaServerConfiguration> setRuntimeExecutable(String path) async {
    return LlamaServerConfiguration(executablePath: path);
  }
}

void main() {
  testWidgets(
      'LocalInferenceSettingsWidget visualizza runtime e pulsanti azione',
      (tester) async {
    final inferenceFacade = FakeLocalInferenceFacade();
    final settingsFacade = FakeRuntimeModelSettingsFacade();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocalInferenceSettingsWidget(
            inferenceFacade: inferenceFacade,
            settingsFacade: settingsFacade,
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(find.text('Inferenza Locale (llama-server)'), findsOneWidget);
    expect(find.text('PRONTO'), findsOneWidget);
    expect(find.text('TEST PROBE'), findsOneWidget);
    expect(find.text('WINGET HELP'), findsOneWidget);
  });

  testWidgets(
      'LocalInferenceSettingsWidget esegue TEST PROBE e visualizza esito',
      (tester) async {
    final inferenceFacade = FakeLocalInferenceFacade();
    final settingsFacade = FakeRuntimeModelSettingsFacade();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocalInferenceSettingsWidget(
            inferenceFacade: inferenceFacade,
            settingsFacade: settingsFacade,
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    final probeBtn = find.text('TEST PROBE');
    await tester.ensureVisible(probeBtn);
    await tester.tap(probeBtn);
    await tester.pump();
    await tester.pump();

    expect(
        find.textContaining('Probe superato: versione b3450'), findsOneWidget);
  });

  testWidgets(
      'LocalInferenceSettingsWidget esegue rimozione di runtime, Actor ed Evaluator',
      (tester) async {
    final inferenceFacade = FakeLocalInferenceFacade();
    final settingsFacade = FakeRuntimeModelSettingsFacade();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocalInferenceSettingsWidget(
            inferenceFacade: inferenceFacade,
            settingsFacade: settingsFacade,
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    // Rimozione runtime
    await tester.tap(find.text('RIMUOVI RUNTIME'));
    await tester.pump();
    await tester.pump();
    expect(settingsFacade.runtimeCleared, isTrue);

    // Rimozione Actor (secondo pulsante RIMUOVI)
    final removeButtons = find.text('RIMUOVI');
    await tester.tap(removeButtons.at(0));
    await tester.pump();
    await tester.pump();
    expect(settingsFacade.actorCleared, isTrue);

    // Rimozione Evaluator (terzo pulsante RIMUOVI)
    await tester.tap(removeButtons.at(1));
    await tester.pump();
    await tester.pump();
    expect(settingsFacade.evaluatorCleared, isTrue);
  });

  testWidgets(
      'LocalInferenceSettingsWidget gestisce la selezione e il binding di modelli managed',
      (tester) async {
    final inferenceFacade = FakeLocalInferenceFacade();
    final settingsFacade = FakeRuntimeModelSettingsFacade();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocalInferenceSettingsWidget(
            inferenceFacade: inferenceFacade,
            settingsFacade: settingsFacade,
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    // Passa Actor a MANAGED
    await tester.tap(find.text('MANAGED').first);
    await tester.pump();
    await tester.pump();

    // Apre il dropdown Actor managed
    await tester.tap(find.byKey(const Key('actor_managed_dropdown')));
    await tester.pumpAndSettle();

    // Seleziona la voce Gemma 4 12B
    await tester.tap(find.text('Gemma 4 12B Actor (1.0.0)').last);
    await tester.pumpAndSettle();

    // Salva binding Actor managed
    final saveButtons = find.text('SALVA');
    await tester.tap(saveButtons.at(0));
    await tester.pump();
    await tester.pump();

    expect(settingsFacade.boundActor, isA<ManagedModelReference>());
    expect((settingsFacade.boundActor as ManagedModelReference).installationId,
        'managed-actor-01');
  });

  testWidgets(
      'LocalInferenceSettingsWidget non va in crash su dispose asincrono durante probe',
      (tester) async {
    final inferenceFacade = FakeLocalInferenceFacade();
    final settingsFacade = FakeRuntimeModelSettingsFacade();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocalInferenceSettingsWidget(
            inferenceFacade: inferenceFacade,
            settingsFacade: settingsFacade,
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    final probeBtn = find.text('TEST PROBE');
    await tester.ensureVisible(probeBtn);
    await tester.tap(probeBtn);
    await tester.pump(); // In-flight

    // Smonta il widget immediatamente
    await tester.pumpWidget(const SizedBox.shrink());
    await tester
        .pump(); // Completa senza lanciare setState() chiamato dopo dispose
  });

  testWidgets(
      'LocalInferenceSettingsWidget si adatta a viewport stretta senza overflow',
      (tester) async {
    tester.view.physicalSize = const Size(400, 500);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final inferenceFacade = FakeLocalInferenceFacade();
    final settingsFacade = FakeRuntimeModelSettingsFacade();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocalInferenceSettingsWidget(
            inferenceFacade: inferenceFacade,
            settingsFacade: settingsFacade,
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
