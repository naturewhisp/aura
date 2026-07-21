import '../domain/catalog_manifest.dart';
import '../domain/provisioning_cancellation_token.dart';
import '../domain/provisioning_options.dart';
import 'provisioning_file_system.dart';

/// Risultato dell'installazione fisica eseguita da [AtomicArtifactInstaller].
final class InstallationResult {
  final String targetInstallPath;
  final bool installed;
  final bool alreadyInstalled;
  final bool rollbackPerformed;

  const InstallationResult({
    required this.targetInstallPath,
    required this.installed,
    required this.alreadyInstalled,
    required this.rollbackPerformed,
  });
}

/// Installer fisico responsabile dello spostamento sicuro dell'artefatto da staging a destinazione finale.
///
/// **Invariante di Dominio**:
/// [AtomicArtifactInstaller] non aggiorna MAI l'[InstallationRecord] o l'[ActivationState] e non genera l'[installationId].
/// La registrazione dell'identità e dello stato persistito è responsabilità esclusiva dei layer superiori.
final class AtomicArtifactInstaller {
  final ProvisioningFileSystem _fileSystem;

  const AtomicArtifactInstaller({
    required ProvisioningFileSystem fileSystem,
  }) : _fileSystem = fileSystem;

  /// Installa un artefatto da [stagingSourcePath] a [targetInstallPath] usando una directory intermedia isolata.
  Future<InstallationResult> installArtifact({
    required CatalogArtifact artifact,
    required String stagingSourcePath,
    required String targetInstallPath,
    required ProvisioningConflictPolicy conflictPolicy,
    required String operationId,
    ProvisioningCancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();

    final targetDirExists =
        await _fileSystem.directoryExists(targetInstallPath);
    final targetFileExists = await _fileSystem.fileExists(targetInstallPath);

    if (targetDirExists || targetFileExists) {
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.installationConflict,
        message:
            'La directory di installazione finale esiste già sul filesystem.',
      );
    }

    final intermediateTargetPath = '$targetInstallPath.installing-$operationId';
    bool physicalRollbackAttempted = false;

    try {
      cancellationToken?.throwIfCancelled();

      // Pulizia di eventuali residui intermedi precedenti
      await _fileSystem.deleteDirectoryBestEffort(intermediateTargetPath);
      await _fileSystem.deleteFileBestEffort(intermediateTargetPath);

      if (await _fileSystem.directoryExists(stagingSourcePath)) {
        await _fileSystem.copyDirectory(
            stagingSourcePath, intermediateTargetPath);
      } else if (await _fileSystem.fileExists(stagingSourcePath)) {
        final targetFilePath = '$intermediateTargetPath\\${artifact.fileName}';
        await _fileSystem.copyFile(stagingSourcePath, targetFilePath);
      } else {
        throw const ProvisioningException(
          reason: ProvisioningFailureReason.atomicMoveFailed,
          message:
              'Sorgente di staging non trovata per l\'installazione finale.',
        );
      }

      physicalRollbackAttempted = true;
      cancellationToken?.throwIfCancelled();

      // Spostamento finale atomico SENZA fallback a copia nel target definitivo
      await _fileSystem.renameDirectoryWithoutFallback(
          intermediateTargetPath, targetInstallPath);

      return InstallationResult(
        targetInstallPath: targetInstallPath,
        installed: true,
        alreadyInstalled: false,
        rollbackPerformed: false,
      );
    } catch (e) {
      // Rollback fisico: eliminazione della directory intermedia isolata e pulizia target
      if (physicalRollbackAttempted) {
        await _fileSystem.deleteDirectoryBestEffort(intermediateTargetPath);
        await _fileSystem.deleteFileBestEffort(intermediateTargetPath);
        await _fileSystem.deleteDirectoryBestEffort(targetInstallPath);
        await _fileSystem.deleteFileBestEffort(targetInstallPath);
      }

      if (e is ProvisioningException) {
        rethrow;
      }
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.atomicMoveFailed,
        message: 'Spostamento o installazione finale dell\'artefatto fallita.',
      );
    }
  }
}
