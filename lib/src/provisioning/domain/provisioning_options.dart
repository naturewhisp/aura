import 'package:meta/meta.dart';
import 'json_safe_value.dart';

/// Policy applicativa per la gestione del download di artefatti remoti.
enum ProvisioningDownloadPolicy {
  neverDownload,
  explicitConsent;

  static ProvisioningDownloadPolicy parse(String value) {
    for (final policy in ProvisioningDownloadPolicy.values) {
      if (policy.name == value.trim()) {
        return policy;
      }
    }
    throw ProvisioningException(
      reason: ProvisioningFailureReason.catalogMalformed,
      message: 'ProvisioningDownloadPolicy non valida: "$value".',
    );
  }
}

/// Policy applicativa per la gestione dei conflitti di installazione.
enum ProvisioningConflictPolicy {
  fail,
  returnAlreadyInstalled;
}

/// Consenso esplicito per l'esecuzione di un singolo download remoto.
@immutable
final class DownloadConsent {
  final String artifactId;
  final String sourceUri;
  final int expectedSizeBytes;
  final String operationId;

  const DownloadConsent._({
    required this.artifactId,
    required this.sourceUri,
    required this.expectedSizeBytes,
    required this.operationId,
  });

  factory DownloadConsent.grantedFor({
    required String artifactId,
    required String sourceUri,
    required int expectedSizeBytes,
    required String operationId,
  }) {
    if (artifactId.isEmpty || sourceUri.isEmpty || operationId.isEmpty) {
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.consentMissing,
        message: 'I campi del consenso al download non possono essere vuoti.',
      );
    }
    if (expectedSizeBytes <= 0) {
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.consentMissing,
        message: 'expectedSizeBytes deve essere maggiore di zero.',
      );
    }
    return DownloadConsent._(
      artifactId: artifactId,
      sourceUri: sourceUri,
      expectedSizeBytes: expectedSizeBytes,
      operationId: operationId,
    );
  }

  bool isValidFor({
    required String targetArtifactId,
    required String targetSourceUri,
    required int targetSizeBytes,
    required String targetOperationId,
  }) {
    return artifactId == targetArtifactId &&
        sourceUri == targetSourceUri &&
        expectedSizeBytes == targetSizeBytes &&
        operationId == targetOperationId;
  }
}

/// Origine dell'artefatto da installare.
enum ProvisioningSourceKind {
  bundled,
  remoteHttps,
  localImport;
}

/// Stato finale dell'operazione di provisioning.
enum ProvisioningStatus {
  success,
  alreadyInstalled,
  failed,
  cancelled;
}

/// Discriminatore tipizzato delle possibili cause di fallimento del provisioning.
enum ProvisioningFailureReason {
  catalogNotFound,
  catalogMalformed,
  unsupportedSchemaVersion,
  invalidCatalog,
  artifactIdNotFound,
  unsupportedArtifactType,
  unsupportedPlatform,
  unsupportedArchitecture,
  invalidSourceUri,
  downloadNotAllowed,
  consentMissing,
  downloadFailed,
  redirectRejected,
  downloadTimeout,
  sizeLimitExceeded,
  sizeMismatch,
  hashMismatch,
  stagingCreationFailed,
  extractionFailed,
  unsafeArchiveEntry,
  installationConflict,
  atomicMoveFailed,
  installationRecordReadFailed,
  installationRecordWriteFailed,
  activationStateReadFailed,
  activationStateWriteFailed,
  incompatibleRuntimeAndModel,
  artifactNotVerified,
  rollbackFailed,
  cleanupFailed,
  operationCancelled,
  unexpectedState,
  installationNotFound;
}

/// Richiesta formale di provisioning inviata dal chiamante applicativo.
@immutable
final class ProvisioningRequest {
  final String operationId;
  final String catalogId;
  final String artifactId;
  final ProvisioningDownloadPolicy downloadPolicy;
  final DownloadConsent? consent;
  final String expectedPlatform;
  final String expectedArchitecture;
  final String? customSourcePath;
  final ProvisioningConflictPolicy conflictPolicy;

  const ProvisioningRequest({
    required this.operationId,
    required this.catalogId,
    required this.artifactId,
    this.downloadPolicy = ProvisioningDownloadPolicy.neverDownload,
    this.consent,
    required this.expectedPlatform,
    required this.expectedArchitecture,
    this.customSourcePath,
    this.conflictPolicy = ProvisioningConflictPolicy.fail,
  });
}

/// Risultato sintetico restituto da un'operazione di provisioning.
@immutable
final class ProvisioningResult {
  final String operationId;
  final String artifactId;
  final ProvisioningStatus status;
  final String? installationId;
  final bool installed;
  final bool alreadyInstalled;
  final bool activated;
  final bool verified;
  final int bytesProcessed;
  final ProvisioningSourceKind sourceKind;
  final bool rollbackPerformed;
  final bool cleanupSucceeded;
  final ProvisioningFailureReason? failureReason;
  final Map<String, dynamic> sanitizedDiagnostics;

  ProvisioningResult({
    required this.operationId,
    required this.artifactId,
    required this.status,
    this.installationId,
    this.installed = false,
    this.alreadyInstalled = false,
    this.activated = false,
    this.verified = false,
    this.bytesProcessed = 0,
    required this.sourceKind,
    this.rollbackPerformed = false,
    this.cleanupSucceeded = true,
    this.failureReason,
    Map<String, dynamic> sanitizedDiagnostics = const {},
  }) : sanitizedDiagnostics =
            JsonSafeValue.ensureJsonSafeMap(sanitizedDiagnostics);

