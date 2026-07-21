import 'package:meta/meta.dart';

/// Policy applicativa per la gestione del download di artefatti remoti.
enum ProvisioningDownloadPolicy {
  neverDownload,
  explicitConsent;

  static ProvisioningDownloadPolicy parse(String value) {
    return ProvisioningDownloadPolicy.values.firstWhere(
      (e) => e.name == value,
      orElse: () => ProvisioningDownloadPolicy.neverDownload,
    );
  }
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
      throw ArgumentError(
          'I campi del consenso al download non possono essere vuoti');
    }
    if (expectedSizeBytes <= 0) {
      throw ArgumentError('expectedSizeBytes deve essere maggiore di zero');
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
}

/// Richiesta strutturata per l'esecuzione di un'operazione di provisioning.
@immutable
final class ProvisioningRequest {
  final String operationId;
  final String catalogId;
  final String artifactId;
  final ProvisioningDownloadPolicy downloadPolicy;
  final DownloadConsent? consent;
  final bool activateAfterInstall;
  final String expectedPlatform;
  final String expectedArchitecture;
  final String? customSourcePath;
  final bool overwritePolicy;
  final bool diagnosticMode;

  const ProvisioningRequest({
    required this.operationId,
    required this.catalogId,
    required this.artifactId,
    this.downloadPolicy = ProvisioningDownloadPolicy.neverDownload,
    this.consent,
    this.activateAfterInstall = true,
    this.expectedPlatform = 'windows',
    this.expectedArchitecture = 'x64',
    this.customSourcePath,
    this.overwritePolicy = false,
    this.diagnosticMode = false,
  });
}

/// Risultato tipizzato restituito al termine del provisioning.
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

  const ProvisioningResult({
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
    this.sanitizedDiagnostics = const {},
  });

  factory ProvisioningResult.success({
    required String operationId,
    required String artifactId,
    required String installationId,
    required ProvisioningSourceKind sourceKind,
    required int bytesProcessed,
    bool activated = true,
    bool alreadyInstalled = false,
  }) {
    return ProvisioningResult(
      operationId: operationId,
      artifactId: artifactId,
      status: alreadyInstalled
          ? ProvisioningStatus.alreadyInstalled
          : ProvisioningStatus.success,
      installationId: installationId,
      installed: true,
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
}

/// Eccezione tipizzata del dominio di provisioning.
final class ProvisioningException implements Exception {
  final ProvisioningFailureReason reason;
  final String message;
  final Object? cause;

  const ProvisioningException({
    required this.reason,
    required this.message,
    this.cause,
  });

  @override
  String toString() {
    return 'ProvisioningException[${reason.name}]: $message';
  }
}
