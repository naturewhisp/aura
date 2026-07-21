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
      if (conflictPolicy == ProvisioningConflictPolicy.returnAlreadyInstalled) {
        // Verifica fisica che l'installazione esistente sia integra e non vuota
        final isExistingValid =
            await _verifyExistingInstallation(targetInstallPath);
        if (isExistingValid) {
          return InstallationResult(
            targetInstallPath: targetInstallPath,
            installed: false,
            alreadyInstalled: true,
            rollbackPerformed: false,
          );
        }
        // Se la directory esistente era vuota o corrotta, la elimina e forza la nuova installazione
        await _fileSystem.deleteDirectoryBestEffort(targetInstallPath);
        await _fileSystem.deleteFileBestEffort(targetInstallPath);
      } else {
        throw const ProvisioningException(
          reason: ProvisioningFailureReason.installationConflict,
          message: 'La directory di installazione finale esiste già.',
        );
      }
    }

    final intermediateTargetPath = '$targetInstallPath.installing-$operationId';

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

      cancellationToken?.throwIfCancelled();

      // Verifica di integrità sulla directory intermedia
      final isIntermediateValid =
          await _verifyExistingInstallation(intermediateTargetPath);
      if (!isIntermediateValid) {
        throw const ProvisioningException(
          reason: ProvisioningFailureReason.atomicMoveFailed,
          message:
              'La directory di installazione intermedia è risultata vuota o corrotta.',
        );
      }

      // Spostamento finale dalla directory intermedia alla destinazione definitiva
      await _fileSystem.moveDirectory(
          intermediateTargetPath, targetInstallPath);

      return InstallationResult(
        targetInstallPath: targetInstallPath,
        installed: true,
        alreadyInstalled: false,
        rollbackPerformed: false,
      );
    } catch (e) {
      // Rollback fisico: eliminazione della directory intermedia e parziale target
      await _fileSystem.deleteDirectoryBestEffort(intermediateTargetPath);
      await _fileSystem.deleteFileBestEffort(intermediateTargetPath);
      await _fileSystem.deleteDirectoryBestEffort(targetInstallPath);
      await _fileSystem.deleteFileBestEffort(targetInstallPath);

      if (e is ProvisioningException) {
        rethrow;
      }
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.atomicMoveFailed,
        message: 'Spostamento o installazione finale dell\'artefatto fallita.',
      );
    }
  }

  Future<bool> _verifyExistingInstallation(String path) async {
    if (await _fileSystem.directoryExists(path)) {
      final items = await _fileSystem.listDirectory(path);
      return items.isNotEmpty;
    } else if (await _fileSystem.fileExists(path)) {
      final size = await _fileSystem.getFileSize(path);
      return size > 0;
    }
    return false;
  }
}
