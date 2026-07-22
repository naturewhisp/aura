import 'package:meta/meta.dart';
import '../domain/catalog_manifest.dart';
import '../domain/installation_record.dart';
import '../domain/provisioning_options.dart';
import '../infrastructure/activation_state_repository.dart';
import '../infrastructure/installation_record_repository.dart';
import '../infrastructure/provisioning_file_system.dart';
import '../infrastructure/provisioning_path_resolver.dart';
import '../validation/installed_artifact_verifier.dart';

/// DTO immutabile contenente il payload del runtime di inferenza risolto.
@immutable
final class ResolvedRuntimePayload {
  final String installationId;
  final String runtimeId;
  final String executableAbsolutePath;
  final InstalledArtifactDescriptor descriptor;
  final bool isFallbackUsed;
  final String? fallbackSource;

  const ResolvedRuntimePayload({
    required this.installationId,
    required this.runtimeId,
    required this.executableAbsolutePath,
    required this.descriptor,
    this.isFallbackUsed = false,
    this.fallbackSource,
  });

  Map<String, dynamic> toJson() => {
        'installationId': installationId,
        'runtimeId': runtimeId,
        'executableAbsolutePath': executableAbsolutePath,
        'descriptor': descriptor.toJson(),
        'isFallbackUsed': isFallbackUsed,
        if (fallbackSource != null) 'fallbackSource': fallbackSource,
      };
}

/// DTO immutabile per l'esito della risoluzione del runtime.
@immutable
final class RuntimeResolutionResult {
  final ProvisioningStatus status;
  final ResolvedRuntimePayload? payload;
  final ProvisioningFailureReason? failureReason;
  final String? sanitizedMessage;

  const RuntimeResolutionResult.success(this.payload)
      : status = ProvisioningStatus.success,
        failureReason = null,
        sanitizedMessage = null;

  const RuntimeResolutionResult.failure({
    required this.failureReason,
    required this.sanitizedMessage,
  })  : status = ProvisioningStatus.failed,
        payload = null;

  bool get isSuccess => status == ProvisioningStatus.success && payload != null;
}

/// Servizio ad alto livello per la risoluzione dell'eseguibile di runtime attivo o di fallback.
final class RuntimeResolver {
  final InstallationRecordRepository _recordRepository;
  final ActivationStateRepository _activationRepository;
  final ProvisioningPathResolver _pathResolver;
  final InstalledArtifactVerifier _verifier;
  final ProvisioningFileSystem _fileSystem;

  RuntimeResolver({
    required InstallationRecordRepository recordRepository,
    required ActivationStateRepository activationRepository,
    required ProvisioningPathResolver pathResolver,
    required InstalledArtifactVerifier verifier,
    ProvisioningFileSystem fileSystem = const LocalProvisioningFileSystem(),
  })  : _recordRepository = recordRepository,
        _activationRepository = activationRepository,
        _pathResolver = pathResolver,
        _verifier = verifier,
        _fileSystem = fileSystem;

