import '../domain/catalog_manifest.dart';
import '../domain/provisioning_cancellation_token.dart';
import '../domain/provisioning_options.dart';
import 'provisioning_file_system.dart';

/// Eccezione tipizzata specifica per i fallimenti dell'installazione fisica.
final class ArtifactInstallationException implements Exception {
  final ProvisioningFailureReason reason;
  final String message;
  final bool rollbackPerformed;

  const ArtifactInstallationException({
    required this.reason,
    required this.message,
    this.rollbackPerformed = false,
  });
}

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
/// **Invarianti di Dominio**:
/// 1. [AtomicArtifactInstaller] non aggiorna MAI l'[InstallationRecord] o l'[ActivationState] e non genera l'[installationId].
/// 2. Non esegue MAI copie ricorsive direttamente nel percorso target finale [targetInstallPath].
/// 3. In caso di fallimento di rename atomico, non cancella MAI la destinazione finale [targetInstallPath] (che appartiene a race/altre operazioni).
final class AtomicArtifactInstaller {
  final ProvisioningFileSystem _fileSystem;

  const AtomicArtifactInstaller({
    required ProvisioningFileSystem fileSystem,
  }) : _fileSystem = fileSystem;

  /// Installa un artefatto da [stagingSourcePath] a [targetInstallPath] usando [intermediateInstallPath].
  Future<InstallationResult> installArtifact({
    required CatalogArtifact artifact,
    required String stagingSourcePath,
    required String targetInstallPath,
    required String intermediateInstallPath,
    ProvisioningCancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();

    final targetDirExists =
        await _fileSystem.directoryExists(targetInstallPath);
    final targetFileExists = await _fileSystem.fileExists(targetInstallPath);

    if (targetDirExists || targetFileExists) {
      throw const ArtifactInstallationException(
        reason: ProvisioningFailureReason.installationConflict,
        message:
            'La directory di installazione finale esiste già sul filesystem.',
        rollbackPerformed: false,
      );
    }

    bool physicalCopyStarted = false;

    try {
      cancellationToken?.throwIfCancelled();

      // Pulizia preventiva dell'intermediate di nostra proprietà
      await _fileSystem.deleteDirectoryBestEffort(intermediateInstallPath);
      await _fileSystem.deleteFileBestEffort(intermediateInstallPath);

      physicalCopyStarted = true;

      if (await _fileSystem.directoryExists(stagingSourcePath)) {
        await _fileSystem.copyDirectory(
            stagingSourcePath, intermediateInstallPath);
      } else if (await _fileSystem.fileExists(stagingSourcePath)) {
        final targetFilePath = '$intermediateInstallPath\\${artifact.fileName}';
        await _fileSystem.copyFile(stagingSourcePath, targetFilePath);
      } else {
        throw const ArtifactInstallationException(
          reason: ProvisioningFailureReason.atomicMoveFailed,
          message:
              'Sorgente di staging non trovata per l\'installazione finale.',
          rollbackPerformed: false,
        );
      }

      cancellationToken?.throwIfCancelled();

      // Spostamento finale atomico SENZA fallback a copia nel target definitivo
      await _fileSystem.renameDirectoryWithoutFallback(
          intermediateInstallPath, targetInstallPath);

      return InstallationResult(
        targetInstallPath: targetInstallPath,
        installed: true,
        alreadyInstalled: false,
        rollbackPerformed: false,
      );
    } catch (e) {
      // Pulizia incondizionata indipendentemente dal tipo di eccezione (senza short-circuit &&)
      await _fileSystem.deleteDirectoryBestEffort(intermediateInstallPath);
      await _fileSystem.deleteFileBestEffort(intermediateInstallPath);

      final intermediateAbsent =
          !await _fileSystem.directoryExists(intermediateInstallPath) &&
              !await _fileSystem.fileExists(intermediateInstallPath);

      final rollbackSucceeded = physicalCopyStarted && intermediateAbsent;

      if (e is ArtifactInstallationException) {
        throw ArtifactInstallationException(
          reason: e.reason,
          message: e.message,
          rollbackPerformed: rollbackSucceeded,
        );
      }
      if (e is ProvisioningException) {
        throw ArtifactInstallationException(
          reason: e.reason,
          message: e.message,
          rollbackPerformed: rollbackSucceeded,
        );
      }
      throw ArtifactInstallationException(
        reason: ProvisioningFailureReason.atomicMoveFailed,
        message: 'Spostamento o installazione finale dell\'artefatto fallita.',
        rollbackPerformed: rollbackSucceeded,
      );
    }
  }
}
