import '../../../runtime/runtime_failure.dart';

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
  final List<String> extraArguments;
  final String? workingDirectory;
  final Map<String, String> environmentOverrides;
  final String logPolicy;
  final bool retainProcessLogs;
  final String? apiKey;
  final String modelAlias;
  final String? runtimeInstanceId;
  final bool diagnosticMode;

  const ManagedLlamaServerConfiguration({
    required this.executablePath,
    required this.modelPath,
    this.host = '127.0.0.1',
    this.preferredPort,
    this.startupTimeout = const Duration(seconds: 30),
    this.shutdownTimeout = const Duration(seconds: 10),
    this.healthPollInterval = const Duration(milliseconds: 250),
    this.maxStartupAttempts = 1,
    this.contextSize,
    this.gpuLayers,
    this.threads,
    this.batchSize,
    this.parallelSlots,
    this.seed,
    this.extraArguments = const [],
    this.workingDirectory,
    this.environmentOverrides = const {},
    this.logPolicy = 'minimal',
    this.retainProcessLogs = false,
    this.apiKey,
    this.modelAlias = 'managed-llama-model',
    this.runtimeInstanceId,
    this.diagnosticMode = false,
  });

  /// Elenco degli host locali consentiti per il binding del server.
  static const Set<String> allowedHosts = {'127.0.0.1', 'localhost', '::1'};

  /// Elenco delle opzioni CLI riservate che non possono essere duplicate in [extraArguments].
  static const Set<String> reservedFlags = {
    '--model',
    '-m',
    '--host',
    '--port',
    '--alias',
    '-a',
    '--ctx-size',
    '-c',
    '--n-gpu-layers',
    '--gpu-layers',
    '-ngl',
    '--threads',
    '-t',
    '--batch-size',
    '-b',
    '--parallel',
    '-np',
    '--seed',
    '-s',
  };

  /// Valida la configurazione prima del tentativo di avvio del processo.
  ///
  /// Solleva una [RuntimeException] con un codice appropriato in caso di violazione delle invarianti.
  void validate({bool Function(String path)? fileExists}) {
    if (executablePath.trim().isEmpty) {
      throw const RuntimeException(
        RuntimeFailure(
          code: RuntimeFailureCode.invalidArgument,
          message:
              'Il percorso dell\'eseguibile llama-server non può essere vuoto.',
        ),
      );
    }

    if (modelPath.trim().isEmpty) {
      throw const RuntimeException(
        RuntimeFailure(
          code: RuntimeFailureCode.invalidArgument,
          message: 'Il percorso del modello GGUF non può essere vuoto.',
        ),
      );
    }

    if (modelAlias.trim().isEmpty) {
      throw const RuntimeException(
        RuntimeFailure(
          code: RuntimeFailureCode.invalidArgument,
          message: 'L\'alias del modello non può essere vuoto.',
        ),
      );
    }

    if (!allowedHosts.contains(host.toLowerCase())) {
      throw RuntimeException(
        RuntimeFailure(
          code: RuntimeFailureCode.invalidArgument,
          message:
              'Host non consentito: $host. Sono ammessi solo loopback locali (127.0.0.1, localhost, ::1).',
        ),
      );
    }

    if (preferredPort != null &&
        (preferredPort! < 1 || preferredPort! > 65535)) {
      throw RuntimeException(
        RuntimeFailure(
          code: RuntimeFailureCode.invalidArgument,
          message:
              'Porta non valida: $preferredPort. Deve essere compresa tra 1 e 65535.',
        ),
      );
    }

    if (startupTimeout.isNegative || startupTimeout == Duration.zero) {
      throw const RuntimeException(
        RuntimeFailure(
          code: RuntimeFailureCode.invalidArgument,
          message: 'Il timeout di avvio deve essere un intervallo positivo.',
        ),
      );
    }

    if (shutdownTimeout.isNegative || shutdownTimeout == Duration.zero) {
      throw const RuntimeException(
        RuntimeFailure(
          code: RuntimeFailureCode.invalidArgument,
          message: 'Il timeout di shutdown deve essere un intervallo positivo.',
        ),
      );
    }

    if (healthPollInterval.isNegative || healthPollInterval == Duration.zero) {
      throw const RuntimeException(
        RuntimeFailure(
          code: RuntimeFailureCode.invalidArgument,
          message:
              'L\'intervallo di poll dell\'health check deve essere positivo.',
        ),
      );
    }

    if (maxStartupAttempts < 1) {
      throw const RuntimeException(
        RuntimeFailure(
          code: RuntimeFailureCode.invalidArgument,
          message:
              'Il numero massimo di tentativi di avvio deve essere almeno 1.',
        ),
      );
    }

    if (contextSize != null && contextSize! <= 0) {
      throw const RuntimeException(
        RuntimeFailure(
          code: RuntimeFailureCode.invalidArgument,
          message: 'La dimensione del contesto deve essere maggiore di 0.',
        ),
      );
    }

    if (gpuLayers != null && gpuLayers! < 0) {
      throw const RuntimeException(
        RuntimeFailure(
          code: RuntimeFailureCode.invalidArgument,
          message: 'Il numero di layer GPU non può essere negativo.',
        ),
      );
    }

    if (threads != null && threads! <= 0) {
      throw const RuntimeException(
        RuntimeFailure(
          code: RuntimeFailureCode.invalidArgument,
          message: 'Il numero di thread deve essere maggiore di 0.',
        ),
      );
    }

    if (batchSize != null && batchSize! <= 0) {
      throw const RuntimeException(
        RuntimeFailure(
          code: RuntimeFailureCode.invalidArgument,
          message: 'La dimensione del batch deve essere maggiore di 0.',
        ),
      );
    }

    if (parallelSlots != null && parallelSlots! <= 0) {
      throw const RuntimeException(
        RuntimeFailure(
          code: RuntimeFailureCode.invalidArgument,
          message: 'Il numero di slot paralleli deve essere maggiore di 0.',
        ),
      );
    }

    for (final arg in extraArguments) {
      final flag = arg.split('=').first.trim();
      if (reservedFlags.contains(flag)) {
        throw RuntimeException(
          RuntimeFailure(
            code: RuntimeFailureCode.invalidArgument,
            message: 'Flag riservato duplicato in extraArguments: $flag.',
          ),
        );
      }
    }

    if (fileExists != null) {
      if (!fileExists(executablePath)) {
        throw const RuntimeException(
          RuntimeFailure(
            code: RuntimeFailureCode.invalidArgument,
            message:
                'Eseguibile llama-server non trovato al percorso specificato.',
          ),
        );
      }
      if (!fileExists(modelPath)) {
        throw const RuntimeException(
          RuntimeFailure(
            code: RuntimeFailureCode.invalidArgument,
            message:
                'File del modello GGUF non trovato al percorso specificato.',
          ),
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
    List<String>? extraArguments,
    String? workingDirectory,
    Map<String, String>? environmentOverrides,
    String? logPolicy,
    bool? retainProcessLogs,
    String? apiKey,
    String? modelAlias,
    String? runtimeInstanceId,
    bool? diagnosticMode,
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
      extraArguments: extraArguments ?? this.extraArguments,
      workingDirectory: workingDirectory ?? this.workingDirectory,
      environmentOverrides: environmentOverrides ?? this.environmentOverrides,
      logPolicy: logPolicy ?? this.logPolicy,
      retainProcessLogs: retainProcessLogs ?? this.retainProcessLogs,
      apiKey: apiKey ?? this.apiKey,
      modelAlias: modelAlias ?? this.modelAlias,
      runtimeInstanceId: runtimeInstanceId ?? this.runtimeInstanceId,
      diagnosticMode: diagnosticMode ?? this.diagnosticMode,
    );
  }
}
