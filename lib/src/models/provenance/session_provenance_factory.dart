import 'dart:io' as io;

import 'dataset_source.dart';
import 'session_provenance_metadata.dart';

/// Factory per la creazione e popolamento automatico dei metadati di provenance di sessione.
///
/// Ispeziona l'ambiente operativo corrente dell'host per rilevare piattaforma, versione OS
/// e architettura del processore, combinandoli con le informazioni del runtime di inferenza.
abstract final class SessionProvenanceFactory {
  /// Hash Git commit di fallback registrato al momento della compilazione.
  static const String defaultGitCommit = String.fromEnvironment(
    'AURA_GIT_COMMIT',
    defaultValue: '2fa8cea71c7263b65ef345f1b13ec1e89cf29900',
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
  static SessionProvenanceMetadata create({
    required String sessionId,
    required DatasetSource datasetSource,
    String? platform,
    String? osVersion,
    String? architecture,
    String? hardwareClass,
    String? gitCommit,
    String appVersion = '0.1.0',
    String runtimeBackend = 'managed_llama_server',
    String runtimeAcceleration = 'cpu',
    String llamaCppBuild = 'b4210',
    String actorModelId = 'google/gemma-4-12b-qat',
    String actorModelSha256 =
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
    String actorQuantization = 'Q4_0',
    int actorContextSize = 8192,
    String evaluatorModelId = 'mistralai/ministral-3-3b',
    String evaluatorModelSha256 =
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
    String evaluatorQuantization = 'Q4_K_M',
    int evaluatorContextSize = 4096,
    String? anonymizedTesterId,
  }) {
    final hostPlatform = platform ?? io.Platform.operatingSystem;
    final hostOsVersion = osVersion ?? io.Platform.operatingSystemVersion;
    final hostArch = architecture ?? detectArchitecture();

    String detectedHardwareClass = hardwareClass ?? 'generic';
    if (hardwareClass == null) {
      if (hostPlatform == 'macos') {
        detectedHardwareClass = 'apple_silicon_${hostArch}';
      } else if (hostPlatform == 'windows') {
        detectedHardwareClass = 'pc_windows_${hostArch}';
      } else {
        detectedHardwareClass = '${hostPlatform}_${hostArch}';
      }
    }

    return SessionProvenanceMetadata(
      schemaVersion: '1.1.0',
      datasetSource: datasetSource,
      platform: hostPlatform,
      osVersion: hostOsVersion,
      architecture: hostArch,
      hardwareClass: detectedHardwareClass,
      gitCommit: gitCommit ?? defaultGitCommit,
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
      sessionId: sessionId,
      anonymizedTesterId: anonymizedTesterId,
    );
  }
}
