import 'dart:io';
import '../domain/catalog_manifest.dart';
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
/// [AtomicArtifactInstaller] non aggiorna MAI l'[InstallationRecord] o l'[ActivationState].
/// La registrazione dello stato persistito è responsabilità esclusiva dei layer superiori.
final class AtomicArtifactInstaller {
  final ProvisioningFileSystem _fileSystem;

  const AtomicArtifactInstaller({
    ProvisioningFileSystem fileSystem = const LocalProvisioningFileSystem(),
  }) : _fileSystem = fileSystem;

  /// Installa un artefatto da [stagingSourcePath] a [targetInstallPath].
  Future<InstallationResult> installArtifact({
    required CatalogArtifact artifact,
    required String stagingSourcePath,
    required String targetInstallPath,
    required ProvisioningConflictPolicy conflictPolicy,
  }) async {
    final targetDirExists =
        await _fileSystem.directoryExists(targetInstallPath);
    final targetFileExists = await _fileSystem.fileExists(targetInstallPath);

    if (targetDirExists || targetFileExists) {
      if (conflictPolicy == ProvisioningConflictPolicy.returnAlreadyInstalled) {
        return InstallationResult(
          targetInstallPath: targetInstallPath,
          installed: false,
          alreadyInstalled: true,
          rollbackPerformed: false,
        );
      } else {
        throw const ProvisioningException(
          reason: ProvisioningFailureReason.installationConflict,
          message: 'La directory di installazione finale esiste già.',
        );
      }
    }

    try {
      final stagingDir = Directory(stagingSourcePath);
      final stagingFile = File(stagingSourcePath);

      if (await stagingDir.exists()) {
        await _moveOrCopyDirectory(stagingSourcePath, targetInstallPath);
      } else if (await stagingFile.exists()) {
        final targetFile = File(targetInstallPath);
        await targetFile.parent.create(recursive: true);
        await _fileSystem.copyFile(stagingSourcePath, targetInstallPath);
        await _fileSystem.deleteFileBestEffort(stagingSourcePath);
      } else {
        throw const ProvisioningException(
          reason: ProvisioningFailureReason.atomicMoveFailed,
          message:
              'Sorgente di staging non trovata per l\'installazione finale.',
        );
      }

      return InstallationResult(
        targetInstallPath: targetInstallPath,
        installed: true,
        alreadyInstalled: false,
        rollbackPerformed: false,
      );
    } catch (e) {
      // Rollback: cleanup best-effort della directory target parziale
      await _cleanupPartialTarget(targetInstallPath);

      if (e is ProvisioningException) {
        rethrow;
      }
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.atomicMoveFailed,
        message: 'Spostamento o installazione finale dell\'artefatto fallita.',
      );
    }
  }

  Future<void> _moveOrCopyDirectory(
      String sourcePath, String targetPath) async {
    final sourceDir = Directory(sourcePath);
    final targetDir = Directory(targetPath);

    await targetDir.parent.create(recursive: true);

    try {
      // Tenta il rename atomico diretto della directory
      await sourceDir.rename(targetDir.path);
    } catch (_) {
      // Fallback: copia ricorsiva e successiva rimozione dello staging
      await _copyDirectoryRecursively(sourceDir, targetDir);
      try {
        await sourceDir.delete(recursive: true);
      } catch (_) {}
    }
  }

  Future<void> _copyDirectoryRecursively(
      Directory source, Directory target) async {
    if (!await target.exists()) {
      await target.create(recursive: true);
    }

    await for (final entity in source.list(recursive: false)) {
      final relativeName = entity.path.substring(source.path.length + 1);
      final destinationPath = '${target.path}\\$relativeName';

      if (entity is Directory) {
        await _copyDirectoryRecursively(entity, Directory(destinationPath));
      } else if (entity is File) {
        await entity.copy(destinationPath);
      }
    }
  }

  Future<void> _cleanupPartialTarget(String targetPath) async {
    try {
      final dir = Directory(targetPath);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
      final file = File(targetPath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }
}
