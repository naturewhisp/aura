import 'package:meta/meta.dart';

/// Error codes returned when an [InferenceRuntime] operation fails.
enum RuntimeFailureCode {
  invalidState,
  alreadyInitialized,
  disposed,
  runtimeUnavailable,
  runtimeInitializationFailed,
  runtimeIncompatible,
  runtimeCrashed,
  backendUnavailable,
  unsupportedBackend,
  unsupportedCapability,
  modelMissing,
  modelCorrupted,
  modelIncompatible,
  modelLoadFailed,
  invalidModelHandle,
  modelInUse,
  insufficientMemory,
  insufficientStorage,
  invalidRequest,
  invalidArgument,
  duplicateRequestId,
  requestNotFound,
  tooManyLoadedModels,
  concurrencyLimitExceeded,
  generationFailed,
  structuredOutputUnavailable,
  malformedStructuredOutput,
  timeout,
  cancelled,
  cancellationUnsupported,
  networkUnavailable,
  permissionDenied,
  integrityCheckFailed,
  recoveryFailed,
  unknown,
}

/// Suggested actions to recover from a runtime failure.
enum RuntimeRecoveryAction {
  none,
  retryRequest,
  reloadModel,
  restartRuntime,
  selectFallbackBackend,
  selectFallbackModel,
  freeStorage,
  closeOtherApplications,
  repairInstallation,
  reinstallRuntime,
  useDeterministicFallback,
  contactSupport,
}

/// Structured failure information for an [InferenceRuntime] error.
@immutable
class RuntimeFailure {
  final RuntimeFailureCode code;
  final String message;
  final bool recoverable;
  final RuntimeRecoveryAction suggestedAction;
  final Map<String, Object?> diagnostics;

  const RuntimeFailure({
    required this.code,
    required this.message,
    this.recoverable = false,
    this.suggestedAction = RuntimeRecoveryAction.none,
    this.diagnostics = const {},
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RuntimeFailure &&
          runtimeType == other.runtimeType &&
          code == other.code &&
          message == other.message &&
          recoverable == other.recoverable &&
          suggestedAction == other.suggestedAction;

  @override
  int get hashCode => Object.hash(code, message, recoverable, suggestedAction);

  @override
  String toString() => 'RuntimeFailure(code: $code, message: "$message")';
}

/// Exception thrown when an [InferenceRuntime] operation encounters a failure.
class RuntimeException implements Exception {
  final RuntimeFailure failure;
  final Object? cause;
  final StackTrace? stackTrace;

  const RuntimeException(
    this.failure, {
    this.cause,
    this.stackTrace,
  });

  @override
  String toString() =>
      'RuntimeException: ${failure.message} (code: ${failure.code})'
      '${cause != null ? ' Cause: $cause' : ''}';
}

/// Warning codes for degraded non-fatal runtime operations.
enum RuntimeWarningCode {
  requestedBackendUnavailableFallbackUsed,
  requestedContextReduced,
  tokenUsageUnavailable,
  thinkingPolicyIgnored,
  nativeStructuredOutputUnavailablePromptFallbackUsed,
  resourceMetricsUnavailable,
  modelAlreadyLoadedReused,
}

/// Warning information returned alongside generation or runtime results.
@immutable
class RuntimeWarning {
  final RuntimeWarningCode code;
  final String message;
  final Map<String, Object?> diagnostics;

  const RuntimeWarning({
    required this.code,
    required this.message,
    this.diagnostics = const {},
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RuntimeWarning &&
          runtimeType == other.runtimeType &&
          code == other.code &&
          message == other.message;

  @override
  int get hashCode => Object.hash(code, message);

  @override
  String toString() => 'RuntimeWarning(code: $code, message: "$message")';
}
