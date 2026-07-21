import 'dart:io';
import 'package:aura_core/aura_core.dart';
import 'package:test/test.dart';

void main() {
  group('AtomicArtifactInstaller Tests -', () {
    late Directory tempDir;
    late AtomicArtifactInstaller installer;
    late CatalogArtifact sampleArtifact;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('aura_installer_test_');
      installer = const AtomicArtifactInstaller(
        fileSystem: LocalProvisioningFileSystem(),
      );

      sampleArtifact = CatalogArtifact(
        artifactId: 'llama-server-b3500',
        artifactType: CatalogArtifactType.runtime,
        displayName: 'llama-server b3500',
        version: 'b3500',
        buildId: 'b3500',
        platform: 'windows',
        architecture: 'x64',
        fileName: 'llama-server.exe',
        license: 'MIT',
        sizeBytes: 1024,
        sha256: 'a' * 64,
        compression: CatalogCompressionFormat.zip,
        sourceKind: CatalogArtifactSourceKind.bundled,
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
        'Installa correttamente l artefatto da staging a target final usando un rename atomico isolato',
        () async {
      final stagingDir = Directory('${tempDir.path}\\staging\\extracted');
      await stagingDir.create(recursive: true);
      await File('${stagingDir.path}\\llama-server.exe')
          .writeAsString('binary content');

      final targetDir = '${tempDir.path}\\runtimes\\llama-server-b3500\\b3500';

      final res = await installer.installArtifact(
        artifact: sampleArtifact,
        stagingSourcePath: stagingDir.path,
        targetInstallPath: targetDir,
        conflictPolicy: ProvisioningConflictPolicy.fail,
        operationId: 'op-install-1',
      );

      expect(res.installed, isTrue);
      expect(res.alreadyInstalled, isFalse);
      expect(await File('$targetDir\\llama-server.exe').readAsString(),
          equals('binary content'));
    });

    test(
        'Lancia ProvisioningException in caso di conflitto con la destinazione finale sul filesystem',
        () async {
      final targetDir = '${tempDir.path}\\runtimes\\llama-server-b3500\\b3500';
      await Directory(targetDir).create(recursive: true);
      await File('$targetDir\\llama-server.exe')
          .writeAsString('existing content');

      expect(
        () => installer.installArtifact(
          artifact: sampleArtifact,
          stagingSourcePath: '${tempDir.path}\\staging\\extracted',
          targetInstallPath: targetDir,
          conflictPolicy: ProvisioningConflictPolicy.fail,
          operationId: 'op-install-4',
        ),
        throwsA(isA<ProvisioningException>().having(
          (e) => e.reason,
          'reason',
          equals(ProvisioningFailureReason.installationConflict),
        )),
      );
    });
  });
}
