import 'dart:io' as io;

import 'dataset_source.dart';
import 'session_provenance_metadata.dart';

/// Factory per la creazione e popolamento automatico dei metadati di provenance di sessione.
///
/// Ispeziona l'ambiente operativo corrente dell'host per rilevare piattaforma, versione OS
/// e architettura del processore, combinandoli con le informazioni del runtime di inferenza.
abstract final class SessionProvenanceFactory {
  /// Hash Git commit di fallback registrato al momento della compilazione.
  /// Se non impostato tramite `--dart-define=AURA_GIT_COMMIT=...`, vale 'unknown'.
  static const String defaultGitCommit = String.fromEnvironment(
    'AURA_GIT_COMMIT',
    defaultValue: 'unknown',
  );

  /// Versione applicativa di fallback registrata al momento della compilazione.
  /// Se non impostata tramite `--dart-define=AURA_APP_VERSION=...`, vale 'unknown'.
  static const String defaultAppVersion = String.fromEnvironment(
    'AURA_APP_VERSION',
    defaultValue: 'unknown',
  );

  /// Rileva l'architettura della CPU host in modo normalizzato.
  static String detectArchitecture() {
    final version = io.Platform.version.toLowerCase();
    if (version.contains('arm64') || version.contains('aarch64')) {
      return 'arm64';
    }
    if (version.contains('x64') || version.contains('x86_64')) {
      return 'x86_64';
    }
    return io.Platform.operatingSystem == 'macos' ? 'arm64' : 'x86_64';
  }

  /// Crea un'istanza [SessionProvenanceMetadata] pre-compilata con i dati ambientali dell'host.
  ///
  /// In assenza di valori espliciti o misurati per commit, versione, backend, accelerazione, build,
  /// modelli, quantizzazioni o dimensioni di contesto, tutti i campi assumono rigorosamente
  /// il valore fail-closed 'unknown', stringa vuota o zero per garantire l'integrità scientifica.
  static SessionProvenanceMetadata create({
    required String sessionId,
    required DatasetSource datasetSource,
    String? platform,
    String? osVersion,
    String? architecture,
    String? hardwareClass,
    String? gitCommit,
    String appVersion = 'unknown',
    String runtimeBackend = 'unknown',
    String runtimeAcceleration = 'unknown',
    String llamaCppBuild = 'unknown',
    String actorModelId = 'unknown',
    String actorModelSha256 = '',
    String actorQuantization = 'unknown',
    int actorContextSize = 0,
    String evaluatorModelId = 'unknown',
    String evaluatorModelSha256 = '',
    String evaluatorQuantization = 'unknown',
    int evaluatorContextSize = 0,
    String? anonymizedTesterId,
  }) {
    final hostPlatform = platform ?? io.Platform.operatingSystem;
    final hostOsVersion = osVersion ?? io.Platform.operatingSystemVersion;
    final hostArch = architecture ?? detectArchitecture();

    String detectedHardwareClass = hardwareClass ?? 'unknown';
    if (hardwareClass == null) {
      if (hostPlatform == 'macos') {
        detectedHardwareClass = 'apple_silicon_${hostArch}';
      } else if (hostPlatform == 'windows') {
        detectedHardwareClass = 'pc_windows_${hostArch}';
      } else if (hostPlatform != 'unknown') {
        detectedHardwareClass = '${hostPlatform}_${hostArch}';
      }
    }

    final resolvedGitCommit = gitCommit ?? defaultGitCommit;
    final resolvedAppVersion =
        appVersion != 'unknown' ? appVersion : defaultAppVersion;

    return SessionProvenanceMetadata(
      schemaVersion: '1.1.0',
      datasetSource: datasetSource,
      platform: hostPlatform,
      osVersion: hostOsVersion,
      architecture: hostArch,
      hardwareClass: detectedHardwareClass,
      gitCommit: resolvedGitCommit,
      appVersion: resolvedAppVersion,
      runtimeBackend: runtimeBackend,
      runtimeAcceleration: runtimeAcceleration,
      llamaCppBuild: llamaCppBuild,
      actorModelId: actorModelId,
      actorModelSha256: actorModelSha256,
      actorQuantization: actorQuantization,
      actorContextSize: actorContextSize,
      evaluatorModelId: evaluatorModelId,
      evaluatorModelSha256: evaluatorModelSha256,
      evaluatorQuantization: evaluatorQuantization,
      evaluatorContextSize: evaluatorContextSize,
      sessionId: sessionId,
      anonymizedTesterId: anonymizedTesterId,
    );
  }

