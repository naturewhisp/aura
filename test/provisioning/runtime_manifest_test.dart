import 'package:aura_core/aura_offline.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

import 'provisioning_test_helpers.dart';

void main() {
  group('RuntimeManifest & Strict Validation', () {
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

    test('rigetta manifest contenenti percorsi assoluti o path traversal', () {
      final json = {
        'schemaVersion': 1,
        'runtimeSetId': 'aura-runtime-v0.1.0',
        'variants': [
          {
            'id': 'win-x64-cuda',
            'acceleration': 'cuda',
            'executable': r'C:\System32\cmd.exe',
            'workingDirectory': 'bin/win-x64-cuda',
            'files': [
              {
                'path': '../secret.txt',
                'sizeBytes': 100,
                'sha256':
                    'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
              }
            ]
          }
        ]
      };

      expect(() => RuntimeManifest.fromJson(json),
          throwsA(isA<RuntimeManifestException>()));
    });

    test('rigetta manifest con varianti o file duplicati', () {
      final json = {
        'schemaVersion': 1,
        'runtimeSetId': 'aura-runtime-v0.1.0',
        'variants': [
          {
            'id': 'win-x64-cuda',
            'acceleration': 'cuda',
            'executable': 'llama-server.exe',
            'workingDirectory': '.',
            'files': [
              {
                'path': 'llama-server.exe',
                'sizeBytes': 100,
                'sha256':
                    'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
              },
              {
                'path': 'llama-server.exe',
                'sizeBytes': 100,
                'sha256':
                    'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
              }
            ]
          }
        ]
      };

      expect(() => RuntimeManifest.fromJson(json),
          throwsA(isA<RuntimeManifestException>()));
    });
  });

  group('RuntimeBundleIntegrityVerifier Unit Test', () {
    final fs = MemoryProvisioningFileSystem();
    final verifier = DefaultRuntimeBundleIntegrityVerifier(fileSystem: fs);

    test('verifica con successo dimensione e SHA-256 dei file di variante',
        () async {
      const contentBytes = [1, 2, 3, 4, 5];
      final hashStr = sha256.convert(contentBytes).toString().toLowerCase();

      await fs.writeBytes(r'C:\AURA\runtime\llama-server.exe', contentBytes);

      final variant = RuntimeVariantDescriptor(
        id: 'win-x64-cpu-avx2',
        acceleration: RuntimeAcceleration.cpu,
        architecture: 'x64',
        requiredCpuFeatures: const ['avx2'],
        executable: 'llama-server.exe',
        workingDirectory: '.',
        vendorDirectories: const [],
        files: [
          RuntimeFileEntry(
            path: 'llama-server.exe',
            sizeBytes: 5,
            sha256: hashStr,
          ),
        ],
      );

      final result = await verifier.verifyVariant(
        variant: variant,
        runtimeRootPath: r'C:\AURA\runtime',
      );

      expect(result.isValid, isTrue);
      expect(result.missingFiles, isEmpty);
      expect(result.corruptedFiles, isEmpty);
    });

    test('rileva file mancante o corrotto nel bundle', () async {
      await fs.writeBytes(r'C:\AURA\runtime\llama-server.exe', [1, 2, 3]);

      const variant = RuntimeVariantDescriptor(
        id: 'win-x64-cpu-avx2',
        acceleration: RuntimeAcceleration.cpu,
        architecture: 'x64',
        requiredCpuFeatures: ['avx2'],
        executable: 'llama-server.exe',
        workingDirectory: '.',
        vendorDirectories: [],
        files: [
          RuntimeFileEntry(
            path: 'llama-server.exe',
            sizeBytes: 100, // Dimensione errata
            sha256:
                'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
          ),
        ],
      );

      final result = await verifier.verifyVariant(
        variant: variant,
        runtimeRootPath: r'C:\AURA\runtime',
      );

      expect(result.isValid, isFalse);
      expect(result.corruptedFiles, isNotEmpty);
    });
  });

  group('LlamaServerConfiguration Portable Persistence & CopyWith', () {
    test(
        'serializza in formato portabile senza salvare path assoluto statico per source bundled',
        () {
      const config = LlamaServerConfiguration(
        schemaVersion: 1,
        source: RuntimeSource.bundled,
        variantId: 'win-x64-cuda',
        runtimeSetId: 'aura-runtime-v0.1.0',
        executablePath: r'C:\AURA\runtime\bin\win-x64-cuda\llama-server.exe',
        validationStatus: LlamaServerValidationStatus.valid,
        acceleration: RuntimeAcceleration.cuda,
      );

      final json = config.toJson();
      expect(json['source'], equals('bundled'));
      expect(json['variantId'], equals('win-x64-cuda'));
      expect(json['runtimeSetId'], equals('aura-runtime-v0.1.0'));
      expect(json.containsKey('executablePath'), isFalse);
    });

    test(
        'copyWith preserva tutti i campi estesi inclusi source, variantId e runtimeSetId',
        () {
      const config = LlamaServerConfiguration(
        schemaVersion: 1,
        source: RuntimeSource.bundled,
        variantId: 'win-x64-cuda',
        runtimeSetId: 'aura-runtime-v0.1.0',
        executablePath: r'C:\AURA\runtime\bin\win-x64-cuda\llama-server.exe',
      );

      final updated = config.copyWith(
        validationStatus: LlamaServerValidationStatus.valid,
      );

      expect(updated.schemaVersion, equals(1));
      expect(updated.source, equals(RuntimeSource.bundled));
      expect(updated.variantId, equals('win-x64-cuda'));
      expect(updated.runtimeSetId, equals('aura-runtime-v0.1.0'));
      expect(
          updated.validationStatus, equals(LlamaServerValidationStatus.valid));
    });
  });
}
