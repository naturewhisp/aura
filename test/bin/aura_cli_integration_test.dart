import 'dart:convert';

import 'package:aura_core/aura_offline.dart';
import '../provisioning/provisioning_test_helpers.dart';
import 'package:test/test.dart';

void main() {
  group('Tranche 6.4f.8-fix — CLI Entrypoint Integration & Environment Tests',
      () {
    late MemoryProvisioningFileSystem fileSystem;

    setUp(() {
      fileSystem = MemoryProvisioningFileSystem();
    });

    group('AuraCliEnvironment Path Resolution', () {
      test('risolve i percorsi predefiniti da ambiente Platform', () {
        final env = AuraCliEnvironment.fromPlatform(
          environment: {'APPDATA': r'C:\Users\TestUser\AppData\Roaming'},
        );

        expect(env.appManagedRoot, contains('AURA'));
        expect(env.bundledRoot, contains('AURA'));
      });

      test('rispetta l\'override da variabile d\'ambiente AURA_DATA_ROOT', () {
        final env = AuraCliEnvironment.fromPlatform(
          environment: {'AURA_DATA_ROOT': r'D:\CustomDataRoot'},
        );

        expect(env.appManagedRoot, equals(r'D:\CustomDataRoot'));
      });

      test('rispetta l\'override da flag CLI --data-root=<path>', () {
        final env = AuraCliEnvironment.fromPlatform(
          cliArgs: ['model', 'list', r'--data-root=E:\CliDataRoot'],
        );

        expect(env.appManagedRoot, equals(r'E:\CliDataRoot'));
      });
    });

    group('LocalInferenceServiceProvider & Integration', () {
      test(
          'crea il grafo di dipendenze con file system e lock personalizzabili',
          () async {
        final env = const AuraCliEnvironment(
          appManagedRoot: r'C:\TestRoot',
          bundledRoot: r'C:\BundledRoot',
        );
        final lock = InMemoryProvisioningLock();

        final services = LocalInferenceServiceProvider.create(
          environment: env,
          customFileSystem: fileSystem,
          customLock: lock,
        );

        final res = await services.cliRunner
            .runRuntimeCommand(['status'], jsonOutput: true);
        expect(res.exitCode, equals(3));

        final json = jsonDecode(res.outputText) as Map<String, dynamic>;
        expect(json['ok'], isFalse);
        expect(json['code'], equals('runtime_unconfigured'));
      });

      test(
          'esegue la persistenza delle impostazioni sul percorso condiviso dell\'ambiente',
          () async {
        final env = const AuraCliEnvironment(
          appManagedRoot: r'C:\SharedStore',
          bundledRoot: r'C:\BundledStore',
        );

        final services = LocalInferenceServiceProvider.create(
          environment: env,
          customFileSystem: fileSystem,
        );

        const execPath = r'C:\Tools\llama-server.exe';
        fileSystem.writeBytes(execPath, [1, 2, 3]);

        final setRes =
            await services.cliRunner.runRuntimeCommand(['set', execPath]);
        expect(setRes.exitCode, equals(0));

        final statusRes = await services.cliRunner
            .runRuntimeCommand(['status'], jsonOutput: true);
        final json = jsonDecode(statusRes.outputText) as Map<String, dynamic>;
        expect(json['ok'], isTrue);
        expect(json['executablePath'], equals(execPath));
      });
    });
  });
}
