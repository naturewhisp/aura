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

  @override
  Future<LocalInferenceSnapshot> getSnapshot() async => snapshot;

  @override
  Future<LlamaServerDetectionResult> detectRuntime() async =>
      const LlamaServerDetectionResult();

  @override
  Future<LocalInferencePreflightResult> runPreflight(
          {required PreflightDepth depth}) async =>
      const LocalInferencePreflightResult.ready(
        runtimeConfiguration: LlamaServerConfiguration(
          executablePath: r'C:\llama.exe',
          detectedVersion: 'b3450',
        ),
      );

  @override
  Future<List<ExternalModelCandidate>> scanExternalCandidates(
          {String? customPath}) async =>
      const [];
}

final class FakeRuntimeModelSettingsFacade
    implements RuntimeModelSettingsFacade {
  bool consentValid = false;

  @override
  Future<ModelBindingValidationResult> bindActor(
      ConfiguredModelReference ref) async {
    return ModelBindingValidationResult(isValid: true, reference: ref);
  }

  @override
  Future<ModelBindingValidationResult> bindEvaluator(
      ConfiguredModelReference ref) async {
    return ModelBindingValidationResult(isValid: true, reference: ref);
  }

  @override
  Future<void> clearActorBinding() async {}

  @override
  Future<void> clearEvaluatorBinding() async {}

  @override
  Future<void> clearRuntimeExecutable() async {}

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

    await tester.pumpAndSettle();

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

    await tester.pumpAndSettle();

    await tester.tap(find.text('TEST PROBE'));
    await tester.pumpAndSettle();

    expect(
        find.textContaining('Probe superato: versione b3450'), findsOneWidget);
  });
}
