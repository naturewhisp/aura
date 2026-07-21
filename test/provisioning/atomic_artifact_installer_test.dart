import 'dart:io';
import 'package:aura_core/aura_core.dart';
import 'package:test/test.dart';

void main() {
  group('AtomicArtifactInstaller Tests -', () {
    late Directory tempAppRoot;
    late Directory tempBundledRoot;
    late ProvisioningPathResolver pathResolver;
    late AtomicArtifactInstaller installer;

    setUp(() async {
      tempAppRoot =
          await Directory.systemTemp.createTemp('aura_installer_test_app_');
      tempBundledRoot =
          await Directory.systemTemp.createTemp('aura_installer_test_bundled_');
      pathResolver = ProvisioningPathResolver(
        appManagedRoot: tempAppRoot.path,
        bundledRoot: tempBundledRoot.path,
      );
      installer = AtomicArtifactInstaller(pathResolver: pathResolver);
    });

    tearDown(() async {
      if (await tempAppRoot.exists()) {
        await tempAppRoot.delete(recursive: true);
      }
      if (await tempBundledRoot.exists()) {
        await tempBundledRoot.delete(recursive: true);
      }
    });

    test(
        'Sposta fisicamente una directory da staging al percorso gestito dall applicazione',
        () async {
      final stagingDir =
          Directory(pathResolver.resolveStagingDirectory('op_100'));
      await stagingDir.create(recursive: true);
      final binFile = File('${stagingDir.path}\\llama-server.exe');
      await binFile.writeAsString('binary_content_bytes');

      final artifact = CatalogArtifact(
        artifactId: 'llama-b3500',
        artifactType: CatalogArtifactType.runtime,
        displayName: 'llama-server b3500',
        version: 'b3500',
        buildId: 'b3500',
        platform: 'windows',
        architecture: 'x64',
        fileName: 'llama-server.exe',
        sourceKind: CatalogArtifactSourceKind.remoteHttps,
        downloadUri: 'https://downloads.local/rt.zip',
        sizeBytes: 1000,
        sha256: 'a' * 64,
        license: 'MIT',
        minimumRuntimeBuild: 'b3500',
      );

      final descriptor = await installer.installArtifact(
        sourcePath: stagingDir.path,
        targetArtifact: artifact,
      );

      expect(descriptor.artifactId, equals('llama-b3500'));
      expect(
          descriptor.relativeInstallPath, equals('runtimes/llama-b3500/b3500'));

      final expectedAbsPath = pathResolver.resolveAbsoluteInstallPath(
        artifactType: CatalogArtifactType.runtime,
        artifactId: 'llama-b3500',
        buildOrVersionId: 'b3500',
      );

      expect(await Directory(expectedAbsPath).exists(), isTrue);
      expect(await File('$expectedAbsPath\\llama-server.exe').exists(), isTrue);
      expect(await stagingDir.exists(), isFalse);
    });

    test(
        'Rifiuta l installazione se la destinazione esiste già (installationConflict)',
        () async {
      final stagingDir =
          Directory(pathResolver.resolveStagingDirectory('op_101'));
      await stagingDir.create(recursive: true);

      final artifact = CatalogArtifact(
        artifactId: 'llama-b3500',
        artifactType: CatalogArtifactType.runtime,
        displayName: 'llama-server b3500',
        version: 'b3500',
        buildId: 'b3500',
        platform: 'windows',
        architecture: 'x64',
        fileName: 'llama-server.exe',
        sourceKind: CatalogArtifactSourceKind.remoteHttps,
        downloadUri: 'https://downloads.local/rt.zip',
        sizeBytes: 1000,
        sha256: 'a' * 64,
        license: 'MIT',
        minimumRuntimeBuild: 'b3500',
      );

      final targetAbsPath = pathResolver.resolveAbsoluteInstallPath(
        artifactType: CatalogArtifactType.runtime,
        artifactId: 'llama-b3500',
        buildOrVersionId: 'b3500',
      );

      // Pre-crea la destinazione
      await Directory(targetAbsPath).create(recursive: true);

      expect(
        () => installer.installArtifact(
          sourcePath: stagingDir.path,
          targetArtifact: artifact,
        ),
        throwsA(isA<ProvisioningException>().having(
          (e) => e.reason,
          'reason',
          equals(ProvisioningFailureReason.installationConflict),
        )),
      );
    });

    test(
        'Non aggiorna InstallationRecord né ActiveState durante l installazione fisica',
        () async {
      final stagingDir =
          Directory(pathResolver.resolveStagingDirectory('op_102'));
      await stagingDir.create(recursive: true);

      final artifact = CatalogArtifact(
        artifactId: 'model-q4',
        artifactType: CatalogArtifactType.model,
        displayName: 'Model Q4',
        version: '1.0',
        buildId: 'v1',
        platform: 'windows',
        architecture: 'x64',
        fileName: 'model.gguf',
        sourceKind: CatalogArtifactSourceKind.remoteHttps,
        downloadUri: 'https://downloads.local/model.gguf',
        sizeBytes: 2000,
        sha256: 'b' * 64,
        license: 'Apache-2.0',
        modelArchitecture: 'llama',
        quantization: 'Q4_K_M',
      );

      await installer.installArtifact(
        sourcePath: stagingDir.path,
        targetArtifact: artifact,
      );

      // Verifica che I/O record/state files NON siano stati creati dall installer
      expect(await File(pathResolver.installationRecordPath).exists(), isFalse);
      expect(await File(pathResolver.activeStatePath).exists(), isFalse);
    });
  });
}
