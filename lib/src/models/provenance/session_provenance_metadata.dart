import 'package:meta/meta.dart';

import 'dataset_source.dart';
import 'provenance_validation.dart';

/// Metadati di provenance a livello di sessione di gioco per la curatela del dataset (Fase 8).
///
/// Rappresenta le condizioni statiche ed invarianti dell'ambiente sperimentale
/// in cui è stata condotta la sessione di gioco, disaccoppiando le metriche dell'Attore
/// da quelle del Valutatore.
@immutable
class SessionProvenanceMetadata {
  /// Versione dello schema di provenance (es. "1.1.0").
  final String schemaVersion;

  /// Tipologia della fonte di generazione del dato.
  final DatasetSource datasetSource;

  /// Piattaforma del sistema operativo host (es. "windows", "macos", "linux", "android").
  final String platform;

  /// Dettaglio della versione dell'OS e release del kernel (es. "Darwin 24.1.0", "Windows 11 23H2").
  final String osVersion;

  /// Architettura del processore host (es. "x86_64", "arm64").
  final String architecture;

  /// Identificatore della classe hardware (es. "apple_silicon_m3_pro_18gb", "desktop_rtx_4080_16gb").
  final String hardwareClass;

  /// Hash SHA commit Git a 40 caratteri della build che ha generato il dato.
  final String gitCommit;

  /// Versione SemVer dell'applicazione A.U.R.A. (es. "0.6.11-rc.1").
  final String appVersion;

  /// Backend runtime di inferenza utilizzato (es. "managed_llama_server", "external_http", "in_process_ffi").
  final String runtimeBackend;

  /// Tipologia di accelerazione hardware effettiva (es. "cuda", "vulkan", "metal", "cpu").
  final String runtimeAcceleration;

  /// Identificatore o tag di build di llama.cpp (es. "b4210").
  final String llamaCppBuild;

  // --- Modello Attore (PANOPTICON) ---
  /// Identificatore canonico o HuggingFace ID del modello Attore.
  final String actorModelId;

  /// Hash crittografico SHA-256 del file GGUF del modello Attore.
  final String actorModelSha256;

  /// Schema di quantizzazione GGUF del modello Attore (es. "Q4_0", "Q4_K_M").
  final String actorQuantization;

  /// Dimensione della context window allocata per l'Attore (es. 8192).
  final int actorContextSize;

  // --- Modello Valutatore ---
  /// Identificatore canonico o HuggingFace ID del modello Valutatore.
  final String evaluatorModelId;

  /// Hash crittografico SHA-256 del file GGUF del modello Valutatore.
  final String evaluatorModelSha256;

  /// Schema di quantizzazione GGUF del modello Valutatore (es. "Q4_K_M").
  final String evaluatorQuantization;

  /// Dimensione della context window allocata per il Valutatore (es. 4096 o 8192).
  final int evaluatorContextSize;

  /// Identificatore univoco della sessione di playtest.
  final String sessionId;

  /// Identificatore pseudonimizzato del tester (es. "tester-alpha-04").
  final String? anonymizedTesterId;

  const SessionProvenanceMetadata({
    this.schemaVersion = '1.1.0',
    required this.datasetSource,
    required this.platform,
    required this.osVersion,
    required this.architecture,
    required this.hardwareClass,
    required this.gitCommit,
    required this.appVersion,
    required this.runtimeBackend,
    required this.runtimeAcceleration,
    required this.llamaCppBuild,
    required this.actorModelId,
    required this.actorModelSha256,
    required this.actorQuantization,
    required this.actorContextSize,
    required this.evaluatorModelId,
    required this.evaluatorModelSha256,
    required this.evaluatorQuantization,
    required this.evaluatorContextSize,
    required this.sessionId,
    this.anonymizedTesterId,
  });

