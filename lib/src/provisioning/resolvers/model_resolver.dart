import 'package:meta/meta.dart';
import '../../agent_runtime/model_catalog.dart';
import '../domain/catalog_manifest.dart';
import '../domain/installation_record.dart';
import '../domain/provisioning_options.dart';
import '../infrastructure/activation_state_repository.dart';
import '../infrastructure/installation_record_repository.dart';
import '../infrastructure/provisioning_path_resolver.dart';
import '../validation/installed_artifact_verifier.dart';

/// DTO immutabile contenente il payload del modello risolto pronto per l'inferenza.
@immutable
final class ResolvedModelPayload {
  final String installationId;
  final String modelId;
  final String absoluteModelPath;
  final InstalledArtifactDescriptor descriptor;
  final bool isFallbackUsed;
  final String? fallbackSource;

  const ResolvedModelPayload({
    required this.installationId,
    required this.modelId,
    required this.absoluteModelPath,
    required this.descriptor,
    this.isFallbackUsed = false,
    this.fallbackSource,
  });

  Map<String, dynamic> toJson() => {
        'installationId': installationId,
        'modelId': modelId,
        'absoluteModelPath': absoluteModelPath,
        'descriptor': descriptor.toJson(),
        'isFallbackUsed': isFallbackUsed,
        if (fallbackSource != null) 'fallbackSource': fallbackSource,
      };
}

/// DTO immutabile per l'esito della risoluzione del modello.
@immutable
final class ModelResolutionResult {
  final ProvisioningStatus status;
  final ResolvedModelPayload? payload;
  final ProvisioningFailureReason? failureReason;
  final String? sanitizedMessage;

  const ModelResolutionResult.success(this.payload)
      : status = ProvisioningStatus.success,
        failureReason = null,
        sanitizedMessage = null;

  const ModelResolutionResult.failure({
    required this.failureReason,
    required this.sanitizedMessage,
  })  : status = ProvisioningStatus.failed,
        payload = null;

  bool get isSuccess => status == ProvisioningStatus.success && payload != null;
}

/// Servizio ad alto livello per la risoluzione role-aware del modello (Actor o Evaluator) per alias logici/fisici.
final class ModelResolver {
  final ModelCatalog _catalog;
  final InstallationRecordRepository _recordRepository;
  final ActivationStateRepository _activationRepository;
  final ProvisioningPathResolver _pathResolver;
  final InstalledArtifactVerifier _verifier;

  ModelResolver({
    required ModelCatalog catalog,
    required InstallationRecordRepository recordRepository,
    required ActivationStateRepository activationRepository,
    required ProvisioningPathResolver pathResolver,
    required InstalledArtifactVerifier verifier,
  })  : _catalog = catalog,
        _recordRepository = recordRepository,
        _activationRepository = activationRepository,
        _pathResolver = pathResolver,
        _verifier = verifier;

