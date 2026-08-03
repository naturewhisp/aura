import 'package:aura_core/aura_offline.dart';
import 'package:test/test.dart';

void main() {
  group('RuntimeManifest & LlamaServerConfiguration Schema Migration', () {
    test('deserializza correttamente runtime-manifest.json valido', () {
      final json = {
        'schemaVersion': 1,
        'runtimeSetId': 'aura-runtime-v0.1.0',
        'llamaCppVersion': 'b3200',
        'sourceCommit': '645044d064c10022821e6b151066e3bbcdbc21af',
        'variants': [
          {
            'id': 'win-x64-cuda',
            'acceleration': 'cuda',
            'architecture': 'x64',
            'requiredCpuFeatures': ['avx2', 'cuda12'],
            'executable': 'bin/win-x64-cuda/llama-server.exe',
            'workingDirectory': 'bin/win-x64-cuda',
            'vendorDirectories': ['bin/win-x64-cuda/vendor'],
            'files': [
              {
                'path': 'llama-server.exe',
                'sizeBytes': 1234567,
                'sha256':
                    'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
              }
            ]
          }
        ]
      };

      final manifest = RuntimeManifest.fromJson(json);
      expect(manifest.schemaVersion, equals(1));
      expect(manifest.runtimeSetId, equals('aura-runtime-v0.1.0'));
      expect(manifest.variants.length, equals(1));

      final v = manifest.findVariantById('win-x64-cuda');
      expect(v, isNotNull);
      expect(v!.acceleration, equals(RuntimeAcceleration.cuda));
      expect(v.vendorDirectories, contains('bin/win-x64-cuda/vendor'));
    });

    test(
        'migra correttamente configurazioni legacy prive di schemaVersion e source',
        () {
      final legacyJson = {
        'executablePath': r'C:\Users\test\.lmstudio\bin\llama-server.exe',
        'validationStatus': 'valid',
        'acceleration': 'cuda',
      };

      final config = LlamaServerConfiguration.fromJson(legacyJson);
      expect(config.schemaVersion, equals(1));
      expect(config.source, equals(RuntimeSource.external));
      expect(config.externalExecutablePath,
          equals(r'C:\Users\test\.lmstudio\bin\llama-server.exe'));
      expect(config.executablePath,
          equals(r'C:\Users\test\.lmstudio\bin\llama-server.exe'));
    });

    test(
        'riconosce il source bundled quando il path appartiene a una variante nota',
        () {
      final legacyJson = {
        'executablePath': r'C:\AURA\runtime\bin\win-x64-cuda\llama-server.exe',
        'validationStatus': 'valid',
        'acceleration': 'cuda',
      };

      final config = LlamaServerConfiguration.fromJson(legacyJson);
      expect(config.schemaVersion, equals(1));
      expect(config.source, equals(RuntimeSource.bundled));
      expect(config.variantId, equals('win-x64-cuda'));
    });
  });
}
