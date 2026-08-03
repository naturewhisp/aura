import 'package:aura_core/aura_offline.dart';
import 'package:test/test.dart';

void main() {
  group('DefaultLlamaRuntimeLaunchEnvironmentResolver', () {
    const resolver = DefaultLlamaRuntimeLaunchEnvironmentResolver();

    test(
        'sanitizza PATH rimuovendo riferimenti legacy a LM Studio ed antepone vendorDirectories',
        () {
      final currentEnv = {
        'PATH':
            r'C:\System32;C:\Users\test\.lmstudio\extensions\backends\vendor\win-llama;C:\Tools',
      };

      final result = resolver.resolve(
        executablePath: r'C:\AURA\runtime\bin\win-x64-cuda\llama-server.exe',
        workingDirectory: r'C:\AURA\runtime\bin\win-x64-cuda',
        vendorDirectories: [r'C:\AURA\runtime\bin\win-x64-cuda\vendor'],
        currentEnvironment: currentEnv,
      );

      expect(
          result.workingDirectory, equals(r'C:\AURA\runtime\bin\win-x64-cuda'));
      final newPath = result.environmentOverrides['PATH']!;
      expect(newPath, contains(r'C:\AURA\runtime\bin\win-x64-cuda\vendor'));
      expect(newPath, contains(r'C:\System32'));
      expect(newPath, contains(r'C:\Tools'));
      expect(newPath, isNot(contains(r'.lmstudio')));
    });

    test('ricava workingDirectory dal percorso dell executable se non fornita',
        () {
      final result = resolver.resolve(
        executablePath: r'C:\AURA\runtime\bin\win-x64-vulkan\llama-server.exe',
        workingDirectory: '',
        currentEnvironment: {'PATH': r'C:\Windows'},
      );

      expect(result.workingDirectory,
          equals(r'C:\AURA\runtime\bin\win-x64-vulkan'));
    });
  });
}