  /// Risolve un identificatore di modello (alias logico o modelId fisico) nel corrispondente [ResolvedModelPayload].
  ///
  /// Strategia di Risoluzione Role-Aware:
  /// 1. Mappa l'alias logico (es. `actor.default`, `evaluator.default`) nel `physicalModelId` tramite [ModelCatalog].
  /// 2. Determina il ruolo specifico (Actor vs Evaluator) per interrogare la chiave attiva corretta in [ActivationState].
  /// 3. Attesta che l'installazione attiva appartenga esplicitamente al `physicalModelId` richiesto.
  /// 4. Se l'installazione attiva è mancante, del ruolo errato o non integra, tenta `lastKnownGood` specifico del ruolo.
  /// 5. Se anche `lastKnownGood` fallisce, seleziona l'ultima installazione `verified` disponibile nel registro per quel modello specifico.
  Future<ModelResolutionResult> resolveModel(String logicalOrPhysicalId) async {
    final physicalModelId = _catalog.resolveLogicalModelId(logicalOrPhysicalId);
    final isEvaluator = logicalOrPhysicalId.trim() ==
            LogicalModelIds.defaultEvaluator ||
        logicalOrPhysicalId.trim() == LogicalModelIds.primaryEvaluatorAlias ||
        logicalOrPhysicalId.trim() == 'evaluator.default';

    final record = await _recordRepository.readRecord();
    final state = await _activationRepository.readState();

    // 1. Identifica l'installazione attiva specifica per il ruolo
    final activeId = isEvaluator
        ? state.activeEvaluatorModelInstallationId
        : state.activeActorModelInstallationId;

    if (activeId != null) {
      final activeDescriptor = record.findInstallation(activeId);
      if (activeDescriptor != null &&
          activeDescriptor.artifactType == CatalogArtifactType.model &&
          activeDescriptor.artifactId == physicalModelId &&
          activeDescriptor.status == InstallationStatus.verified) {
        final isValid = await _verifier.verifyPhysicalIntegrity(
          activeDescriptor,
          pathResolver: _pathResolver,
        );
        if (isValid) {
          final absolutePath = _resolvePayloadAbsolutePath(activeDescriptor);
          return ModelResolutionResult.success(
            ResolvedModelPayload(
              installationId: activeDescriptor.installationId,
              modelId: activeDescriptor.artifactId,
              absoluteModelPath: absolutePath,
              descriptor: activeDescriptor,
              isFallbackUsed: false,
            ),
          );
        }
      }
    }

    // 2. Prova lastKnownGood specifico per il ruolo se l'attiva ha fallito o non appartiene al modello richiesto
    final lkgId = isEvaluator
        ? state.lastKnownGoodEvaluatorModelInstallationId
        : state.lastKnownGoodActorModelInstallationId;

    if (lkgId != null && lkgId != activeId) {
      final lkgDescriptor = record.findInstallation(lkgId);
      if (lkgDescriptor != null &&
          lkgDescriptor.artifactType == CatalogArtifactType.model &&
          lkgDescriptor.artifactId == physicalModelId &&
          lkgDescriptor.status == InstallationStatus.verified) {
        final isValid = await _verifier.verifyPhysicalIntegrity(
          lkgDescriptor,
          pathResolver: _pathResolver,
        );
        if (isValid) {
          final absolutePath = _resolvePayloadAbsolutePath(lkgDescriptor);
          return ModelResolutionResult.success(
            ResolvedModelPayload(
              installationId: lkgDescriptor.installationId,
              modelId: lkgDescriptor.artifactId,
              absoluteModelPath: absolutePath,
              descriptor: lkgDescriptor,
              isFallbackUsed: true,
              fallbackSource: 'lastKnownGood',
            ),
          );
        }
      }
    }

    // 3. Fallback sull'ultima installazione verificata del modello fisico specifico nel registro
    final latestVerified =
        record.findLatestVerifiedInstallation(physicalModelId);
    if (latestVerified != null &&
        latestVerified.artifactType == CatalogArtifactType.model) {
      final isValid = await _verifier.verifyPhysicalIntegrity(
        latestVerified,
        pathResolver: _pathResolver,
      );
      if (isValid) {
        final absolutePath = _resolvePayloadAbsolutePath(latestVerified);
        return ModelResolutionResult.success(
          ResolvedModelPayload(
            installationId: latestVerified.installationId,
            modelId: latestVerified.artifactId,
            absoluteModelPath: absolutePath,
            descriptor: latestVerified,
            isFallbackUsed: true,
            fallbackSource: 'latestVerified',
          ),
        );
      }
    }

    return ModelResolutionResult.failure(
      failureReason: ProvisioningFailureReason.installationNotFound,
      sanitizedMessage:
          'Impossibile risolvere un\'installazione integra e verificata per il modello "$logicalOrPhysicalId" ($physicalModelId).',
    );
  }

  String _resolvePayloadAbsolutePath(InstalledArtifactDescriptor descriptor) {
    if (descriptor.entryFileName != null &&
        descriptor.entryFileName!.trim().isNotEmpty) {
      return _pathResolver.resolveEntryFilePath(
        relativeInstallPath: descriptor.relativeInstallPath,
        entryFileName: descriptor.entryFileName!,
      );
    }
    return _pathResolver
        .resolveAppManagedRelativePath(descriptor.relativeInstallPath);
  }
}
