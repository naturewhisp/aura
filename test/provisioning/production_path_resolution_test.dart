import 'dart:io';
import 'package:aura_core/aura_offline.dart';
import 'package:test/test.dart';
import 'provisioning_test_helpers.dart';

void main() {
  group('Phase 6.10 — Production Path Resolution & Hardcoded Paths Regression',
      () {
    group('1. Bundled Root Resolution Precedence', () {
      test('explicitBundledRoot has highest priority', () {
        final env = AuraCliEnvironment.fromPlatform(
          explicitBundledRoot: r'C:\Users\TestUser\AppData\Local\Programs\AURA',
          environment: {
            'AURA_BUNDLED_ROOT': r'C:\EnvOverride\AURA',
            'ProgramFiles': r'C:\Program Files',
          },
          targetOS: AuraOperatingSystem.windows,
        );

        expect(
          env.bundledRoot,
          equals(r'C:\Users\TestUser\AppData\Local\Programs\AURA'),
        );
      });

      test('CLI argument --bundled-root has priority over environment variable',
          () {
        final env = AuraCliEnvironment.fromPlatform(
          cliArgs: [
            r'--bundled-root=C:\Users\TestUser\AppData\Local\Programs\AURA'
          ],
          environment: {
            'AURA_BUNDLED_ROOT': r'C:\EnvOverride\AURA',
            'ProgramFiles': r'C:\Program Files',
          },
          targetOS: AuraOperatingSystem.windows,
        );

        expect(
          env.bundledRoot,
          equals(r'C:\Users\TestUser\AppData\Local\Programs\AURA'),
        );
      });

      test('AURA_BUNDLED_ROOT environment variable has priority over default',
          () {
        final env = AuraCliEnvironment.fromPlatform(
          environment: {
            'AURA_BUNDLED_ROOT': r'C:\CustomBundle\AURA',
            'ProgramFiles': r'C:\Program Files',
          },
          targetOS: AuraOperatingSystem.windows,
        );

        expect(env.bundledRoot, equals(r'C:\CustomBundle\AURA'));
      });

      test('Fallback legacy default used when no override is present', () {
        final env = AuraCliEnvironment.fromPlatform(
          environment: {
            'ProgramFiles': r'C:\Program Files',
          },
          targetOS: AuraOperatingSystem.windows,
        );

        expect(env.bundledRoot, equals(r'C:\Program Files\AURA'));
      });
    });

    group('2. Portable Installation Isolation', () {
      test(
          'Portable deployment keeps bundled read-only binaries separate from mutable app data',
          () {
        const portableRoot = r'D:\Games\PortableAURA';
        const localAppData = r'C:\Users\TestUser\AppData\Local';

        final env = AuraCliEnvironment.fromPlatform(
          explicitBundledRoot: portableRoot,
          environment: {
            'LOCALAPPDATA': localAppData,
          },
          targetOS: AuraOperatingSystem.windows,
        );

        expect(env.bundledRoot, equals(portableRoot));
        expect(env.appManagedRoot, equals('$localAppData\\AURA\\store'));

        final resolver = ProvisioningPathResolver(
          appManagedRoot: env.appManagedRoot,
          bundledRoot: env.bundledRoot,
        );

        // Verifica che le cartelle mutabili risiedano sotto appManagedRoot e non dentro portableRoot
        expect(resolver.modelsDirectory.startsWith(env.appManagedRoot), isTrue);
        expect(
            resolver.runtimesDirectory.startsWith(env.appManagedRoot), isTrue);
        expect(resolver.logsDirectory.startsWith(env.appManagedRoot), isTrue);
        expect(resolver.modelsDirectory.startsWith(portableRoot), isFalse);
      });
    });

    group('3. DefaultApplicationBootstrap Fail-Closed on Missing Roots', () {
      test(
          'Throws ApplicationBootstrapException when appManagedRoot is missing',
          () async {
        final bootstrap = DefaultApplicationBootstrap();
        const topology = ManagedInferenceTopology(
          actor: ManagedRoleRuntimeConfiguration(
            role: InferenceModelRole.actor,
            modelId: 'aura.actor.primary',
            serverConfiguration: ManagedLlamaServerConfiguration(
              executablePath: r'C:\AURA\llama-server.exe',
              workingDirectory: r'C:\AURA',
              modelPath: r'C:\AURA\actor.gguf',
              modelAlias: 'actor',
            ),
          ),
          evaluator: ManagedRoleRuntimeConfiguration(
            role: InferenceModelRole.evaluator,
            modelId: 'aura.evaluator.primary',
            serverConfiguration: ManagedLlamaServerConfiguration(
              executablePath: r'C:\AURA\llama-server.exe',
              workingDirectory: r'C:\AURA',
              modelPath: r'C:\AURA\evaluator.gguf',
              modelAlias: 'evaluator',
            ),
          ),
        );

        const config = ApplicationRuntimeConfiguration(
          runtimeMode: ApplicationRuntimeMode.managedLlamaServer,
          sessionId: 'test-session',
          managedInferenceTopology: topology,
          appManagedRoot: null,
          bundledRoot: r'C:\AURA\bundled',
        );

        expect(
          () => bootstrap.bootstrap(
            const ApplicationBootstrapRequest(
              configuration: config,
              appManagedRoot: null,
              bundledRoot: r'C:\AURA\bundled',
            ),
          ),
          throwsA(isA<ApplicationBootstrapException>().having(
            (e) => e.failure.code,
            'code',
            equals(ApplicationBootstrapFailureCode.incompleteConfiguration),
          )),
        );
      });

      test('Throws ApplicationBootstrapException when bundledRoot is missing',
          () async {
        final bootstrap = DefaultApplicationBootstrap();
        const topology = ManagedInferenceTopology(
          actor: ManagedRoleRuntimeConfiguration(
            role: InferenceModelRole.actor,
            modelId: 'aura.actor.primary',
            serverConfiguration: ManagedLlamaServerConfiguration(
              executablePath: r'C:\AURA\llama-server.exe',
              workingDirectory: r'C:\AURA',
              modelPath: r'C:\AURA\actor.gguf',
              modelAlias: 'actor',
            ),
          ),
          evaluator: ManagedRoleRuntimeConfiguration(
            role: InferenceModelRole.evaluator,
            modelId: 'aura.evaluator.primary',
            serverConfiguration: ManagedLlamaServerConfiguration(
              executablePath: r'C:\AURA\llama-server.exe',
              workingDirectory: r'C:\AURA',
              modelPath: r'C:\AURA\evaluator.gguf',
              modelAlias: 'evaluator',
            ),
          ),
        );

        const config = ApplicationRuntimeConfiguration(
          runtimeMode: ApplicationRuntimeMode.managedLlamaServer,
          sessionId: 'test-session',
          managedInferenceTopology: topology,
          appManagedRoot: r'C:\AURA\store',
          bundledRoot: null,
        );

        expect(
          () => bootstrap.bootstrap(
            const ApplicationBootstrapRequest(
              configuration: config,
              appManagedRoot: r'C:\AURA\store',
              bundledRoot: null,
            ),
          ),
          throwsA(isA<ApplicationBootstrapException>().having(
            (e) => e.failure.code,
            'code',
            equals(ApplicationBootstrapFailureCode.incompleteConfiguration),
          )),
        );
      });
    });

    group('4. Single Services Instance Reuse in Bridge', () {
      test(
          'InferenceBootstrapBridge accepts and reuses injected LocalInferenceServices',
          () async {
        final fileSystem = MemoryProvisioningFileSystem();
        const env = AuraCliEnvironment(
          appManagedRoot: r'C:\CustomTestStore',
          bundledRoot: r'C:\CustomBundled',
        );
        final services = LocalInferenceServiceProvider.create(
          environment: env,
          customFileSystem: fileSystem,
        );

        final bridge = InferenceBootstrapBridge(services: services);
        final resolution = await bridge.resolve();

        // Senza modelli configurati in memoria, deve restituire incompleteModelConfiguration
        // ma utilizzando esattamente i percorsi di services
        expect(resolution, isA<InvalidResolution>());
        expect(
          (resolution as InvalidResolution).reason,
          equals(InferenceBootstrapFailureReason.incompleteModelConfiguration),
        );
      });
    });

    group('5. Zero Hardcoded Developer Paths Scan', () {
      test('No developer-specific workstation paths in lib/ or app/lib/', () {
        final libDir = Directory('lib');
        final appLibDir = Directory('app/lib');

        final disallowedPatterns = [
          r'Users\dendo',
          'Users/dendo',
          r'Documents\GitHub\aura',
          'Documents/GitHub/aura',
        ];

        final filesToScan = <File>[
          ...libDir
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart')),
          ...appLibDir
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart')),
        ];

        final violations = <String>[];

        for (final file in filesToScan) {
          final content = file.readAsStringSync();
          for (final pattern in disallowedPatterns) {
            if (content.contains(pattern)) {
              violations.add('${file.path} contains "$pattern"');
            }
          }
        }

        expect(
          violations,
          isEmpty,
          reason:
              'Found hardcoded developer paths in production code: \n${violations.join('\n')}',
        );
      });
    });
  });
}
