import 'package:meta/meta.dart';

import 'activation_state.dart';
import 'installation_record.dart';
import 'provisioning_options.dart';
import 'validated_catalog_candidate.dart';

/// Policy per la gestione dell'attivazione durante l'aggiornamento di un modello.
enum UpdateActivationPolicy {
  /// Installa la nuova versione nel registro/store ma lascia inalterato lo stato di attivazione corrente.
  keepCurrent,

  /// Attiva sempre la nuova versione installata.
  activateNew,

  /// Attiva la nuova versione SOLO SE la versione precedentemente installata era attiva.
  followActiveArtifact,
}

/// Policy per la gestione dell'eliminazione (purge) di un'installazione attualmente attiva.
enum ActiveInstallationPurgePolicy {
  /// Rifiuta l'eliminazione se l'installazione target è attualmente attiva.
  reject,

  /// Disattiva il modello ed il relativo binding prima dell'eliminazione fisica.
  deactivate,

  /// Commuta l'attivazione alla versione verificata precedente prima di eliminare.
  fallbackToPreviousVerified,
}

/// Precondizioni ottimistiche catturate durante la fase preparatoria (unlocked)
/// e verificate sotto lock prima di eseguire il commit atomico.
@immutable
final class LifecyclePrecondition {
  final String artifactId;
  final String? expectedActiveInstallationId;
  final Set<String> expectedInstallationIds;

  const LifecyclePrecondition({
    required this.artifactId,
    this.expectedActiveInstallationId,
    this.expectedInstallationIds = const {},
  });

  /// Cattura la snapshot di precondizione corrente da record ed activation state.
  factory LifecyclePrecondition.capture({
    required String artifactId,
    required InstallationRecord record,
    required ActivationState activationState,
    ModelActivationRole? role,
  }) {
    final activeId =
        role != null ? activationState.getActiveInstallationId(role) : null;
    final existingIds = record
        .findInstallationsForArtifact(artifactId)
        .map((a) => a.installationId)
        .toSet();

    return LifecyclePrecondition(
      artifactId: artifactId,
      expectedActiveInstallationId: activeId,
      expectedInstallationIds: existingIds,
    );
  }
}

// ============================================================================
// REPAIR DTOs
// ============================================================================

/// Stato di esito per un'operazione di riparazione.
enum ModelRepairStatus {
  noRepairNeeded,
  repaired,
  repairSourceUnavailable,
  repairMetadataMissing,
  repairConflict,
  repairCommitIndeterminate,
  failed,
}

/// Richiesta di riparazione per un'installazione specifica.
@immutable
final class RepairModelRequest {
  final String operationId;
  final String targetInstallationId;
  final ValidatedCatalogCandidate? candidate;

  const RepairModelRequest({
    required this.operationId,
    required this.targetInstallationId,
    this.candidate,
  });
}

/// Risultato tipizzato di un'operazione di riparazione.
@immutable
final class ModelRepairResult {
  final String operationId;
  final String artifactId;
  final String installationId;
  final ModelRepairStatus status;
  final bool filesystemCommitted;
  final bool recordCommitted;
  final bool activationCommitted;
  final bool cleanupPending;
  final bool reconciliationRequired;
  final ProvisioningFailureReason? failureReason;
  final String? message;

  const ModelRepairResult({
    required this.operationId,
    required this.artifactId,
    required this.installationId,
    required this.status,
    this.filesystemCommitted = false,
    this.recordCommitted = false,
    this.activationCommitted = false,
    this.cleanupPending = false,
    this.reconciliationRequired = false,
    this.failureReason,
    this.message,
  });

  bool get isSuccess =>
      status == ModelRepairStatus.noRepairNeeded ||
      status == ModelRepairStatus.repaired;
}

// ============================================================================
// UPDATE DTOs
// ============================================================================

/// Stato di esito per un'operazione di aggiornamento.
enum ModelUpdateStatus {
  alreadyLatest,
  installed,
  installedAndActivated,
  installedActivationPending,
  updateConflict,
  stalePrecondition,
  updateCommitIndeterminate,
  failed,
}

/// Richiesta di aggiornamento di un modello rispetto ad un candidato di catalogo.
@immutable
final class UpdateModelRequest {
  final String operationId;
  final String artifactId;
  final ModelActivationRole modelRole;
  final ValidatedCatalogCandidate candidate;
  final UpdateActivationPolicy activationPolicy;

  const UpdateModelRequest({
    required this.operationId,
    required this.artifactId,
    required this.modelRole,
    required this.candidate,
    this.activationPolicy = UpdateActivationPolicy.followActiveArtifact,
  });
}

/// Risultato tipizzato di un'operazione di aggiornamento.
@immutable
final class ModelUpdateResult {
  final String operationId;
  final String artifactId;
  final String? previousInstallationId;
  final String? newInstallationId;
  final ModelUpdateStatus status;
  final bool filesystemCommitted;
  final bool recordCommitted;
  final bool activationCommitted;
  final bool cleanupPending;
  final bool reconciliationRequired;
  final ProvisioningFailureReason? failureReason;
  final String? message;

