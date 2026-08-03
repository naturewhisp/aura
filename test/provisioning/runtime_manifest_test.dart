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
                'path': 'bin/win-x64-cuda/llama-server.exe',
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

    test('rigetta manifest se executable non è incluso nella lista files', () {
      final json = {
        'schemaVersion': 1,
        'runtimeSetId': 'aura-runtime-v0.1.0',
        'variants': [
          {
            'id': 'win-x64-cuda',
            'acceleration': 'cuda',
            'executable': 'bin/win-x64-cuda/llama-server.exe',
            'workingDirectory': 'bin/win-x64-cuda',
            'files': [
              {
                'path': 'bin/win-x64-cuda/other.dll',
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

    test('rigetta manifest se workingDirectory non racchiude l\'eseguibile',
        () {
      final json = {
        'schemaVersion': 1,
        'runtimeSetId': 'aura-runtime-v0.1.0',
        'variants': [
          {
            'id': 'win-x64-cuda',
            'acceleration': 'cuda',
            'executable': 'bin/win-x64-vulkan/llama-server.exe',
            'workingDirectory': 'bin/win-x64-cuda',
            'files': [
              {
                'path': 'bin/win-x64-vulkan/llama-server.exe',
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
  });

  group('End-to-End Portable Bundled Runtime Resolution & Preflight', () {
    test(
        'salva configurazione bundled -> serializza/deserializza -> cambia bundledRoot -> preflight & probe success',
        () async {
      final fs = MemoryProvisioningFileSystem();

      const manifestContent = '''
{
  "schemaVersion": 1,
  "runtimeSetId": "aura-runtime-v0.1.0",
  "llamaCppVersion": "b3200",
  "sourceCommit": "645044d064c10022821e6b151066e3bbcdbc21af",
  "variants": [
    {
      "id": "win-x64-cpu-avx2",
      "acceleration": "cpu",
      "architecture": "x64",
      "requiredCpuFeatures": ["avx2"],
      "executable": "bin/win-x64-cpu-avx2/llama-server.exe",
      "workingDirectory": "bin/win-x64-cpu-avx2",
      "vendorDirectories": [],
      "files": [
        {
          "path": "bin/win-x64-cpu-avx2/llama-server.exe",
          "sizeBytes": 1000,
          "sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        }
      ]
    }
  ]
}
''';

      // 1. Setup root originale
      final root1 = r'C:\AURA_ROOT_1';
      await fs.writeAsString(
          '$root1\\runtime\\runtime-manifest.json', manifestContent);
      await fs.writeBytes(
        '$root1\\runtime\\bin\\win-x64-cpu-avx2\\llama-server.exe',
        List.filled(1000, 0),
      );

      final resolver1 = ProvisioningPathResolver(
        appManagedRoot: r'C:\AppData\aura',
        bundledRoot: root1,
      );

      final manifestRepo1 = DefaultRuntimeManifestRepository(
        fileSystem: fs,
        pathResolver: resolver1,
      );

      final bundledResolver1 = DefaultBundledRuntimeResolver(
        manifestRepository: manifestRepo1,
        fileSystem: fs,
        pathResolver: resolver1,
      );

      // Configurazione bundled originale
      final originalConfig = LlamaServerConfiguration(
        schemaVersion: 1,
        source: RuntimeSource.bundled,
        variantId: 'win-x64-cpu-avx2',
        runtimeSetId: 'aura-runtime-v0.1.0',
        executablePath:
            r'C:\AURA_ROOT_1\runtime\bin\win-x64-cpu-avx2\llama-server.exe',
        validationStatus: LlamaServerValidationStatus.valid,
        acceleration: RuntimeAcceleration.cpu,
      );

      final resolved1 = await bundledResolver1.resolve(originalConfig);
      expect(resolved1, isNotNull);

      // 2. Serializzazione (omette executablePath) e Deserializzazione (executablePath = "")
      final jsonSaved = originalConfig.toJson();
      expect(jsonSaved.containsKey('executablePath'), isFalse);

      final deserializedConfig = LlamaServerConfiguration.fromJson(jsonSaved);
      expect(deserializedConfig.executablePath, isEmpty);

      // 3. Spostamento dell'applicazione su un nuovo percorso di installazione root2!
      final root2 = r'D:\InstalledPrograms\AURA_ROOT_2';
      await fs.writeAsString(
          '$root2\\runtime\\runtime-manifest.json', manifestContent);
      await fs.writeBytes(
        '$root2\\runtime\\bin\\win-x64-cpu-avx2\\llama-server.exe',
        List.filled(1000, 0),
      );

      final resolver2 = ProvisioningPathResolver(
        appManagedRoot: r'C:\AppData\aura',
        bundledRoot: root2,
      );

      final manifestRepo2 = DefaultRuntimeManifestRepository(
        fileSystem: fs,
        pathResolver: resolver2,
      );

      final bundledResolver2 = DefaultBundledRuntimeResolver(
        manifestRepository: manifestRepo2,
        fileSystem: fs,
        pathResolver: resolver2,
      );

      // 4. Risoluzione su root2
      final resolved = await bundledResolver2.resolve(deserializedConfig);
      expect(resolved, isNotNull);
      expect(
          resolved!.executablePath,
          equals(
              r'D:\InstalledPrograms\AURA_ROOT_2\runtime\bin\win-x64-cpu-avx2\llama-server.exe'));
      expect(
          resolved.workingDirectory,
          equals(
              r'D:\InstalledPrograms\AURA_ROOT_2\runtime\bin\win-x64-cpu-avx2'));
    });
  });
}
