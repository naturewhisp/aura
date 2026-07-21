import 'dart:async';
import 'dart:convert';
import 'dart:io' show ProcessSignal;
import 'dart_io_process_launcher.dart';
import 'llama_server_command_builder.dart';
import 'llama_server_health_probe.dart';
import 'managed_llama_server_configuration.dart';
import 'managed_llama_server_failure.dart';
import 'port_allocator.dart';
import 'process_launcher.dart';

/// Stati possibili della State Machine del supervisor di `llama-server`.
enum LlamaServerSupervisorState {
  idle,
  starting,
  probing,
  ready,
  stopping,
  stopped,
  failed,
  disposed,
}

/// Gestore responsabile dell'orchestrazione del ciclo di vita del processo `llama-server`.
class LlamaServerProcessSupervisor {
  final ManagedLlamaServerConfiguration _configuration;
  final ProcessLauncher _processLauncher;
  final PortAllocator _portAllocator;
  final HealthProbe _healthProbe;
  final ManagedFileSystem _fileSystem;
  final LlamaServerCommandBuilder _commandBuilder;

  LlamaServerSupervisorState _state = LlamaServerSupervisorState.idle;
  ManagedProcess? _process;
  int? _allocatedPort;
  int? _lastExitCode;
  String? _failureReason;
  ManagedLlamaServerFailureCode? _failureCode;

  final List<String> _logBuffer = [];
  static const int _maxLogLines = 100;
  static const int _maxLineLength = 512;

  StreamSubscription<List<int>>? _stdoutSub;
  StreamSubscription<List<int>>? _stderrSub;
  Future<void>? _stopFuture;

  DateTime? _startedAt;
  DateTime? _readyAt;

  LlamaServerProcessSupervisor({
    required ManagedLlamaServerConfiguration configuration,
    required ProcessLauncher processLauncher,
    required PortAllocator portAllocator,
    required HealthProbe healthProbe,
    ManagedFileSystem fileSystem = const LocalFileSystem(),
    LlamaServerCommandBuilder commandBuilder =
        const LlamaServerCommandBuilder(),
  })  : _configuration = configuration,
        _processLauncher = processLauncher,
        _portAllocator = portAllocator,
        _healthProbe = healthProbe,
        _fileSystem = fileSystem,
        _commandBuilder = commandBuilder;

  LlamaServerSupervisorState get state => _state;
  int? get allocatedPort => _allocatedPort;
  int? get pid => _process?.pid;
  int? get lastExitCode => _lastExitCode;
  String? get failureReason => _failureReason;
  ManagedLlamaServerFailureCode? get failureCode => _failureCode;
  List<String> get logTail => List.unmodifiable(_logBuffer);

