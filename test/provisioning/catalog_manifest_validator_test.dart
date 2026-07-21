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
          CatalogArtifact(
            artifactId: 'rt-bundled-b1',
            artifactType: CatalogArtifactType.runtime,
            displayName: 'Bundled Runtime',
            version: '1.0',
            buildId: 'b1',
            platform: 'windows',
            architecture: 'x64',
            fileName: 'llama-server.exe',
            sourceKind: CatalogArtifactSourceKind.bundled,
            bundledAssetId: 'bundled_llama_server_b1',
            sizeBytes: 5000000,
            sha256: 'c' * 64,
            license: 'MIT',
            minimumRuntimeBuild: 'b1',
          ),
        ],
      );

      expect(
          () => CatalogManifestValidator.validate(manifest), returnsNormally);
    });

    test('Rifiuta generatedAt non valido (non ISO-8601)', () {
      final manifest = CatalogManifest(
        schemaVersion: '1.0',
        catalogId: 'aura.bad.date',
        generatedAt: 'invalid-date-string',
        artifacts: [],
      );

      expect(
        () => CatalogManifestValidator.validate(manifest),
        throwsA(isA<ProvisioningException>().having(
          (e) => e.reason,
          'reason',
          equals(ProvisioningFailureReason.invalidCatalog),
        )),
      );
    });

    test('Rifiuta URI remote non valide, con user info o non HTTPS assolute',
        () {
      void checkBadUri(String? uri) {
        final art = CatalogArtifact(
          artifactId: 'bad-uri-art',
          artifactType: CatalogArtifactType.runtime,
          displayName: 'RT',
          version: '1.0',
          buildId: 'b1',
          platform: 'windows',
          architecture: 'x64',
          fileName: 'llama.exe',
          sourceKind: CatalogArtifactSourceKind.remoteHttps,
          downloadUri: uri,
          sizeBytes: 100,
          sha256: 'a' * 64,
          license: 'MIT',
          minimumRuntimeBuild: 'b1',
        );

        final manifest = CatalogManifest(
          schemaVersion: '1.0',
          catalogId: 'aura.baduri.catalog',
          generatedAt: '2026-07-21T20:00:00Z',
          artifacts: [art],
        );

        expect(
          () => CatalogManifestValidator.validate(manifest),
          throwsA(isA<ProvisioningException>().having(
            (e) => e.reason,
            'reason',
            equals(ProvisioningFailureReason.invalidSourceUri),
          )),
        );
      }

      checkBadUri(null);
      checkBadUri('');
      checkBadUri('http://insecure.local/rt.zip');
      checkBadUri('https://user:password@insecure.local/rt.zip');
      checkBadUri('relative/path/rt.zip');
    });

    test('Impone invarianti stringenti per sourceKind bundled e localImport',
        () {
      void checkBadSource(CatalogArtifact art) {
        final manifest = CatalogManifest(
          schemaVersion: '1.0',
          catalogId: 'aura.source.catalog',
          generatedAt: '2026-07-21T20:00:00Z',
          artifacts: [art],
        );

        expect(
          () => CatalogManifestValidator.validate(manifest),
          throwsA(isA<ProvisioningException>()),
        );
      }

      // bundled senza bundledAssetId
      checkBadSource(CatalogArtifact(
        artifactId: 'bundled-no-asset',
        artifactType: CatalogArtifactType.runtime,
        displayName: 'RT',
        version: '1.0',
        buildId: 'b1',
        platform: 'windows',
        architecture: 'x64',
        fileName: 'llama.exe',
        sourceKind: CatalogArtifactSourceKind.bundled,
        bundledAssetId: null,
        sizeBytes: 100,
        sha256: 'a' * 64,
        license: 'MIT',
        minimumRuntimeBuild: 'b1',
      ));

      // localImport con bundledAssetId o downloadUri
      checkBadSource(CatalogArtifact(
        artifactId: 'local-import-with-asset',
        artifactType: CatalogArtifactType.runtime,
        displayName: 'RT',
        version: '1.0',
        buildId: 'b1',
        platform: 'windows',
        architecture: 'x64',
        fileName: 'llama.exe',
        sourceKind: CatalogArtifactSourceKind.localImport,
        bundledAssetId: 'asset_id',
        sizeBytes: 100,
        sha256: 'a' * 64,
        license: 'MIT',
        minimumRuntimeBuild: 'b1',
      ));
    });
  });
}
