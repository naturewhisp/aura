import 'dart:io';
import '../domain/catalog_manifest.dart';
import '../domain/installation_record.dart';
import '../domain/provisioning_options.dart';
import 'provisioning_path_resolver.dart';

/// Esegue l'installazione atomica fisica sul filesystem degli artefatti.
/// NON modifica direttamente l'InstallationRecord o l'ActivationState.
final class AtomicArtifactInstaller {
  final ProvisioningPathResolver _pathResolver;

  AtomicArtifactInstaller({
    required ProvisioningPathResolver pathResolver,
  }) : _pathResolver = pathResolver;

  /// Sposta fisicamente l'artefatto dalla directory/file di staging alla destinazione app-managed.
  /// Ritorna un [InstalledArtifactDescriptor] contenente i dettagli della transazione completata.
  Future<InstalledArtifactDescriptor> installArtifact({
    required String sourcePath,
    required CatalogArtifact targetArtifact,
    String? installedAtOverride,
  }) async {
    final sourceEntity = FileSystemEntity.typeSync(sourcePath);
    if (sourceEntity == FileSystemEntityType.notFound) {
      throw ProvisioningException(
        reason: ProvisioningFailureReason.atomicMoveFailed,
        message: 'La sorgente di staging non esiste: "$sourcePath".',
      );
    }

    final relativeInstallPath = _pathResolver.resolveRelativeInstallPath(
      artifactType: targetArtifact.artifactType,
      artifactId: targetArtifact.artifactId,
      buildOrVersionId: targetArtifact.buildId,
    );

    final absoluteInstallPath = _pathResolver.resolveAbsoluteInstallPath(
      artifactType: targetArtifact.artifactType,
      artifactId: targetArtifact.artifactId,
      buildOrVersionId: targetArtifact.buildId,
    );

    _validateTargetBoundary(absoluteInstallPath);

    final targetEntity = FileSystemEntity.typeSync(absoluteInstallPath);
    if (targetEntity != FileSystemEntityType.notFound) {
      throw ProvisioningException(
        reason: ProvisioningFailureReason.installationConflict,
        message:
            'La destinazione di installazione esiste già: "$absoluteInstallPath".',
      );
    }

    final targetDir = Directory(absoluteInstallPath);
    await targetDir.parent.create(recursive: true);

    bool copyPerformed = false;
    try {
      if (sourceEntity == FileSystemEntityType.directory) {
        final sourceDir = Directory(sourcePath);
        try {
          await sourceDir.rename(absoluteInstallPath);
        } on FileSystemException catch (_) {
          copyPerformed = true;
          await _copyDirectory(sourceDir, targetDir);
          await sourceDir.delete(recursive: true);
        }
      } else if (sourceEntity == FileSystemEntityType.file) {
        final sourceFile = File(sourcePath);
        final targetFile = File(
            ProvisioningPathResolver.sanitizeSegment(targetArtifact.fileName));
        final finalFilePath = '${targetDir.path}\\${targetFile.path}';
        await targetDir.create(recursive: true);
        try {
          await sourceFile.rename(finalFilePath);
        } on FileSystemException catch (_) {
          copyPerformed = true;
          await sourceFile.copy(finalFilePath);
          await sourceFile.delete();
        }
      }
    } catch (_) {
      // Rollback fisico best-effort
      await _performPhysicalRollback(absoluteInstallPath);
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.atomicMoveFailed,
        message: 'Spostamento atomico o copia fisica dell\'artefatto fallita.',
      );
    }

    final installedAt =
        installedAtOverride ?? DateTime.now().toUtc().toIso8601String();

    return InstalledArtifactDescriptor(
      artifactId: targetArtifact.artifactId,
      artifactType: targetArtifact.artifactType,
      displayName: targetArtifact.displayName,
      version: targetArtifact.version,
      buildId: targetArtifact.buildId,
      platform: targetArtifact.platform,
      architecture: targetArtifact.architecture,
      relativeInstallPath: relativeInstallPath,
      installedAt: installedAt,
      sizeBytes: targetArtifact.sizeBytes,
      sha256: targetArtifact.sha256,
      sourceKind: targetArtifact.sourceKind,
      metadata: {
        ...targetArtifact.metadata,
        'installedViaCopyFallback': copyPerformed,
      },
    );
  }

  void _validateTargetBoundary(String absoluteInstallPath) {
    final cleanAppManaged = _pathResolver.appManagedRoot.toLowerCase();
    final cleanTarget = absoluteInstallPath.toLowerCase();

    if (!cleanTarget.startsWith(cleanAppManaged)) {
      throw ProvisioningException(
        reason: ProvisioningFailureReason.atomicMoveFailed,
        message:
            'Il percorso di destinazione "$absoluteInstallPath" è esterno alla root gestita dall\'applicazione.',
      );
    }
  }

  Future<void> _copyDirectory(Directory source, Directory destination) async {
    await destination.create(recursive: true);
    await for (final entity in source.list(recursive: false)) {
      final name = entity.path.substring(source.path.length + 1);
      final newPath = '${destination.path}\\$name';
      if (entity is Directory) {
        await _copyDirectory(entity, Directory(newPath));
      } else if (entity is File) {
        await entity.copy(newPath);
      }
    }
  }

  Future<void> _performPhysicalRollback(String targetPath) async {
    try {
      final type = FileSystemEntity.typeSync(targetPath);
      if (type == FileSystemEntityType.directory) {
        await Directory(targetPath).delete(recursive: true);
      } else if (type == FileSystemEntityType.file) {
        await File(targetPath).delete();
      }
    } catch (_) {}
  }
}
