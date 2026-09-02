import 'dart:typed_data';
import 'package:aura_core/aura_testing.dart';
import 'package:test/test.dart';

import '../provisioning_test_helpers.dart';

void main() {
  group('Tranche 6.4d — ArtifactImportInspector Tests', () {
    late MemoryProvisioningFileSystem fileSystem;
    late ArtifactImportInspector inspector;
    late CatalogManifest manifest;

    setUp(() {
      fileSystem = MemoryProvisioningFileSystem();
      inspector = ArtifactImportInspector(fileSystem: fileSystem);

      manifest = CatalogManifest(
        schemaVersion: '1.0',
        catalogId: 'aura-official-test',
        generatedAt: '2026-07-27T20:00:00Z',
        artifacts: [
          CatalogArtifact(
            artifactId: 'model-small-q4',
            artifactType: CatalogArtifactType.model,
            displayName: 'Small Q4 Model',
            version: '1.0.0',
            buildId: 'v1',
            platform: 'all',
            architecture: 'gguf',
            fileName: 'small_model.gguf',
            sourceKind: CatalogArtifactSourceKind.remoteHttps,
            sizeBytes: 1000,
            sha256:
                'a1b2c3d4e5f60000000000000000000000000000000000000000000000000000',
            license: 'apache-2.0',
          ),
          CatalogArtifact(
            artifactId: 'model-large-q4',
            artifactType: CatalogArtifactType.model,
            displayName: 'Large Q4 Model',
            version: '2.0.0',
            buildId: 'v1',
            platform: 'all',
            architecture: 'gguf',
            fileName: 'large_model.gguf',
            sourceKind: CatalogArtifactSourceKind.remoteHttps,
            sizeBytes: 5000,
            sha256:
                'b2c3d4e5f6000000000000000000000000000000000000000000000000000000',
            license: 'apache-2.0',
          ),
        ],
      );
    });

    test(
        'Detects valid GGUF magic header bytes 0x47, 0x47, 0x55, 0x46 and filters candidate by sizeBytes',
        () async {
      final headerBytes = Uint8List(1000);
      headerBytes[0] = 0x47; // 'G'
      headerBytes[1] = 0x47; // 'G'
      headerBytes[2] = 0x55; // 'U'
      headerBytes[3] = 0x46; // 'F'

      final byteData = ByteData.sublistView(headerBytes);
      byteData.setUint32(4, 3, Endian.little);

      const filePath = r'C:\Users\TestUser\Downloads\custom_model.gguf';
      await fileSystem.appendBytes(filePath, headerBytes);

      final result = await inspector.inspectLocalFile(
        filePath: filePath,
        manifest: manifest,
      );

      expect(result.isGgufHeaderValid, isTrue);
      expect(result.ggufVersion, equals(3));
      expect(result.sizeBytes, equals(1000));
      expect(result.candidateArtifacts.length, equals(1));
      expect(
          result.candidateArtifacts.first.artifactId, equals('model-small-q4'));
      expect(result.isEligibleForImport, isTrue);
    });

    test('Rejects file with invalid magic header bytes', () async {
      final headerBytes = Uint8List(1000);
      headerBytes[0] = 0x50; // 'P'
      headerBytes[1] = 0x4B; // 'K' (Zip magic)

      const filePath = r'C:\Users\TestUser\Downloads\not_gguf.zip';
      await fileSystem.appendBytes(filePath, headerBytes);

      final result = await inspector.inspectLocalFile(
        filePath: filePath,
        manifest: manifest,
      );

      expect(result.isGgufHeaderValid, isFalse);
      expect(result.isEligibleForImport, isFalse);
    });
  });
}