  /// Risolve il runtime di inferenza eseguibile attivo o di fallback.
  ///
  /// Se [requestedInstallationId] è fornito ed [allowFallback] è false (strict mode),
  /// l'esito fallisce direttamente se l'installazione specifica non è integra o l'eseguibile è assente.
  Future<RuntimeResolutionResult> resolveRuntime({
    String? requestedInstallationId,
    bool allowFallback = true,
  }) async {
    final record = await _recordRepository.readRecord();
    final state = await _activationRepository.readState();

    // 1. Prova l'installazione richiesta o attiva corrente
    final targetId =
        requestedInstallationId ?? state.activeRuntimeInstallationId;
    if (targetId != null) {
      final descriptor = record.findInstallation(targetId);
      if (descriptor != null &&
          descriptor.artifactType == CatalogArtifactType.runtime &&
          descriptor.status == InstallationStatus.verified) {
        final isValid = await _verifier.verifyPhysicalIntegrity(
          descriptor,
          pathResolver: _pathResolver,
        );
        if (isValid) {
          final execPath = _resolveExecutableAbsolutePath(descriptor);
          final execExists = await _fileSystem.fileExists(execPath);
          if (execExists) {
            return RuntimeResolutionResult.success(
              ResolvedRuntimePayload(
                installationId: descriptor.installationId,
                runtimeId: descriptor.artifactId,
                executableAbsolutePath: execPath,
                descriptor: descriptor,
                isFallbackUsed: false,
              ),
            );
          }
        }
      }

      // Se era stata richiesta un'installazione esplicita in modalità strict (allowFallback: false), non avviare fallback
      if (requestedInstallationId != null && !allowFallback) {
        return RuntimeResolutionResult.failure(
          failureReason: ProvisioningFailureReason.installationNotFound,
          sanitizedMessage:
              'L\'installazione di runtime richiesta "$requestedInstallationId" non è integra o l\'eseguibile è assente su disco.',
        );
      }
    }

    if (!allowFallback && requestedInstallationId != null) {
      return RuntimeResolutionResult.failure(
        failureReason: ProvisioningFailureReason.installationNotFound,
        sanitizedMessage:
            'L\'installazione di runtime richiesta "$requestedInstallationId" non esiste.',
      );
    }

    // 2. Prova lastKnownGoodRuntimeInstallationId se l'attiva ha fallito o non è impostata
    final lkgId = state.lastKnownGoodRuntimeInstallationId;
    if (lkgId != null && lkgId != targetId) {
      final lkgDescriptor = record.findInstallation(lkgId);
      if (lkgDescriptor != null &&
          lkgDescriptor.artifactType == CatalogArtifactType.runtime &&
          lkgDescriptor.status == InstallationStatus.verified) {
        final isValid = await _verifier.verifyPhysicalIntegrity(
          lkgDescriptor,
          pathResolver: _pathResolver,
        );
        if (isValid) {
          final execPath = _resolveExecutableAbsolutePath(lkgDescriptor);
          final execExists = await _fileSystem.fileExists(execPath);
          if (execExists) {
            return RuntimeResolutionResult.success(
              ResolvedRuntimePayload(
                installationId: lkgDescriptor.installationId,
                runtimeId: lkgDescriptor.artifactId,
                executableAbsolutePath: execPath,
                descriptor: lkgDescriptor,
                isFallbackUsed: true,
                fallbackSource: 'lastKnownGood',
              ),
            );
          }
        }
      }
    }

    // 3. Fallback deterministico sull'ultima installazione di runtime verified registrata
    final latestRuntime = record.findLatestVerifiedRuntimeInstallation();
    if (latestRuntime != null) {
      final isValid = await _verifier.verifyPhysicalIntegrity(
        latestRuntime,
        pathResolver: _pathResolver,
      );
      if (isValid) {
        final execPath = _resolveExecutableAbsolutePath(latestRuntime);
        final execExists = await _fileSystem.fileExists(execPath);
        if (execExists) {
          return RuntimeResolutionResult.success(
            ResolvedRuntimePayload(
              installationId: latestRuntime.installationId,
              runtimeId: latestRuntime.artifactId,
              executableAbsolutePath: execPath,
              descriptor: latestRuntime,
              isFallbackUsed: true,
              fallbackSource: 'latestVerified',
            ),
          );
        }
      }
    }

    return const RuntimeResolutionResult.failure(
      failureReason: ProvisioningFailureReason.installationNotFound,
      sanitizedMessage:
          'Impossibile risolvere un runtime di inferenza integro e verificato con eseguibile valido su disco.',
    );
  }

  String _resolveExecutableAbsolutePath(
      InstalledArtifactDescriptor descriptor) {
    if (descriptor.entryFileName != null &&
        descriptor.entryFileName!.trim().isNotEmpty) {
      return _pathResolver.resolveEntryFilePath(
        relativeInstallPath: descriptor.relativeInstallPath,
        entryFileName: descriptor.entryFileName!,
      );
    }
    final baseDir = _pathResolver
        .resolveAppManagedRelativePath(descriptor.relativeInstallPath);
    return _pathResolver.join(baseDir, 'llama-server.exe');
  }
}
