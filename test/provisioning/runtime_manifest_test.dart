import 'package:aura_core/aura_offline.dart';
import 'package:aura_core/aura_testing.dart';
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
            'requiredCpuFeatures': ['avx2', 'fma'],
            'requiredBackendCapabilities': ['cuda12'],
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
      expect(v.requiredCpuFeatures, containsAll(['avx2', 'fma']));
      expect(v.requiredBackendCapabilities, contains('cuda12'));
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

  group('End-to-End Portable Bundled Runtime Resolution & Strict Fail-Closed',
      () {
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
          "sha256": "541b3e9daa09b20bf85fa273e5cbd3e80185aa4ec298e765db87742b70138a53"
        }
      ]
    }
  ]
}
''';

    test(
        'salva configurazione bundled -> serializza/deserializza -> cambia bundledRoot -> preflight & probe success',
        () async {
      final fs = MemoryProvisioningFileSystem();

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

      final jsonSaved = originalConfig.toJson();
      expect(jsonSaved.containsKey('executablePath'), isFalse);

      final deserializedConfig = LlamaServerConfiguration.fromJson(jsonSaved);
      expect(deserializedConfig.executablePath, isEmpty);

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

      final resolved = await bundledResolver2.resolve(deserializedConfig);
      expect(resolved, isNotNull);
      expect(
          resolved!.executablePath,
          equals(
              r'D:\InstalledPrograms\AURA_ROOT_2\runtime\bin\win-x64-cpu-avx2\llama-server.exe'));
    });

    test(
        'rifiuta la risoluzione se un file/DLL della variante viene corrotto (SHA-256 mismatch)',
        () async {
      final fs = MemoryProvisioningFileSystem();
      final root = r'C:\AURA_CORRUPTED_TEST';

      await fs.writeAsString(
          '$root\\runtime\\runtime-manifest.json', manifestContent);
      // Scrive 500 byte anziche 1000 byte dichiarati -> hash e size mismatch!
      await fs.writeBytes(
        '$root\\runtime\\bin\\win-x64-cpu-avx2\\llama-server.exe',
        List.filled(500, 0),
      );

      final pathResolver = ProvisioningPathResolver(
        appManagedRoot: r'C:\AppData\aura',
        bundledRoot: root,
      );

      final resolver = DefaultBundledRuntimeResolver(
        manifestRepository: DefaultRuntimeManifestRepository(
          fileSystem: fs,
          pathResolver: pathResolver,
        ),
        fileSystem: fs,
        pathResolver: pathResolver,
      );

      final config = LlamaServerConfiguration(
        schemaVersion: 1,
        source: RuntimeSource.bundled,
        variantId: 'win-x64-cpu-avx2',
        runtimeSetId: 'aura-runtime-v0.1.0',
        executablePath: '',
      );

      final resolved = await resolver.resolve(config);
      expect(resolved, isNull);
    });

    test(
        'ritorna null senza fallback silenzioso se variantId esplicito non esiste nel manifest',
        () async {
      final fs = MemoryProvisioningFileSystem();
      final root = r'C:\AURA_MISSING_VARIANT';

      await fs.writeAsString(
          '$root\\runtime\\runtime-manifest.json', manifestContent);
      await fs.writeBytes(
        '$root\\runtime\\bin\\win-x64-cpu-avx2\\llama-server.exe',
        List.filled(1000, 0),
      );

      final pathResolver = ProvisioningPathResolver(
        appManagedRoot: r'C:\AppData\aura',
        bundledRoot: root,
      );

      final resolver = DefaultBundledRuntimeResolver(
        manifestRepository: DefaultRuntimeManifestRepository(
          fileSystem: fs,
          pathResolver: pathResolver,
        ),
        fileSystem: fs,
        pathResolver: pathResolver,
      );

      final config = LlamaServerConfiguration(
        schemaVersion: 1,
        source: RuntimeSource.bundled,
        variantId:
            'win-x64-cuda', // Richiede esplicitamente CUDA, non presente nel manifest
        runtimeSetId: 'aura-runtime-v0.1.0',
        executablePath: '',
      );

      final resolved = await resolver.resolve(config);
      expect(resolved, isNull);
    });

    test(
        'ritorna null se runtimeSetId della configurazione differisce dal manifest',
        () async {
      final fs = MemoryProvisioningFileSystem();
      final root = r'C:\AURA_NEW_RUNTIME_SET';

      await fs.writeAsString(
          '$root\\runtime\\runtime-manifest.json', manifestContent);
      await fs.writeBytes(
        '$root\\runtime\\bin\\win-x64-cpu-avx2\\llama-server.exe',
        List.filled(1000, 0),
      );

      final pathResolver = ProvisioningPathResolver(
        appManagedRoot: r'C:\AppData\aura',
        bundledRoot: root,
      );

      final resolver = DefaultBundledRuntimeResolver(
        manifestRepository: DefaultRuntimeManifestRepository(
          fileSystem: fs,
          pathResolver: pathResolver,
        ),
        fileSystem: fs,
        pathResolver: pathResolver,
      );

      final config = LlamaServerConfiguration(
        schemaVersion: 1,
        source: RuntimeSource.bundled,
        variantId: 'win-x64-cpu-avx2',
        runtimeSetId: 'aura-runtime-v0.0.9-old', // runtimeSetId obsoleto
        executablePath: '',
      );

      final resolved = await resolver.resolve(config);
      expect(resolved, isNull);
    });
  });

  group('Real Manifest & DefaultCpuFeatureDetector End-to-End Discovery', () {
    test(
        'convalida tutte e tre le varianti del manifest reale con DefaultCpuFeatureDetector',
        () async {
      final fs = MemoryProvisioningFileSystem();

      const realManifestContent = '''
{
  "schemaVersion": 1,
  "runtimeSetId": "aura-runtime-v0.1.0",
  "llamaCppVersion": "b10255",
  "sourceCommit": "66fa168a5",
  "variants": [
    {
      "id": "win-x64-cuda",
      "acceleration": "cuda",
      "architecture": "x64",
      "requiredCpuFeatures": ["avx2", "fma"],
      "requiredBackendCapabilities": ["cuda12"],
      "executable": "bin/win-x64-cuda/llama-server.exe",
      "workingDirectory": "bin/win-x64-cuda",
      "vendorDirectories": ["bin/win-x64-cuda/vendor"],
      "files": [
        {
          "path": "bin/win-x64-cuda/llama-server.exe",
          "sizeBytes": 1000,
          "sha256": "541b3e9daa09b20bf85fa273e5cbd3e80185aa4ec298e765db87742b70138a53"
        }
      ]
    },
    {
      "id": "win-x64-vulkan",
      "acceleration": "vulkan",
      "architecture": "x64",
      "requiredCpuFeatures": ["avx2"],
      "requiredBackendCapabilities": ["vulkan"],
      "executable": "bin/win-x64-vulkan/llama-server.exe",
      "workingDirectory": "bin/win-x64-vulkan",
      "vendorDirectories": ["bin/win-x64-vulkan/vendor"],
      "files": [
        {
          "path": "bin/win-x64-vulkan/llama-server.exe",
          "sizeBytes": 1000,
          "sha256": "541b3e9daa09b20bf85fa273e5cbd3e80185aa4ec298e765db87742b70138a53"
        }
      ]
    },
    {
      "id": "win-x64-cpu-avx2",
      "acceleration": "cpu",
      "architecture": "x64",
      "requiredCpuFeatures": ["avx2", "fma"],
      "requiredBackendCapabilities": [],
      "executable": "bin/win-x64-cpu-avx2/llama-server.exe",
      "workingDirectory": "bin/win-x64-cpu-avx2",
      "vendorDirectories": [],
      "files": [
        {
          "path": "bin/win-x64-cpu-avx2/llama-server.exe",
          "sizeBytes": 1000,
          "sha256": "541b3e9daa09b20bf85fa273e5cbd3e80185aa4ec298e765db87742b70138a53"
        }
      ]
    }
  ]
}
''';

      final root = r'C:\AURA_REAL_MANIFEST_TEST';
      await fs.writeAsString(
          '$root\\runtime\\runtime-manifest.json', realManifestContent);
      await fs.writeBytes('$root\\runtime\\bin\\win-x64-cuda\\llama-server.exe',
          List.filled(1000, 0));
      await fs.writeBytes(
          '$root\\runtime\\bin\\win-x64-vulkan\\llama-server.exe',
          List.filled(1000, 0));
      await fs.writeBytes(
          '$root\\runtime\\bin\\win-x64-cpu-avx2\\llama-server.exe',
          List.filled(1000, 0));

      final pathResolver = ProvisioningPathResolver(
        appManagedRoot: r'C:\AppData\aura',
        bundledRoot: root,
      );

      final service = DefaultLlamaServerDependencyService(
        configurationRepository: JsonModelConfigurationRepository(
          storeDirectoryPath: r'C:\AppData\aura\store',
          fileSystem: fs,
          lock: InMemoryProvisioningLock(),
        ),
        fileSystem: fs,
        pathResolver: pathResolver,
        processLauncher: FakeProcessLauncher(
          processFactory: () {
            final proc = FakeManagedProcess();
            proc.emitStdout('version: 10255 (66fa168a5)\nbuild: 10255');
            proc.completeExit(0);
            return proc;
          },
        ),
        cpuFeatureDetector: const DefaultCpuFeatureDetector(),
      );

      final detection = await service.detect();
      expect(detection.effectiveCandidate, isNotNull);
    });
  });
}