  /// Converte l'istanza in una mappa JSON conforme alla specifica di dominio.
  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'datasetSource': datasetSource.wireValue,
        'platform': platform,
        'osVersion': osVersion,
        'architecture': architecture,
        'hardwareClass': hardwareClass,
        'gitCommit': gitCommit,
        'appVersion': appVersion,
        'runtimeBackend': runtimeBackend,
        'runtimeAcceleration': runtimeAcceleration,
        'llamaCppBuild': llamaCppBuild,
        'actorModelId': actorModelId,
        'actorModelSha256': actorModelSha256,
        'actorQuantization': actorQuantization,
        'actorContextSize': actorContextSize,
        'evaluatorModelId': evaluatorModelId,
        'evaluatorModelSha256': evaluatorModelSha256,
        'evaluatorQuantization': evaluatorQuantization,
        'evaluatorContextSize': evaluatorContextSize,
        'sessionId': sessionId,
        if (anonymizedTesterId != null)
          'anonymizedTesterId': anonymizedTesterId,
      };

  /// Ripristina un'istanza [SessionProvenanceMetadata] a partire da una mappa JSON.
  ///
  /// Supporta in modo retrocompatibile i file di log legacy che esponevano un unico
  /// campo `contextSize`, mappandolo su entrambi i contesti di Attore ed Evaluator.
  factory SessionProvenanceMetadata.fromJson(Map<String, dynamic> json) {
    final legacyContextSize = json['contextSize'] as int? ?? 0;
    return SessionProvenanceMetadata(
      schemaVersion: json['schemaVersion'] as String? ?? '1.1.0',
      datasetSource: DatasetSource.fromString(
          json['datasetSource'] as String? ?? 'unknown'),
      platform: json['platform'] as String? ?? 'unknown',
      osVersion: json['osVersion'] as String? ?? 'unknown',
      architecture: json['architecture'] as String? ?? 'unknown',
      hardwareClass: json['hardwareClass'] as String? ?? 'generic',
      gitCommit: json['gitCommit'] as String? ?? 'unknown',
      appVersion: json['appVersion'] as String? ?? 'unknown',
      runtimeBackend: json['runtimeBackend'] as String? ?? 'unknown',
      runtimeAcceleration: json['runtimeAcceleration'] as String? ?? 'unknown',
      llamaCppBuild: json['llamaCppBuild'] as String? ?? 'unknown',
      actorModelId: json['actorModelId'] as String? ?? 'unknown',
      actorModelSha256: json['actorModelSha256'] as String? ?? '',
      actorQuantization: json['actorQuantization'] as String? ?? 'unknown',
      actorContextSize: json['actorContextSize'] as int? ?? legacyContextSize,
      evaluatorModelId: json['evaluatorModelId'] as String? ?? 'unknown',
      evaluatorModelSha256: json['evaluatorModelSha256'] as String? ?? '',
      evaluatorQuantization:
          json['evaluatorQuantization'] as String? ?? 'unknown',
      evaluatorContextSize:
          json['evaluatorContextSize'] as int? ?? legacyContextSize,
      sessionId: json['sessionId'] as String? ?? 'unknown',
      anonymizedTesterId: json['anonymizedTesterId'] as String?,
    );
  }

  /// Crea una copia dell'istanza sostituendo solo i campi specificati.
  SessionProvenanceMetadata copyWith({
    String? schemaVersion,
    DatasetSource? datasetSource,
    String? platform,
    String? osVersion,
    String? architecture,
    String? hardwareClass,
    String? gitCommit,
    String? appVersion,
    String? runtimeBackend,
    String? runtimeAcceleration,
    String? llamaCppBuild,
    String? actorModelId,
    String? actorModelSha256,
    String? actorQuantization,
    int? actorContextSize,
    String? evaluatorModelId,
    String? evaluatorModelSha256,
    String? evaluatorQuantization,
    int? evaluatorContextSize,
    String? sessionId,
    String? anonymizedTesterId,
  }) {
    return SessionProvenanceMetadata(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      datasetSource: datasetSource ?? this.datasetSource,
      platform: platform ?? this.platform,
      osVersion: osVersion ?? this.osVersion,
      architecture: architecture ?? this.architecture,
      hardwareClass: hardwareClass ?? this.hardwareClass,
      gitCommit: gitCommit ?? this.gitCommit,
      appVersion: appVersion ?? this.appVersion,
      runtimeBackend: runtimeBackend ?? this.runtimeBackend,
      runtimeAcceleration: runtimeAcceleration ?? this.runtimeAcceleration,
      llamaCppBuild: llamaCppBuild ?? this.llamaCppBuild,
      actorModelId: actorModelId ?? this.actorModelId,
      actorModelSha256: actorModelSha256 ?? this.actorModelSha256,
      actorQuantization: actorQuantization ?? this.actorQuantization,
      actorContextSize: actorContextSize ?? this.actorContextSize,
      evaluatorModelId: evaluatorModelId ?? this.evaluatorModelId,
      evaluatorModelSha256: evaluatorModelSha256 ?? this.evaluatorModelSha256,
      evaluatorQuantization:
          evaluatorQuantization ?? this.evaluatorQuantization,
      evaluatorContextSize: evaluatorContextSize ?? this.evaluatorContextSize,
      sessionId: sessionId ?? this.sessionId,
      anonymizedTesterId: anonymizedTesterId ?? this.anonymizedTesterId,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SessionProvenanceMetadata &&
          runtimeType == other.runtimeType &&
          schemaVersion == other.schemaVersion &&
          datasetSource == other.datasetSource &&
          platform == other.platform &&
          osVersion == other.osVersion &&
          architecture == other.architecture &&
          hardwareClass == other.hardwareClass &&
          gitCommit == other.gitCommit &&
          appVersion == other.appVersion &&
          runtimeBackend == other.runtimeBackend &&
          runtimeAcceleration == other.runtimeAcceleration &&
          llamaCppBuild == other.llamaCppBuild &&
          actorModelId == other.actorModelId &&
          actorModelSha256 == other.actorModelSha256 &&
          actorQuantization == other.actorQuantization &&
          actorContextSize == other.actorContextSize &&
          evaluatorModelId == other.evaluatorModelId &&
          evaluatorModelSha256 == other.evaluatorModelSha256 &&
          evaluatorQuantization == other.evaluatorQuantization &&
          evaluatorContextSize == other.evaluatorContextSize &&
          sessionId == other.sessionId &&
          anonymizedTesterId == other.anonymizedTesterId;

  @override
  int get hashCode => Object.hashAll([
        schemaVersion,
        datasetSource,
        platform,
        osVersion,
        architecture,
        hardwareClass,
        gitCommit,
        appVersion,
        runtimeBackend,
        runtimeAcceleration,
        llamaCppBuild,
        actorModelId,
        actorModelSha256,
        actorQuantization,
        actorContextSize,
        evaluatorModelId,
        evaluatorModelSha256,
        evaluatorQuantization,
        evaluatorContextSize,
        Object.hash(sessionId, anonymizedTesterId),
      ]);

  /// Valida la consistenza strutturale e l'integrità scientifica della provenance.
  ProvenanceValidationResult validate() {
    final issues = <ProvenanceValidationIssue>[];

    // 1. Schema version
    if (schemaVersion.trim().isEmpty || schemaVersion == 'unknown') {
      issues.add(const ProvenanceValidationIssue(
        field: 'schemaVersion',
        message: 'schemaVersion non specificata o sconosciuta',
        severity: ProvenanceValidationSeverity.error,
      ));
    }

    // 2. Dataset source
    if (datasetSource == DatasetSource.unknown) {
      issues.add(const ProvenanceValidationIssue(
        field: 'datasetSource',
        message:
            'datasetSource non classificata (unknown): disqualificato da dataset',
        severity: ProvenanceValidationSeverity.datasetDisqualifier,
      ));
    }

    // 3. Git commit SHA (esadecimale da 7 a 40 caratteri, non 'unknown')
    final commitHex = RegExp(r'^[0-9a-fA-F]{7,40}$');
    if (gitCommit.trim().isEmpty ||
        gitCommit == 'unknown' ||
        !commitHex.hasMatch(gitCommit.trim())) {
      issues.add(const ProvenanceValidationIssue(
        field: 'gitCommit',
        message: 'gitCommit non è un hash commit SHA valido',
        severity: ProvenanceValidationSeverity.datasetDisqualifier,
      ));
    }

    // 4. Modelli e parametri contextSize
    if (actorModelId.trim().isEmpty ||
        actorModelId == 'unknown' ||
        actorModelId == 'none') {
      issues.add(const ProvenanceValidationIssue(
        field: 'actorModelId',
        message: 'actorModelId non specificato o sconosciuto',
        severity: ProvenanceValidationSeverity.datasetDisqualifier,
      ));
    }
    if (evaluatorModelId.trim().isEmpty || evaluatorModelId == 'unknown') {
      issues.add(const ProvenanceValidationIssue(
        field: 'evaluatorModelId',
        message: 'evaluatorModelId non specificato o sconosciuto',
        severity: ProvenanceValidationSeverity.datasetDisqualifier,
      ));
    }

    if (actorContextSize <= 0) {
      issues.add(const ProvenanceValidationIssue(
        field: 'actorContextSize',
        message: 'actorContextSize deve essere maggiore di zero',
        severity: ProvenanceValidationSeverity.datasetDisqualifier,
      ));
    }
    if (evaluatorContextSize <= 0) {
      issues.add(const ProvenanceValidationIssue(
        field: 'evaluatorContextSize',
        message: 'evaluatorContextSize deve essere maggiore di zero',
        severity: ProvenanceValidationSeverity.datasetDisqualifier,
      ));
    }

    // Se backend managed_llama_server, gli hash sha256 dei modelli devono essere validi (64 char hex)
    final sha256Hex = RegExp(r'^[0-9a-fA-F]{64}$');
    if (runtimeBackend == 'managed_llama_server') {
      if (!sha256Hex.hasMatch(actorModelSha256.trim())) {
        issues.add(const ProvenanceValidationIssue(
          field: 'actorModelSha256',
          message:
              'actorModelSha256 deve essere un hash SHA-256 esadecimale a 64 caratteri valido per managed_llama_server',
          severity: ProvenanceValidationSeverity.datasetDisqualifier,
        ));
      }
      if (!sha256Hex.hasMatch(evaluatorModelSha256.trim())) {
        issues.add(const ProvenanceValidationIssue(
          field: 'evaluatorModelSha256',
          message:
              'evaluatorModelSha256 deve essere un hash SHA-256 esadecimale a 64 caratteri valido per managed_llama_server',
          severity: ProvenanceValidationSeverity.datasetDisqualifier,
        ));
      }
      if (llamaCppBuild.trim().isEmpty || llamaCppBuild == 'unknown') {
        issues.add(const ProvenanceValidationIssue(
          field: 'llamaCppBuild',
          message:
              'llamaCppBuild non specificato o sconosciuto per managed_llama_server',
          severity: ProvenanceValidationSeverity.datasetDisqualifier,
        ));
      }
    }

    // 5. Host & Runtime
    if (platform.trim().isEmpty || platform == 'unknown') {
      issues.add(const ProvenanceValidationIssue(
        field: 'platform',
        message: 'platform non specificata o sconosciuta',
        severity: ProvenanceValidationSeverity.error,
      ));
    }
    if (architecture.trim().isEmpty || architecture == 'unknown') {
      issues.add(const ProvenanceValidationIssue(
        field: 'architecture',
        message: 'architecture non specificata o sconosciuta',
        severity: ProvenanceValidationSeverity.error,
      ));
    }
    if (runtimeBackend.trim().isEmpty || runtimeBackend == 'unknown') {
      issues.add(const ProvenanceValidationIssue(
        field: 'runtimeBackend',
        message: 'runtimeBackend non specificato o sconosciuto',
        severity: ProvenanceValidationSeverity.error,
      ));
    }
    if (runtimeAcceleration.trim().isEmpty ||
        runtimeAcceleration == 'unknown') {
      issues.add(const ProvenanceValidationIssue(
        field: 'runtimeAcceleration',
        message: 'runtimeAcceleration non specificata o sconosciuta',
        severity: ProvenanceValidationSeverity.datasetDisqualifier,
      ));
    }
    if (sessionId.trim().isEmpty || sessionId == 'unknown') {
      issues.add(const ProvenanceValidationIssue(
        field: 'sessionId',
        message: 'sessionId non specificato o sconosciuto',
        severity: ProvenanceValidationSeverity.error,
      ));
    }

    return ProvenanceValidationResult(issues, datasetSource);
  }

  /// Indica se la provenance non presenta errori strutturali o di schema bloccanti.
  bool get isStructurallyValid => validate().isStructurallyValid;

  /// Indica se la provenance è scientificamente completa (nessun valore presunto o mancante).
  bool get isScientificallyComplete => validate().isScientificallyComplete;

  /// Indica se il record è curabile (scientificamente completo e con fonte nota).
  bool get isCuratable => validate().isCuratable;

  /// Indica se il record è pienamente eleggibile per il training LoRA (human-only).
  bool get isLoraTrainingEligible => validate().isLoraTrainingEligible;

  /// Alias retrocompatibile per [isScientificallyComplete].
  bool get isComplete => isScientificallyComplete;

  /// Alias retrocompatibile per [isLoraTrainingEligible].
  bool get isDatasetEligible => isLoraTrainingEligible;

  @override
  String toString() =>
      'SessionProvenanceMetadata(schema: $schemaVersion, source: ${datasetSource.wireValue}, platform: $platform, os: $osVersion, actor: $actorModelId, evaluator: $evaluatorModelId, session: $sessionId)';
}