  /// Avvia il processo `llama-server` eseguendo i tentativi consentiti da `maxStartupAttempts`.
  Future<int> start() async {
    if (_state == LlamaServerSupervisorState.disposed) {
      throw const ManagedLlamaServerException(
        code: ManagedLlamaServerFailureCode.unexpectedProcessState,
        message: 'Impossibile avviare il supervisor nello stato disposed.',
      );
    }
    if (_state != LlamaServerSupervisorState.idle &&
        _state != LlamaServerSupervisorState.stopped) {
      throw ManagedLlamaServerException(
        code: ManagedLlamaServerFailureCode.unexpectedProcessState,
        message: 'Impossibile avviare il supervisor nello stato $_state.',
      );
    }

    _stopFuture = null;
    _failureReason = null;
    _failureCode = null;
    _lastExitCode = null;
    _startedAt = DateTime.now();

    final maxAttempts = _configuration.maxStartupAttempts;
    ManagedLlamaServerException? lastException;

    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      _state = LlamaServerSupervisorState.starting;
      _logBuffer.clear();

      try {
        // 1. Validazione configurazione obbligatoria ad ogni tentativo
        _configuration.validate(_fileSystem);

        // 2. Allocazione porta loopback
        try {
          _allocatedPort = await _portAllocator.allocatePort(
            preferredPort: _configuration.preferredPort,
            host: _configuration.host,
          );
        } catch (e) {
          throw ManagedLlamaServerException(
            code: ManagedLlamaServerFailureCode.invalidPort,
            message: 'Allocazione della porta loopback fallita.',
            cause: e,
          );
        }

        // 3. Costruzione argomenti CLI
        final args = _commandBuilder.build(
          configuration: _configuration,
          allocatedPort: _allocatedPort!,
        );

        // 4. Lancio del processo
        final launchRequest = ProcessLaunchRequest(
          executable: _configuration.executablePath,
          arguments: args,
          workingDirectory: _configuration.workingDirectory,
          environment: _configuration.environmentOverrides.isNotEmpty
              ? _configuration.environmentOverrides
              : null,
        );

        try {
          _process = await _processLauncher.start(launchRequest);
        } catch (e) {
          throw ManagedLlamaServerException(
            code: ManagedLlamaServerFailureCode.processLaunchFailed,
            message: 'Impossibile avviare il processo llama-server.',
            cause: e,
          );
        }

        // 5. Sottoscrizione stream
        _stdoutSub = _process!.stdoutBytes.listen(
          (bytes) => _appendLogLines('STDOUT', bytes),
        );
        _stderrSub = _process!.stderrBytes.listen(
          (bytes) => _appendLogLines('STDERR', bytes),
        );

        // 6. Monitoraggio dell'uscita prematura o inattesa del processo
        final currentProcess = _process!;
        unawaited(currentProcess.exitCode.then((code) {
          if (currentProcess != _process) return;
          _lastExitCode = code;
          if (_state == LlamaServerSupervisorState.starting ||
              _state == LlamaServerSupervisorState.probing) {
            _state = LlamaServerSupervisorState.failed;
            _failureCode = ManagedLlamaServerFailureCode.processExitedEarly;
            _failureReason =
                'Il processo llama-server è terminato prematuramente con exit code $code.';
          } else if (_state == LlamaServerSupervisorState.ready) {
            _state = LlamaServerSupervisorState.failed;
            _failureCode = ManagedLlamaServerFailureCode.processExitedEarly;
            _failureReason =
                'Il processo llama-server si è arrestato inaspettatamente dopo l\'avvio con exit code $code.';
          }
        }));

        // 7. Polling di readiness HTTP entro il timeout di avvio
        _state = LlamaServerSupervisorState.probing;
        final baseUri =
            Uri.parse('http://${_configuration.host}:$_allocatedPort');

        final pollStartTime = DateTime.now();
        bool ready = false;
        while (DateTime.now().difference(pollStartTime) <
            _configuration.startupTimeout) {
          if (_state == LlamaServerSupervisorState.failed) {
            throw ManagedLlamaServerException(
              code: _failureCode ??
                  ManagedLlamaServerFailureCode.processExitedEarly,
              message:
                  _failureReason ?? 'Il processo è terminato durante l\'avvio.',
            );
          }

          final probeResult = await _healthProbe.probe(
            baseUri: baseUri,
            expectedModelAlias: _configuration.modelAlias,
            timeout: const Duration(seconds: 1),
          );

          if (probeResult.responsive && probeResult.modelVisible) {
            ready = true;
            break;
          }

          await Future.delayed(_configuration.healthPollInterval);
        }

        if (ready) {
          _state = LlamaServerSupervisorState.ready;
          _readyAt = DateTime.now();
          return _allocatedPort!;
        }

        // Se timed out:
        _state = LlamaServerSupervisorState.failed;
        _failureCode = ManagedLlamaServerFailureCode.startupTimeout;
        _failureReason =
            'Timeout di avvio superato (${_configuration.startupTimeout.inSeconds}s) prima della prontezza HTTP.';
        await _terminateProcess(force: true);
        throw ManagedLlamaServerException(
          code: ManagedLlamaServerFailureCode.startupTimeout,
          message: _failureReason!,
        );
      } on ManagedLlamaServerException catch (e) {
        lastException = e;
        if (attempt < maxAttempts) {
          try {
            await _terminateProcess(force: true);
          } catch (_) {}
          await Future.delayed(const Duration(milliseconds: 500));
        }
      } catch (e) {
        lastException = ManagedLlamaServerException(
          code: ManagedLlamaServerFailureCode.unexpectedProcessState,
          message: 'Errore inatteso durante l\'avvio.',
          cause: e,
        );
        if (attempt < maxAttempts) {
          try {
            await _terminateProcess(force: true);
          } catch (_) {}
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }
    }

    _state = LlamaServerSupervisorState.failed;
    _failureCode = lastException?.code ??
        ManagedLlamaServerFailureCode.unexpectedProcessState;
    _failureReason = lastException?.message ?? 'Tentativi di avvio falliti.';
    throw lastException!;
  }

  void _appendLogLines(String source, List<int> bytes) {
    try {
      final text = utf8.decode(bytes, allowMalformed: true);
      final lines = text.split('\n');
      for (final line in lines) {
        var trimmed = line.trimRight();
        if (trimmed.isNotEmpty) {
          if (trimmed.length > _maxLineLength) {
            trimmed = '${trimmed.substring(0, _maxLineLength)}... [TRUNCATED]';
          }
          final sanitized =
              trimmed.replaceAll(RegExp(r'\x1B\[[0-9;]*[a-zA-Z]'), '');
          _logBuffer.add('[$source] $sanitized');
          if (_logBuffer.length > _maxLogLines) {
            _logBuffer.removeAt(0);
          }
        }
      }
    } catch (_) {}
  }

