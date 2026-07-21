import 'package:aura_core/aura_core.dart';
import 'package:test/test.dart';

void main() {
  group('CatalogManifestValidator Tests -', () {
    test('Supera la validazione su un catalogo manifest completamente valido',
        () {
      final manifest = CatalogManifest(
        schemaVersion: '1.0',
        catalogId: 'aura.valid.catalog',
        generatedAt: '2026-07-21T20:00:00Z',
        artifacts: [
          CatalogArtifact(
            artifactId: 'rt-win-x64-b1',
            artifactType: CatalogArtifactType.runtime,
            displayName: 'Runtime',
            version: '1.0',
            buildId: 'b1',
            platform: 'windows',
            architecture: 'x64',
            fileName: 'llama-server.exe',
            sourceKind: CatalogArtifactSourceKind.remoteHttps,
            downloadUri: 'https://downloads.aura.local/rt.zip',
            sizeBytes: 5000000,
            sha256: 'a' * 64,
            license: 'MIT',
            minimumRuntimeBuild: 'b1',
          ),
          CatalogArtifact(
            artifactId: 'model-q4',
            artifactType: CatalogArtifactType.model,
            displayName: 'Model Q4',
            version: '1.0',
            buildId: 'v1',
            platform: 'windows',
            architecture: 'x64',
            fileName: 'model.gguf',
            sourceKind: CatalogArtifactSourceKind.remoteHttps,
            downloadUri: 'https://downloads.aura.local/model.gguf',
            sizeBytes: 100000000,
            sha256: 'b' * 64,
            license: 'Apache-2.0',
            modelArchitecture: 'llama',
            quantization: 'Q4_K_M',
          ),
        ],
      );

      expect(
          () => CatalogManifestValidator.validate(manifest), returnsNormally);
    });

    test(
        'Verifica coerenza tra sourceKind e presenza di downloadUri / bundledAssetId',
        () {
      void checkBadSource(CatalogArtifact art) {
        final manifest = CatalogManifest(
          schemaVersion: '1.0',
          catalogId: 'aura.source.catalog',
          generatedAt: '2026-07-21',
          artifacts: [art],
        );
        expect(
          () => CatalogManifestValidator.validate(manifest),
          throwsA(isA<ProvisioningException>()),
        );
      }

      // remoteHttps senza downloadUri
      checkBadSource(CatalogArtifact(
        artifactId: 'no-uri',
        artifactType: CatalogArtifactType.runtime,
        displayName: 'RT',
        version: '1.0',
        buildId: 'b1',
        platform: 'windows',
        architecture: 'x64',
        fileName: 'llama.exe',
        sourceKind: CatalogArtifactSourceKind.remoteHttps,
        sizeBytes: 100,
        sha256: 'a' * 64,
        license: 'MIT',
        minimumRuntimeBuild: 'b1',
      ));

      // bundled con downloadUri remoto
      checkBadSource(CatalogArtifact(
        artifactId: 'bundled-uri',
        artifactType: CatalogArtifactType.runtime,
        displayName: 'RT',
        version: '1.0',
        buildId: 'b1',
        platform: 'windows',
        architecture: 'x64',
        fileName: 'llama.exe',
        sourceKind: CatalogArtifactSourceKind.bundled,
        downloadUri: 'https://insecure.local/rt.zip',
        sizeBytes: 100,
        sha256: 'a' * 64,
        license: 'MIT',
        minimumRuntimeBuild: 'b1',
      ));
    });

    test(
        'Rifiuta fileName con separatori (/, \\), path traversal (..), caratteri invalidi o spazi finali',
        () {
      void checkBadFileName(String fileName) {
        final art = CatalogArtifact(
          artifactId: 'bad-file',
          artifactType: CatalogArtifactType.runtime,
          displayName: 'Runtime',
          version: '1.0',
          buildId: 'b1',
          platform: 'windows',
          architecture: 'x64',
          fileName: fileName,
          sourceKind: CatalogArtifactSourceKind.bundled,
          sizeBytes: 100,
          sha256: 'a' * 64,
          license: 'MIT',
          minimumRuntimeBuild: 'b1',
        );

        final manifest = CatalogManifest(
          schemaVersion: '1.0',
          catalogId: 'aura.filename.catalog',
          generatedAt: '2026-07-21',
          artifacts: [art],
        );

        expect(
          () => CatalogManifestValidator.validate(manifest),
          throwsA(isA<ProvisioningException>().having(
            (e) => e.reason,
            'reason',
            equals(ProvisioningFailureReason.invalidCatalog),
          )),
        );
      }

      checkBadFileName('../llama.exe');
      checkBadFileName(r'subfolder\llama.exe');
      checkBadFileName('CON.exe');
      checkBadFileName('NUL');
      checkBadFileName('.hiddenfile');
      checkBadFileName('file_with_trailing_space.exe ');
      checkBadFileName('file<invalid>.exe');
      checkBadFileName('file:stream');
    });
  });
}
