import 'managed_llama_server_failure.dart';
import 'process_launcher.dart';

/// Configurazione immutabile e tipizzata per il runtime locale gestito `llama-server`.
class ManagedLlamaServerConfiguration {
  final String executablePath;
  final String modelPath;
  final String host;
  final int? preferredPort;
  final Duration startupTimeout;
  final Duration shutdownTimeout;
  final Duration healthPollInterval;
  final int maxStartupAttempts;
  final int? contextSize;
  final int? gpuLayers;
  final int? threads;
  final int? batchSize;
  final int? parallelSlots;
  final int? seed;
  final String modelAlias;
  final String apiKey;
  final List<String> extraArguments;
  final Map<String, String> environmentOverrides;
  final String? workingDirectory;
  final bool diagnosticMode;
  final String? runtimeInstanceId;

  static const List<String> allowedHosts = ['127.0.0.1', 'localhost', '::1'];

  static const Set<String> reservedFlags = {
    '--model',
    '-m',
    '--port',
    '-p',
    '--host',
    '--ctx-size',
    '-c',
    '--n-gpu-layers',
    '-ngl',
    '--threads',
    '-t',
    '--batch-size',
    '-b',
    '--parallel',
    '-np',
    '--api-key',
    '--seed',
  };

  const ManagedLlamaServerConfiguration({
    required this.executablePath,
    required this.modelPath,
    this.host = '127.0.0.1',
    this.preferredPort,
    this.startupTimeout = const Duration(seconds: 30),
    this.shutdownTimeout = const Duration(seconds: 5),
    this.healthPollInterval = const Duration(milliseconds: 250),
    this.maxStartupAttempts = 3,
    this.contextSize,
    this.gpuLayers,
    this.threads,
    this.batchSize,
    this.parallelSlots,
    this.seed,
    this.modelAlias = 'default-model',
    this.apiKey = 'managed-llama-secret',
    this.extraArguments = const [],
    this.environmentOverrides = const {},
    this.workingDirectory,
    this.diagnosticMode = false,
    this.runtimeInstanceId,
  });

