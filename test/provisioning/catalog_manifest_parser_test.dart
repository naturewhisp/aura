import 'package:aura_core/aura_core.dart';
import 'package:test/test.dart';

void main() {
  group('CatalogManifestParser Tests -', () {
    test('Parsea correttamente un manifest JSON valido di versione 1.0', () {
      final jsonStr = '''
      {
        "schemaVersion": "1.0",
        "catalogId": "aura.official.catalog.v1",
        "generatedAt": "2026-07-21T20:00:00Z",
        "artifacts": [
          {
            "artifactId": "llama-server-win-x64-b3500",
            "artifactType": "runtime",
            "displayName": "llama-server Windows x64 Build b3500",
            "version": "b3500",
            "buildId": "b3500",
            "platform": "windows",
            "architecture": "x64",
            "fileName": "llama-server.exe",
            "downloadUri": "https://downloads.aura.local/runtimes/llama-server-b3500.zip",
            "sizeBytes": 10485760,
            "sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
            "compression": "zip",
            "license": "MIT",
            "source": "remoteHttps",
            "minimumRuntimeBuild": "b3500"
          },
          {
            "artifactId": "ministral-3b-q4_k_m",
            "artifactType": "model",
            "displayName": "Ministral 3B Instruct Q4_K_M",
            "version": "3.0",
            "buildId": "q4_k_m",
            "platform": "windows",
            "architecture": "x64",
            "fileName": "ministral-3b-instruct-q4_k_m.gguf",
            "downloadUri": "https://downloads.aura.local/models/ministral-3b.gguf",
            "sizeBytes": 2147483648,
            "sha256": "${'a' * 64}",
            "compression": "none",
            "license": "Apache-2.0",
            "source": "remoteHttps",
            "modelArchitecture": "ministral",
            "quantization": "Q4_K_M",
            "contextLength": 8192
          }
        ]
      }
      ''';

      final manifest = CatalogManifestParser.parse(jsonStr);
      expect(manifest.schemaVersion, equals('1.0'));
      expect(manifest.catalogId, equals('aura.official.catalog.v1'));
      expect(manifest.artifacts.length, equals(2));

      final runtimeArt = manifest.artifacts[0];
      expect(runtimeArt.artifactId, equals('llama-server-win-x64-b3500'));
      expect(runtimeArt.artifactType, equals(CatalogArtifactType.runtime));
      expect(runtimeArt.compression, equals(CatalogCompressionFormat.zip));

      final modelArt = manifest.artifacts[1];
      expect(modelArt.artifactId, equals('ministral-3b-q4_k_m'));
      expect(modelArt.artifactType, equals(CatalogArtifactType.model));
      expect(modelArt.modelArchitecture, equals('ministral'));
      expect(modelArt.contextLength, equals(8192));
    });

    test(
        'Lancia ProvisioningException quando il contenuto JSON è vuoto o invalido',
        () {
      expect(
        () => CatalogManifestParser.parse(''),
        throwsA(isA<ProvisioningException>().having(
          (e) => e.reason,
          'reason',
          equals(ProvisioningFailureReason.catalogMalformed),
        )),
      );

      expect(
        () => CatalogManifestParser.parse('{invalid json'),
        throwsA(isA<ProvisioningException>().having(
          (e) => e.reason,
          'reason',
          equals(ProvisioningFailureReason.catalogMalformed),
        )),
      );

      expect(
        () =>
            CatalogManifestParser.parse('["list", "instead", "of", "object"]'),
        throwsA(isA<ProvisioningException>().having(
          (e) => e.reason,
          'reason',
          equals(ProvisioningFailureReason.catalogMalformed),
        )),
      );
    });

    test(
        'Lancia ProvisioningException con unsupportedSchemaVersion per versione diversa da 1.0',
        () {
      final jsonStr = '''
      {
        "schemaVersion": "2.0",
        "catalogId": "aura.future.catalog",
        "artifacts": []
      }
      ''';

      expect(
        () => CatalogManifestParser.parse(jsonStr),
        throwsA(isA<ProvisioningException>().having(
          (e) => e.reason,
          'reason',
          equals(ProvisioningFailureReason.unsupportedSchemaVersion),
        )),
      );
    });

    test('Supporta tolleranza controllata verso campi JSON sconosciuti', () {
      final jsonStr = '''
      {
        "schemaVersion": "1.0",
        "catalogId": "aura.unknown.fields",
        "generatedAt": "2026-07-21T20:00:00Z",
        "futureExtensionField": 12345,
        "artifacts": [
          {
            "artifactId": "valid-art",
            "artifactType": "runtime",
            "displayName": "Valid Art",
            "version": "1.0",
            "buildId": "b1",
            "platform": "windows",
            "architecture": "x64",
            "fileName": "rt.exe",
            "sizeBytes": 100,
            "sha256": "${'f' * 64}",
            "license": "MIT",
            "source": "bundled",
            "minimumRuntimeBuild": "b1",
            "unknownArtifactField": "ignored"
          }
        ]
      }
      ''';

      final manifest = CatalogManifestParser.parse(jsonStr);
      expect(manifest.catalogId, equals('aura.unknown.fields'));
      expect(manifest.artifacts.first.artifactId, equals('valid-art'));
    });
  });
}
