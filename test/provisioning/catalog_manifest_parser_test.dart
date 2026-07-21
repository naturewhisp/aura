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
            "sourceKind": "remoteHttps",
            "downloadUri": "https://downloads.aura.local/runtimes/llama-server-b3500.zip",
            "sizeBytes": 10485760,
            "sha256": "${'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'}",
            "compression": "zip",
            "license": "MIT",
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
            "sourceKind": "remoteHttps",
            "downloadUri": "https://downloads.aura.local/models/ministral-3b.gguf",
            "sizeBytes": 2147483648,
            "sha256": "${'a' * 64}",
            "compression": "none",
            "license": "Apache-2.0",
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
      expect(
          runtimeArt.sourceKind, equals(CatalogArtifactSourceKind.remoteHttps));
      expect(runtimeArt.compression, equals(CatalogCompressionFormat.zip));

      final modelArt = manifest.artifacts[1];
      expect(modelArt.artifactId, equals('ministral-3b-q4_k_m'));
      expect(modelArt.artifactType, equals(CatalogArtifactType.model));
      expect(modelArt.modelArchitecture, equals('ministral'));
      expect(modelArt.contextLength, equals(8192));
    });

    test(
        'Rifiuta sizeBytes o contextLength non interi strict (es. numeri decimali)',
        () {
      final jsonStr = '''
      {
        "schemaVersion": "1.0",
        "catalogId": "aura.bad.size",
        "generatedAt": "2026-07-21T20:00:00Z",
        "artifacts": [
          {
            "artifactId": "art-bad-size",
            "artifactType": "runtime",
            "displayName": "Bad Size Art",
            "version": "1.0",
            "buildId": "b1",
            "platform": "windows",
            "architecture": "x64",
            "fileName": "rt.exe",
            "sourceKind": "bundled",
            "bundledAssetId": "rt_asset",
            "sizeBytes": 100.5,
            "sha256": "${'f' * 64}",
            "license": "MIT",
            "minimumRuntimeBuild": "b1"
          }
        ]
      }
      ''';

      expect(
        () => CatalogManifestParser.parse(jsonStr),
        throwsA(isA<ProvisioningException>().having(
          (e) => e.reason,
          'reason',
          equals(ProvisioningFailureReason.catalogMalformed),
        )),
      );
    });

    test('Supporta copyWith con sentinel per l azzeramento dei campi nullable',
        () {
      final remote = CatalogArtifact(
        artifactId: 'art-1',
        artifactType: CatalogArtifactType.runtime,
        displayName: 'Art',
        version: '1.0',
        buildId: 'b1',
        platform: 'windows',
        architecture: 'x64',
        fileName: 'rt.exe',
        sourceKind: CatalogArtifactSourceKind.remoteHttps,
        downloadUri: 'https://downloads.local/rt.zip',
        sizeBytes: 100,
        sha256: 'a' * 64,
        license: 'MIT',
        minimumRuntimeBuild: 'b1',
      );

      final bundled = remote.copyWith(
        sourceKind: CatalogArtifactSourceKind.bundled,
        downloadUri: null,
        bundledAssetId: 'bundled_rt_1',
      );

      expect(bundled.sourceKind, equals(CatalogArtifactSourceKind.bundled));
      expect(bundled.downloadUri, isNull);
      expect(bundled.bundledAssetId, equals('bundled_rt_1'));
    });
  });
}
