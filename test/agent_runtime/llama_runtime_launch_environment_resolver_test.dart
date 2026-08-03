import 'package:aura_core/aura_offline.dart';
import 'package:test/test.dart';

void main() {
  group('DefaultLlamaRuntimeLaunchEnvironmentResolver', () {
    const resolver = DefaultLlamaRuntimeLaunchEnvironmentResolver();

    test(
        'preserva l ambiente base di sistema (SystemRoot, TEMP, etc) e fonde gli overrides',
        () {
      final baseEnv = {
        'SystemRoot': r'C:\Windows',
        'TEMP': r'C:\Temp',
        'PATH':
            r'C:\Windows\System32;C:\Users\test\.lmstudio\extensions\backends\vendor\win-llama;C:\Tools',
      };

      final overrides = {
        'CUDA_VISIBLE_DEVICES': '0',
        'LLAMA_LOG_LEVEL': '2',
      };

      final result = resolver.resolve(
        executablePath: r'C:\AURA\runtime\bin\win-x64-cuda\llama-server.exe',
        workingDirectory: r'C:\AURA\runtime\bin\win-x64-cuda',
        vendorDirectories: [r'C:\AURA\runtime\bin\win-x64-cuda\vendor'],
        baseEnvironment: baseEnv,
        environmentOverrides: overrides,
      );

      expect(
          result.workingDirectory, equals(r'C:\AURA\runtime\bin\win-x64-cuda'));
      final env = result.environmentOverrides;

      // Preservazione ambiente base
      expect(env['SystemRoot'], equals(r'C:\Windows'));
      expect(env['TEMP'], equals(r'C:\Temp'));
      expect(env['CUDA_VISIBLE_DEVICES'], equals('0'));
      expect(env['LLAMA_LOG_LEVEL'], equals('2'));

      // PATH sanitizzato
      final newPath = env['PATH']!;
      expect(newPath, contains(r'C:\AURA\runtime\bin\win-x64-cuda\vendor'));
      expect(newPath, contains(r'C:\Windows\System32'));
      expect(newPath, contains(r'C:\Tools'));
      expect(newPath, isNot(contains(r'.lmstudio')));
    });

    test(
        'RuntimeLaunchEnvironment operator == e hashCode supportano MapEquality su environmentOverrides',
        () {
      const env1 = RuntimeLaunchEnvironment(
        workingDirectory: r'C:\AURA',
        environmentOverrides: {'A': '1', 'B': '2'},
      );

      const env2 = RuntimeLaunchEnvironment(
        workingDirectory: r'C:\AURA',
        environmentOverrides: {'A': '1', 'B': '2'},
      );

      const env3 = RuntimeLaunchEnvironment(
        workingDirectory: r'C:\AURA',
        environmentOverrides: {'A': '1', 'B': '3'},
      );

      expect(env1, equals(env2));
      expect(env1.hashCode, equals(env2.hashCode));
      expect(env1, isNot(equals(env3)));
    });
  });
}