  /// Esegue la validazione formale e dei vincoli dei parametri di configurazione.
  void validate([ManagedFileSystem? fileSystem]) {
    if (executablePath.trim().isEmpty) {
      throw const ManagedLlamaServerException(
        code: ManagedLlamaServerFailureCode.invalidConfiguration,
        message:
            'Il percorso dell\'eseguibile llama-server non può essere vuoto.',
      );
    }

    if (modelPath.trim().isEmpty) {
      throw const ManagedLlamaServerException(
        code: ManagedLlamaServerFailureCode.invalidConfiguration,
        message: 'Il percorso del modello GGUF non può essere vuoto.',
      );
    }

    if (modelAlias.trim().isEmpty) {
      throw const ManagedLlamaServerException(
        code: ManagedLlamaServerFailureCode.invalidConfiguration,
        message: 'L\'alias del modello non può essere vuoto.',
      );
    }

    if (!allowedHosts.contains(host.toLowerCase())) {
      throw ManagedLlamaServerException(
        code: ManagedLlamaServerFailureCode.unsupportedHost,
        message:
            'Host non consentito: $host. Sono ammessi solo loopback locali (127.0.0.1, localhost, ::1).',
      );
    }

    if (preferredPort != null &&
        (preferredPort! < 1 || preferredPort! > 65535)) {
      throw ManagedLlamaServerException(
        code: ManagedLlamaServerFailureCode.invalidPort,
        message:
            'Porta non valida: $preferredPort. Deve essere compresa tra 1 e 65535.',
      );
    }

    if (startupTimeout.isNegative || startupTimeout == Duration.zero) {
      throw const ManagedLlamaServerException(
        code: ManagedLlamaServerFailureCode.invalidConfiguration,
        message: 'Il timeout di avvio deve essere un intervallo positivo.',
      );
    }

    if (shutdownTimeout.isNegative || shutdownTimeout == Duration.zero) {
      throw const ManagedLlamaServerException(
        code: ManagedLlamaServerFailureCode.invalidConfiguration,
        message: 'Il timeout di shutdown deve essere un intervallo positivo.',
      );
    }

    if (healthPollInterval.isNegative || healthPollInterval == Duration.zero) {
      throw const ManagedLlamaServerException(
        code: ManagedLlamaServerFailureCode.invalidConfiguration,
        message:
            'L\'intervallo di poll dell\'health check deve essere positivo.',
      );
    }

    if (maxStartupAttempts < 1) {
      throw const ManagedLlamaServerException(
        code: ManagedLlamaServerFailureCode.invalidConfiguration,
        message:
            'Il numero massimo di tentativi di avvio deve essere almeno 1.',
      );
    }

    if (contextSize != null && contextSize! <= 0) {
      throw const ManagedLlamaServerException(
        code: ManagedLlamaServerFailureCode.invalidConfiguration,
        message: 'La dimensione del contesto deve essere maggiore di 0.',
      );
    }

    if (gpuLayers != null && gpuLayers! < 0) {
      throw const ManagedLlamaServerException(
        code: ManagedLlamaServerFailureCode.invalidConfiguration,
        message: 'Il numero di layer GPU non può essere negativo.',
      );
    }

    if (threads != null && threads! <= 0) {
      throw const ManagedLlamaServerException(
        code: ManagedLlamaServerFailureCode.invalidConfiguration,
        message: 'Il numero di thread deve essere maggiore di 0.',
      );
    }

    if (batchSize != null && batchSize! <= 0) {
      throw const ManagedLlamaServerException(
        code: ManagedLlamaServerFailureCode.invalidConfiguration,
        message: 'La dimensione del batch deve essere maggiore di 0.',
      );
    }

    if (parallelSlots != null && parallelSlots! <= 0) {
      throw const ManagedLlamaServerException(
        code: ManagedLlamaServerFailureCode.invalidConfiguration,
        message: 'Il numero di slot paralleli deve essere maggiore di 0.',
      );
    }

    if (seed != null && seed! < 0) {
      throw const ManagedLlamaServerException(
        code: ManagedLlamaServerFailureCode.invalidConfiguration,
        message: 'Il seed del modello non può essere negativo.',
      );
    }

    for (final arg in extraArguments) {
      final flag = arg.split('=').first.trim();
      if (reservedFlags.contains(flag)) {
        throw ManagedLlamaServerException(
          code: ManagedLlamaServerFailureCode.invalidConfiguration,
          message: 'Flag riservato duplicato in extraArguments: $flag.',
        );
      }
    }

    if (fileSystem != null) {
      if (!fileSystem.fileExists(executablePath)) {
        throw const ManagedLlamaServerException(
          code: ManagedLlamaServerFailureCode.executableMissing,
          message:
              'Eseguibile llama-server non trovato al percorso specificato.',
        );
      }
      if (!fileSystem.fileExists(modelPath)) {
        throw const ManagedLlamaServerException(
          code: ManagedLlamaServerFailureCode.modelMissing,
          message: 'File del modello GGUF non trovato al percorso specificato.',
        );
      }
      if (workingDirectory != null &&
          !fileSystem.directoryExists(workingDirectory!)) {
        throw const ManagedLlamaServerException(
          code: ManagedLlamaServerFailureCode.invalidConfiguration,
          message: 'Directory di lavoro specificata non trovata.',
        );
      }
    }
  }

  ManagedLlamaServerConfiguration copyWith({
    String? executablePath,
    String? modelPath,
    String? host,
    int? preferredPort,
    Duration? startupTimeout,
    Duration? shutdownTimeout,
    Duration? healthPollInterval,
    int? maxStartupAttempts,
    int? contextSize,
    int? gpuLayers,
    int? threads,
    int? batchSize,
    int? parallelSlots,
    int? seed,
    String? modelAlias,
    String? apiKey,
    List<String>? extraArguments,
    Map<String, String>? environmentOverrides,
    String? workingDirectory,
    bool? diagnosticMode,
    String? runtimeInstanceId,
  }) {
    return ManagedLlamaServerConfiguration(
      executablePath: executablePath ?? this.executablePath,
      modelPath: modelPath ?? this.modelPath,
      host: host ?? this.host,
      preferredPort: preferredPort ?? this.preferredPort,
      startupTimeout: startupTimeout ?? this.startupTimeout,
      shutdownTimeout: shutdownTimeout ?? this.shutdownTimeout,
      healthPollInterval: healthPollInterval ?? this.healthPollInterval,
      maxStartupAttempts: maxStartupAttempts ?? this.maxStartupAttempts,
      contextSize: contextSize ?? this.contextSize,
      gpuLayers: gpuLayers ?? this.gpuLayers,
      threads: threads ?? this.threads,
      batchSize: batchSize ?? this.batchSize,
      parallelSlots: parallelSlots ?? this.parallelSlots,
      seed: seed ?? this.seed,
      modelAlias: modelAlias ?? this.modelAlias,
      apiKey: apiKey ?? this.apiKey,
      extraArguments: extraArguments ?? this.extraArguments,
      environmentOverrides: environmentOverrides ?? this.environmentOverrides,
      workingDirectory: workingDirectory ?? this.workingDirectory,
      diagnosticMode: diagnosticMode ?? this.diagnosticMode,
      runtimeInstanceId: runtimeInstanceId ?? this.runtimeInstanceId,
    );
  }
}
