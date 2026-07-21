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
      installer = const AtomicArtifactInstaller();

      sampleArtifact = CatalogArtifact(
        artifactId: 'llama-server-b3500',
        artifactType: CatalogArtifactType.runtime,
        displayName: 'llama-server b3500',
        version: 'b3500',
        buildId: 'b3500',
        platform: 'windows',
        architecture: 'x64',
        fileName: 'llama-server-b3500.zip',
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

    test('Installa correttamente l artefatto da staging a target final',
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
      );

      expect(res.installed, isTrue);
      expect(res.alreadyInstalled, isFalse);
      expect(await File('$targetDir\\llama-server.exe').readAsString(),
          equals('binary content'));
    });

    test(
        'Gestisce il conflitto con returnAlreadyInstalled se la directory esiste già',
        () async {
      final targetDir = '${tempDir.path}\\runtimes\\llama-server-b3500\\b3500';
      await Directory(targetDir).create(recursive: true);

      final res = await installer.installArtifact(
        artifact: sampleArtifact,
        stagingSourcePath: '${tempDir.path}\\staging\\extracted',
        targetInstallPath: targetDir,
        conflictPolicy: ProvisioningConflictPolicy.returnAlreadyInstalled,
      );

      expect(res.installed, isFalse);
      expect(res.alreadyInstalled, isTrue);
    });

    test('Lancia ProvisioningException in caso di conflitto con policy fail',
        () async {
      final targetDir = '${tempDir.path}\\runtimes\\llama-server-b3500\\b3500';
      await Directory(targetDir).create(recursive: true);

      expect(
        () => installer.installArtifact(
          artifact: sampleArtifact,
          stagingSourcePath: '${tempDir.path}\\staging\\extracted',
          targetInstallPath: targetDir,
          conflictPolicy: ProvisioningConflictPolicy.fail,
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
