import 'package:aura_core/aura_offline.dart';
import 'package:test/test.dart';

void main() {
  group('ManagedLlamaServerConfiguration Tests', () {
    test('Valid configuration passes validation', () {
      const config = ManagedLlamaServerConfiguration(
        executablePath: 'C:\\llama\\llama-server.exe',
        modelPath: 'C:\\models\\model.gguf',
        host: '127.0.0.1',
        preferredPort: 8080,
      );

      expect(() => config.validate(), returnsNormally);
    });

    test('Throws on empty executable path', () {
      const config = ManagedLlamaServerConfiguration(
        executablePath: '   ',
        modelPath: 'C:\\models\\model.gguf',
      );

      expect(
        () => config.validate(),
        throwsA(isA<RuntimeException>().having(
          (e) => e.failure.code,
          'code',
          equals(RuntimeFailureCode.invalidArgument),
        )),
      );
    });

    test('Throws on empty model path', () {
      const config = ManagedLlamaServerConfiguration(
        executablePath: 'C:\\llama\\llama-server.exe',
        modelPath: '',
      );

      expect(
        () => config.validate(),
        throwsA(isA<RuntimeException>().having(
          (e) => e.failure.code,
          'code',
          equals(RuntimeFailureCode.invalidArgument),
        )),
      );
    });

    test('Throws on non-local host', () {
      const config = ManagedLlamaServerConfiguration(
        executablePath: 'C:\\llama\\llama-server.exe',
        modelPath: 'C:\\models\\model.gguf',
        host: '192.168.1.100',
      );

      expect(
        () => config.validate(),
        throwsA(isA<RuntimeException>().having(
          (e) => e.failure.code,
          'code',
          equals(RuntimeFailureCode.invalidArgument),
        )),
      );
    });

    test('Throws on invalid port range', () {
      const config = ManagedLlamaServerConfiguration(
        executablePath: 'C:\\llama\\llama-server.exe',
        modelPath: 'C:\\models\\model.gguf',
        preferredPort: 70000,
      );

      expect(
        () => config.validate(),
        throwsA(isA<RuntimeException>().having(
          (e) => e.failure.code,
          'code',
          equals(RuntimeFailureCode.invalidArgument),
        )),
      );
    });

    test('Throws on duplicate reserved CLI flags in extraArguments', () {
      const config = ManagedLlamaServerConfiguration(
        executablePath: 'C:\\llama\\llama-server.exe',
        modelPath: 'C:\\models\\model.gguf',
        extraArguments: ['--model=duplicate.gguf'],
      );

      expect(
        () => config.validate(),
        throwsA(isA<RuntimeException>().having(
          (e) => e.failure.code,
          'code',
          equals(RuntimeFailureCode.invalidArgument),
        )),
      );
    });

    test('Validates file existence when checker function is provided', () {
      const config = ManagedLlamaServerConfiguration(
        executablePath: 'C:\\llama\\llama-server.exe',
        modelPath: 'C:\\models\\model.gguf',
      );

      expect(
        () => config.validate(
            fileExists: (path) => path.contains('llama-server.exe')),
        throwsA(isA<RuntimeException>().having(
          (e) => e.failure.code,
          'code',
          equals(RuntimeFailureCode.invalidArgument),
        )),
      );
    });
  });
}