  /// Esegue il controllo di integrità asincrono sull'istanza attiva.
  Future<HealthProbeResult> checkHealth() async {
    if (_state != LlamaServerSupervisorState.ready || _allocatedPort == null) {
      return HealthProbeResult(
        responsive: false,
        observedAt: DateTime.now(),
        failureReason:
            'Supervisor non in stato ready (stato attuale: $_state).',
      );
    }

    final baseUri = Uri.parse('http://${_configuration.host}:$_allocatedPort');
    return await _healthProbe.probe(
      baseUri: baseUri,
      expectedModelAlias: _configuration.modelAlias,
    );
  }

  /// Ferma ordinatamente il processo in modo deterministico e re-entrante.
  Future<void> stop() {
    if (_state == LlamaServerSupervisorState.stopped ||
        _state == LlamaServerSupervisorState.disposed) {
      return Future.value();
    }

    return _stopFuture ??= _performStop().whenComplete(() {
      _stopFuture = null;
    });
  }

  Future<void> _performStop() async {
    _state = LlamaServerSupervisorState.stopping;
    try {
      await _terminateProcess(force: false);
      _state = LlamaServerSupervisorState.stopped;
    } catch (e) {
      _state = LlamaServerSupervisorState.failed;
      if (e is ManagedLlamaServerException) {
        _failureCode = e.code;
        _failureReason = e.message;
      } else {
        _failureCode = ManagedLlamaServerFailureCode.unexpectedProcessState;
        _failureReason = 'Errore inatteso durante l\'arresto del processo.';
      }
      rethrow;
    }
  }

  Future<void> _terminateProcess({required bool force}) async {
    if (_process == null) return;

    try {
      if (force) {
        final killed = _process!.kill(ProcessSignal.sigkill);
        if (!killed) {
          throw const ManagedLlamaServerException(
            code: ManagedLlamaServerFailureCode.forcedTerminationFailed,
            message: 'Invio di SIGKILL fallito durante arresto forzato.',
          );
        }
        final exitCode = await _process!.exitCode.timeout(
          const Duration(seconds: 5),
          onTimeout: () => throw const ManagedLlamaServerException(
            code: ManagedLlamaServerFailureCode.forcedTerminationFailed,
            message: 'Il processo non ha risposto a SIGKILL entro 5 secondi.',
          ),
        );
        _lastExitCode = exitCode;
      } else {
        final killed = _process!.kill(ProcessSignal.sigterm);
        if (!killed) {
          await _terminateProcess(force: true);
          return;
        }

        try {
          final exitCode =
              await _process!.exitCode.timeout(_configuration.shutdownTimeout);
          _lastExitCode = exitCode;
        } on TimeoutException {
          await _terminateProcess(force: true);
        }
      }
    } finally {
      if (_lastExitCode != null) {
        await _stdoutSub?.cancel();
        await _stderrSub?.cancel();
        _stdoutSub = null;
        _stderrSub = null;
        _process = null;
      }
    }
  }

  /// Dismette permanentemente il supervisor e le sue risorse.
  Future<void> dispose() async {
    if (_state == LlamaServerSupervisorState.disposed) return;
    Object? firstError;
    try {
      await stop();
    } catch (e) {
      firstError ??= e;
    }
    try {
      await _healthProbe.dispose();
    } catch (e) {
      firstError ??= e;
    }
    if (firstError != null) {
      _state = LlamaServerSupervisorState.failed;
      throw firstError;
    }
    _state = LlamaServerSupervisorState.disposed;
  }

  /// DTO diagnostico sanitizzato per l'ispezione pubblica.
  Map<String, dynamic> getDiagnostics() {
    return {
      'supervisorState': _state.name,
      'host': _configuration.host,
      'modelAlias': _configuration.modelAlias,
      'lastExitCode': _lastExitCode,
      'startedAt': _startedAt?.toIso8601String(),
      'readyAt': _readyAt?.toIso8601String(),
      if (_failureReason != null) 'failureReason': _failureReason,
      if (_failureCode != null) 'failureCode': _failureCode!.name,
      if (_configuration.diagnosticMode && _logBuffer.isNotEmpty)
        'logTail': List<String>.unmodifiable(_logBuffer),
    };
  }
}