  factory ProvisioningResult.success({
    required String operationId,
    required String artifactId,
    required String installationId,
    required ProvisioningSourceKind sourceKind,
    required int bytesProcessed,
    bool activated = false,
    bool alreadyInstalled = false,
  }) {
    return ProvisioningResult(
      operationId: operationId,
      artifactId: artifactId,
      status: alreadyInstalled
          ? ProvisioningStatus.alreadyInstalled
          : ProvisioningStatus.success,
      installationId: installationId,
      installed: !alreadyInstalled,
      alreadyInstalled: alreadyInstalled,
      activated: activated,
      verified: true,
      bytesProcessed: bytesProcessed,
      sourceKind: sourceKind,
    );
  }

  factory ProvisioningResult.failure({
    required String operationId,
    required String artifactId,
    required ProvisioningSourceKind sourceKind,
    required ProvisioningFailureReason failureReason,
    String? sanitizedMessage,
    bool rollbackPerformed = false,
    bool cleanupSucceeded = true,
  }) {
    return ProvisioningResult(
      operationId: operationId,
      artifactId: artifactId,
      status: ProvisioningStatus.failed,
      sourceKind: sourceKind,
      failureReason: failureReason,
      rollbackPerformed: rollbackPerformed,
      cleanupSucceeded: cleanupSucceeded,
      sanitizedDiagnostics: {
        if (sanitizedMessage != null) 'message': sanitizedMessage,
        'failureReason': failureReason.name,
      },
    );
  }

  ProvisioningResult copyWith({
    String? operationId,
    String? artifactId,
    ProvisioningStatus? status,
    String? installationId,
    bool? installed,
    bool? alreadyInstalled,
    bool? activated,
    bool? verified,
    int? bytesProcessed,
    ProvisioningSourceKind? sourceKind,
    bool? rollbackPerformed,
    bool? cleanupSucceeded,
    ProvisioningFailureReason? failureReason,
    Map<String, dynamic>? sanitizedDiagnostics,
  }) {
    return ProvisioningResult(
      operationId: operationId ?? this.operationId,
      artifactId: artifactId ?? this.artifactId,
      status: status ?? this.status,
      installationId: installationId ?? this.installationId,
      installed: installed ?? this.installed,
      alreadyInstalled: alreadyInstalled ?? this.alreadyInstalled,
      activated: activated ?? this.activated,
      verified: verified ?? this.verified,
      bytesProcessed: bytesProcessed ?? this.bytesProcessed,
      sourceKind: sourceKind ?? this.sourceKind,
      rollbackPerformed: rollbackPerformed ?? this.rollbackPerformed,
      cleanupSucceeded: cleanupSucceeded ?? this.cleanupSucceeded,
      failureReason: failureReason ?? this.failureReason,
      sanitizedDiagnostics: sanitizedDiagnostics ?? this.sanitizedDiagnostics,
    );
  }

  bool get isSuccess =>
      status == ProvisioningStatus.success ||
      status == ProvisioningStatus.alreadyInstalled;

  String? get sanitizedMessage => sanitizedDiagnostics['message'] as String?;

  Map<String, dynamic> toJson() => {
        'operationId': operationId,
        'artifactId': artifactId,
        'status': status.name,
        if (installationId != null) 'installationId': installationId,
        'installed': installed,
        'alreadyInstalled': alreadyInstalled,
        'activated': activated,
        'verified': verified,
        'bytesProcessed': bytesProcessed,
        'sourceKind': sourceKind.name,
        'rollbackPerformed': rollbackPerformed,
        'cleanupSucceeded': cleanupSucceeded,
        if (failureReason != null) 'failureReason': failureReason!.name,
        'sanitizedDiagnostics': sanitizedDiagnostics,
      };
}

/// Cause tipizzate di fallimento dell'attivazione di un'installazione.
enum ActivationFailureReason {
  installationNotFound,
  installationNotVerified,
  physicalArtifactMissing,
  integrityVerificationFailed,
  activationPersistenceFailed,
  operationCancelled,
}

/// Risultato dell'operazione di attivazione di un'installazione.
@immutable
final class ActivationResult {
  final String operationId;
  final String installationId;
  final bool success;
  final String? activatedAt;
  final ActivationFailureReason? failureReason;
  final String? sanitizedMessage;

  const ActivationResult({
    required this.operationId,
    required this.installationId,
    required this.success,
    this.activatedAt,
    this.failureReason,
    this.sanitizedMessage,
  });

  bool get isSuccess => success;

  factory ActivationResult.success({
    required String operationId,
    required String installationId,
    required String activatedAt,
  }) {
    return ActivationResult(
      operationId: operationId,
      installationId: installationId,
      success: true,
      activatedAt: activatedAt,
    );
  }

  factory ActivationResult.failure({
    required String operationId,
    required String installationId,
    required ActivationFailureReason failureReason,
    String? sanitizedMessage,
  }) {
    return ActivationResult(
      operationId: operationId,
      installationId: installationId,
      success: false,
      failureReason: failureReason,
      sanitizedMessage: sanitizedMessage,
    );
  }

  Map<String, dynamic> toJson() => {
        'operationId': operationId,
        'installationId': installationId,
        'success': success,
        if (activatedAt != null) 'activatedAt': activatedAt,
        if (failureReason != null) 'failureReason': failureReason!.name,
        if (sanitizedMessage != null) 'sanitizedMessage': sanitizedMessage,
      };
}

/// Eccezione tipizzata del dominio di provisioning.
final class ProvisioningException implements Exception {
  final ProvisioningFailureReason reason;
  final String message;

  const ProvisioningException({
    required this.reason,
    required this.message,
  });

  @override
  String toString() {
    return 'ProvisioningException[${reason.name}]: $message';
  }
}
