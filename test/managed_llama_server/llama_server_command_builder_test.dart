import 'package:aura_core/aura_offline.dart';
import 'package:test/test.dart';

void main() {
  group('LlamaServerCommandBuilder Tests', () {
    const builder = LlamaServerCommandBuilder();

    test('Builds minimal command arguments correctly', () {
      const config = ManagedLlamaServerConfiguration(
        executablePath: 'llama-server.exe',
        modelPath: 'model.gguf',
        host: '127.0.0.1',
        modelAlias: 'test-model',
        disableReasoning: false,
      );

      final args = builder.build(configuration: config, allocatedPort: 8080);

      expect(
          args,
          equals([
            '--model',
            'model.gguf',
            '--host',
            '127.0.0.1',
            '--port',
            '8080',
            '--alias',
            'test-model',
          ]));
    });

    test('Builds all optional CLI parameters deterministically', () {
      const config = ManagedLlamaServerConfiguration(
        executablePath: 'llama-server.exe',
        modelPath: 'model.gguf',
        host: '127.0.0.1',
        modelAlias: 'test-model',
        contextSize: 4096,
        gpuLayers: 33,
        threads: 8,
        batchSize: 512,
        parallelSlots: 2,
        seed: 42,
        extraArguments: ['--verbose', '--mlock'],
      );

      final args = builder.build(configuration: config, allocatedPort: 8080);

      expect(
          args,
          equals([
            '--model',
            'model.gguf',
            '--host',
            '127.0.0.1',
            '--port',
            '8080',
            '--alias',
            'test-model',
            '--ctx-size',
            '4096',
            '--n-gpu-layers',
            '33',
            '--threads',
            '8',
            '--batch-size',
            '512',
            '--parallel',
            '2',
            '--seed',
            '42',
            '--reasoning',
            'off',
            '--chat-template-kwargs',
            '{"enable_thinking": false}',
            '--verbose',
            '--mlock',
          ]));
    });

    test('Filters out duplicate reserved flags from extraArguments', () {
      const config = ManagedLlamaServerConfiguration(
        executablePath: 'llama-server.exe',
        modelPath: 'model.gguf',
        host: '127.0.0.1',
        modelAlias: 'test-model',
        extraArguments: [
          '--model=other.gguf',
          '--threads',
          '4',
          '--temp',
          '0.7'
        ],
      );

      final args = builder.build(configuration: config, allocatedPort: 8080);

      expect(args, contains('--temp'));
      expect(args.where((a) => a == '--model').length, equals(1));
    });
  });
}