  /// Alias semantico per [create] che esplicita la creazione di una provenance incompleta in fase di bootstrap.
  static SessionProvenanceMetadata createIncomplete({
    required String sessionId,
    required DatasetSource datasetSource,
    String? platform,
    String? osVersion,
    String? architecture,
    String? hardwareClass,
    String? gitCommit,
    String appVersion = 'unknown',
    String runtimeBackend = 'unknown',
    String runtimeAcceleration = 'unknown',
    String llamaCppBuild = 'unknown',
    String actorModelId = 'unknown',
    String actorModelSha256 = '',
    String actorQuantization = 'unknown',
    int actorContextSize = 0,
    String evaluatorModelId = 'unknown',
    String evaluatorModelSha256 = '',
    String evaluatorQuantization = 'unknown',
    int evaluatorContextSize = 0,
    String? anonymizedTesterId,
  }) =>
      create(
        sessionId: sessionId,
        datasetSource: datasetSource,
        platform: platform,
        osVersion: osVersion,
        architecture: architecture,
        hardwareClass: hardwareClass,
        gitCommit: gitCommit,
        appVersion: appVersion,
        runtimeBackend: runtimeBackend,
        runtimeAcceleration: runtimeAcceleration,
        llamaCppBuild: llamaCppBuild,
        actorModelId: actorModelId,
        actorModelSha256: actorModelSha256,
        actorQuantization: actorQuantization,
        actorContextSize: actorContextSize,
        evaluatorModelId: evaluatorModelId,
        evaluatorModelSha256: evaluatorModelSha256,
        evaluatorQuantization: evaluatorQuantization,
        evaluatorContextSize: evaluatorContextSize,
        anonymizedTesterId: anonymizedTesterId,
      );

  /// Crea un'istanza [SessionProvenanceMetadata] a partire da osservazioni certe e verificate di runtime.
  static SessionProvenanceMetadata fromRuntimeObservation({
    required String sessionId,
    required DatasetSource datasetSource,
    required String runtimeBackend,
    required String runtimeAcceleration,
    required String llamaCppBuild,
    required String actorModelId,
    required String actorModelSha256,
    required String actorQuantization,
    required int actorContextSize,
    required String evaluatorModelId,
    required String evaluatorModelSha256,
    required String evaluatorQuantization,
    required int evaluatorContextSize,
    required String appVersion,
    String? platform,
    String? osVersion,
    String? architecture,
    String? hardwareClass,
    String? gitCommit,
    String? anonymizedTesterId,
  }) =>
      create(
        sessionId: sessionId,
        datasetSource: datasetSource,
        platform: platform,
        osVersion: osVersion,
        architecture: architecture,
        hardwareClass: hardwareClass,
        gitCommit: gitCommit,
        appVersion: appVersion,
        runtimeBackend: runtimeBackend,
        runtimeAcceleration: runtimeAcceleration,
        llamaCppBuild: llamaCppBuild,
        actorModelId: actorModelId,
        actorModelSha256: actorModelSha256,
        actorQuantization: actorQuantization,
        actorContextSize: actorContextSize,
        evaluatorModelId: evaluatorModelId,
        evaluatorModelSha256: evaluatorModelSha256,
        evaluatorQuantization: evaluatorQuantization,
        evaluatorContextSize: evaluatorContextSize,
        anonymizedTesterId: anonymizedTesterId,
      );
}
