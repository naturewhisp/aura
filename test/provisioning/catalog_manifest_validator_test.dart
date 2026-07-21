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
            downloadUri: 'https://downloads.aura.local/rt.zip',
            sizeBytes: 5000000,
            sha256: 'a' * 64,
            license: 'MIT',
            source: 'remoteHttps',
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
            downloadUri: 'https://downloads.aura.local/model.gguf',
            sizeBytes: 100000000,
            sha256: 'b' * 64,
            license: 'Apache-2.0',
            source: 'remoteHttps',
            modelArchitecture: 'llama',
            quantization: 'Q4_K_M',
          ),
        ],
      );

      expect(
          () => CatalogManifestValidator.validate(manifest), returnsNormally);
    });

    test('Rifiuta catalogo con catalogId vuoto', () {
      final manifest = CatalogManifest(
        schemaVersion: '1.0',
        catalogId: '   ',
        generatedAt: '2026-07-21',
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

    test('Rifiuta catalogo con artifactId duplicato', () {
      final art1 = CatalogArtifact(
        artifactId: 'dup-id',
        artifactType: CatalogArtifactType.runtime,
        displayName: 'Runtime 1',
        version: '1.0',
        buildId: 'b1',
        platform: 'windows',
        architecture: 'x64',
        fileName: 'llama1.exe',
        sizeBytes: 100,
        sha256: 'a' * 64,
        license: 'MIT',
        source: 'bundled',
        minimumRuntimeBuild: 'b1',
      );

      final art2 = CatalogArtifact(
        artifactId: 'dup-id',
        artifactType: CatalogArtifactType.runtime,
        displayName: 'Runtime 2',
        version: '1.0',
        buildId: 'b2',
        platform: 'windows',
        architecture: 'x64',
        fileName: 'llama2.exe',
        sizeBytes: 200,
        sha256: 'b' * 64,
        license: 'MIT',
        source: 'bundled',
        minimumRuntimeBuild: 'b2',
      );

      final manifest = CatalogManifest(
        schemaVersion: '1.0',
        catalogId: 'aura.dup.catalog',
        generatedAt: '2026-07-21',
        artifacts: [art1, art2],
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

    test('Rifiuta hash SHA-256 non valido (non di 64 caratteri esadecimali)',
        () {
      final art = CatalogArtifact(
        artifactId: 'bad-hash',
        artifactType: CatalogArtifactType.runtime,
        displayName: 'Runtime',
        version: '1.0',
        buildId: 'b1',
        platform: 'windows',
        architecture: 'x64',
        fileName: 'llama.exe',
        sizeBytes: 100,
        sha256: 'not-a-valid-sha256',
        license: 'MIT',
        source: 'bundled',
        minimumRuntimeBuild: 'b1',
      );

      final manifest = CatalogManifest(
        schemaVersion: '1.0',
        catalogId: 'aura.badhash.catalog',
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
    });

    test('Rifiuta downloadUri non HTTPS', () {
      final art = CatalogArtifact(
        artifactId: 'http-uri',
        artifactType: CatalogArtifactType.runtime,
        displayName: 'Runtime',
        version: '1.0',
        buildId: 'b1',
        platform: 'windows',
        architecture: 'x64',
        fileName: 'llama.exe',
        downloadUri: 'http://insecure.downloads.com/rt.zip',
        sizeBytes: 100,
        sha256: 'a' * 64,
        license: 'MIT',
        source: 'remoteHttps',
        minimumRuntimeBuild: 'b1',
      );

      final manifest = CatalogManifest(
        schemaVersion: '1.0',
        catalogId: 'aura.http.catalog',
        generatedAt: '2026-07-21',
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
    });

    test(
        'Rifiuta fileName con path traversal, separatori o nomi riservati Windows',
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
          sizeBytes: 100,
          sha256: 'a' * 64,
          license: 'MIT',
          source: 'bundled',
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
    });

    test('Rifiuta modello senza modelArchitecture o quantization', () {
      final art = CatalogArtifact(
        artifactId: 'missing-arch-model',
        artifactType: CatalogArtifactType.model,
        displayName: 'Model',
        version: '1.0',
        buildId: 'v1',
        platform: 'windows',
        architecture: 'x64',
        fileName: 'model.gguf',
        sizeBytes: 100,
        sha256: 'a' * 64,
        license: 'MIT',
        source: 'bundled',
      );

      final manifest = CatalogManifest(
        schemaVersion: '1.0',
        catalogId: 'aura.model.catalog',
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
    });

    test('Rifiuta runtime senza minimumRuntimeBuild', () {
      final art = CatalogArtifact(
        artifactId: 'missing-build-runtime',
        artifactType: CatalogArtifactType.runtime,
        displayName: 'Runtime',
        version: '1.0',
        buildId: 'b1',
        platform: 'windows',
        architecture: 'x64',
        fileName: 'llama.exe',
        sizeBytes: 100,
        sha256: 'a' * 64,
        license: 'MIT',
        source: 'bundled',
      );

      final manifest = CatalogManifest(
        schemaVersion: '1.0',
        catalogId: 'aura.runtime.catalog',
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
    });
  });
}
