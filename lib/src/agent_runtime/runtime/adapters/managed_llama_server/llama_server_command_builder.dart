import 'managed_llama_server_configuration.dart';

/// Builder puro e testabile per la generazione della lista di argomenti CLI di `llama-server`.
class LlamaServerCommandBuilder {
  const LlamaServerCommandBuilder();

  /// Costruisce l'elenco deterministico di argomenti da passare all'eseguibile `llama-server`.
  List<String> build({
    required ManagedLlamaServerConfiguration configuration,
    required int allocatedPort,
  }) {
    final args = <String>[
      '--model',
      configuration.modelPath,
      '--host',
      configuration.host,
      '--port',
      allocatedPort.toString(),
      '--alias',
      configuration.modelAlias,
    ];

    if (configuration.contextSize != null) {
      args.addAll(['--ctx-size', configuration.contextSize.toString()]);
    }

    if (configuration.gpuLayers != null) {
      args.addAll(['--n-gpu-layers', configuration.gpuLayers.toString()]);
    }

    if (configuration.threads != null) {
      args.addAll(['--threads', configuration.threads.toString()]);
    }

    if (configuration.batchSize != null) {
      args.addAll(['--batch-size', configuration.batchSize.toString()]);
    }

    if (configuration.parallelSlots != null) {
      args.addAll(['--parallel', configuration.parallelSlots.toString()]);
    }

    if (configuration.seed != null) {
      args.addAll(['--seed', configuration.seed.toString()]);
    }

    if (configuration.disableReasoning) {
      args.addAll([
        '--reasoning',
        'off',
        '--chat-template-kwargs',
        '{"enable_thinking": false}',
      ]);
    }

    for (final extra in configuration.extraArguments) {
      final flag = extra.split('=').first.trim();
      if (!ManagedLlamaServerConfiguration.reservedFlags.contains(flag)) {
        args.add(extra);
      }
    }

    return List.unmodifiable(args);
  }
}