  const ModelUpdateResult({
    required this.operationId,
    required this.artifactId,
    this.previousInstallationId,
    this.newInstallationId,
    required this.status,
    this.filesystemCommitted = false,
    this.recordCommitted = false,
    this.activationCommitted = false,
    this.cleanupPending = false,
    this.reconciliationRequired = false,
    this.failureReason,
    this.message,
  });

  bool get isSuccess =>
      status == ModelUpdateStatus.alreadyLatest ||
      status == ModelUpdateStatus.installed ||
      status == ModelUpdateStatus.installedAndActivated ||
      status == ModelUpdateStatus.installedActivationPending;
}

// ============================================================================
// ROLLBACK DTOs
// ============================================================================

/// Stato di esito per un rollback (switch dell'attivazione).
enum ModelRollbackStatus {
  rolledBack,
  alreadyActive,
  targetNotVerified,
  targetCorrupt,
  staleCurrentActivation,
  failed,
}

/// Richiesta di rollback dell'attivazione verso un'installazione precedente.
@immutable
final class RollbackModelRequest {
  final String operationId;
  final String artifactId;
  final ModelActivationRole modelRole;
  final String targetInstallationId;
  final String? expectedCurrentInstallationId;

  const RollbackModelRequest({
    required this.operationId,
    required this.artifactId,
    required this.modelRole,
    required this.targetInstallationId,
    this.expectedCurrentInstallationId,
  });
}

/// Risultato tipizzato per un rollback.
@immutable
final class ModelRollbackResult {
  final String operationId;
  final String artifactId;
  final String? previousInstallationId;
  final String activeInstallationId;
  final ModelRollbackStatus status;
  final bool activationCommitted;
  final ProvisioningFailureReason? failureReason;
  final String? message;

  const ModelRollbackResult({
    required this.operationId,
    required this.artifactId,
    this.previousInstallationId,
    required this.activeInstallationId,
    required this.status,
    this.activationCommitted = false,
    this.failureReason,
    this.message,
  });

  bool get isSuccess =>
      status == ModelRollbackStatus.rolledBack ||
      status == ModelRollbackStatus.alreadyActive;
}

// ============================================================================
// PURGE DTOs
// ============================================================================

/// Stato di esito per la rimozione sicura (purge).
enum ModelPurgeStatus {
  purged,
  purgedCleanupPending,
  purgeRejectedActive,
  fallbackUnavailable,
  purgeConflict,
  purgeCommitIndeterminate,
  filesystemAlreadyAbsent,
  filesystemMovedToTrash,
  failed,
}

/// Richiesta di eliminazione sicura di un'installazione.
@immutable
final class PurgeInstallationRequest {
  final String operationId;
  final String installationId;
  final ActiveInstallationPurgePolicy activePurgePolicy;

  const PurgeInstallationRequest({
    required this.operationId,
    required this.installationId,
    this.activePurgePolicy = ActiveInstallationPurgePolicy.reject,
  });
}

/// Risultato tipizzato di una rimozione sicura (purge).
@immutable
final class ModelPurgeResult {
  final String operationId;
  final String installationId;
  final String? fallbackInstallationId;
  final ModelPurgeStatus status;
  final bool filesystemCommitted;
  final bool recordCommitted;
  final bool activationCommitted;
  final bool cleanupPending;
  final ProvisioningFailureReason? failureReason;
  final String? message;

  const ModelPurgeResult({
    required this.operationId,
    required this.installationId,
    this.fallbackInstallationId,
    required this.status,
    this.filesystemCommitted = false,
    this.recordCommitted = false,
    this.activationCommitted = false,
    this.cleanupPending = false,
    this.failureReason,
    this.message,
  });

  bool get isSuccess =>
      status == ModelPurgeStatus.purged ||
      status == ModelPurgeStatus.purgedCleanupPending ||
      status == ModelPurgeStatus.filesystemAlreadyAbsent ||
      status == ModelPurgeStatus.filesystemMovedToTrash;
}

// ============================================================================
// RECONCILIATION RESULT DTO
// ============================================================================

/// Esito sintetico delle transazioni di riconciliazione lifecycle.
@immutable
final class ModelLifecycleReconciliationResult {
  final int repairedCount;
  final int purgedTrashCount;
  final int cleanedStaleTempCount;
  final int resolvedDanglingActivationsCount;
  final int deactivatedNoFallbackCount;
  final int unresolvedRoleMismatchCount;

  const ModelLifecycleReconciliationResult({
    required this.repairedCount,
    required this.purgedTrashCount,
    required this.cleanedStaleTempCount,
    required this.resolvedDanglingActivationsCount,
    this.deactivatedNoFallbackCount = 0,
    this.unresolvedRoleMismatchCount = 0,
  });

  int get totalActionsPerformed =>
      repairedCount +
      purgedTrashCount +
      cleanedStaleTempCount +
      resolvedDanglingActivationsCount +
      deactivatedNoFallbackCount +
      unresolvedRoleMismatchCount;
}
