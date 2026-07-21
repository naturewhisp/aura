import 'dart:async';
import 'dart:convert';
import 'dart:io' show ProcessSignal;
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
  final LlamaServerCommandBuilder _commandBuilder;

  LlamaServerSupervisorState _state = LlamaServerSupervisorState.idle;
  ManagedProcess? _process;
  int? _allocatedPort;
  int? _lastExitCode;
  String? _failureReason;
  ManagedLlamaServerFailureCode? _failureCode;

  final List<String> _logBuffer = [];
  static const int _maxLogLines = 100;

  StreamSubscription<List<int>>? _stdoutSub;
  StreamSubscription<List<int>>? _stderrSub;
  Completer<void>? _stopCompleter;

  DateTime? _startedAt;
  DateTime? _readyAt;

  LlamaServerProcessSupervisor({
    required ManagedLlamaServerConfiguration configuration,
    required ProcessLauncher processLauncher,
    required PortAllocator portAllocator,
    required HealthProbe healthProbe,
    LlamaServerCommandBuilder commandBuilder =
        const LlamaServerCommandBuilder(),
  })  : _configuration = configuration,
        _processLauncher = processLauncher,
        _portAllocator = portAllocator,
        _healthProbe = healthProbe,
        _commandBuilder = commandBuilder;

  LlamaServerSupervisorState get state => _state;
  int? get allocatedPort => _allocatedPort;
  int? get pid => _process?.pid;
  int? get lastExitCode => _lastExitCode;
  String? get failureReason => _failureReason;
  ManagedLlamaServerFailureCode? get failureCode => _failureCode;
  List<String> get logTail => List.unmodifiable(_logBuffer);

  /// Avvia il processo `llama-server`, alloca la porta e ne attende la prontezza HTTP.
  Future<int> start() async {
    if (_state == LlamaServerSupervisorState.disposed) {
      throw StateError('Supervisor già dismesso.');
    }
    if (_state != LlamaServerSupervisorState.idle &&
        _state != LlamaServerSupervisorState.stopped) {
      throw StateError('Impossibile avviare supervisor nello stato $_state.');
    }

    _state = LlamaServerSupervisorState.starting;
    _failureReason = null;
    _failureCode = null;
    _lastExitCode = null;
    _startedAt = DateTime.now();
    _logBuffer.clear();

    try {
      // 1. Validazione configurazione
      _configuration.validate();

      // 2. Allocazione porta loopback
      _allocatedPort = await _portAllocator.allocatePort(
        preferredPort: _configuration.preferredPort,
        host: _configuration.host,
      );

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

      _process = await _processLauncher.start(launchRequest);

      // 5. Sottoscrizione bounded agli stream di output
      _stdoutSub = _process!.stdoutBytes.listen(
        (bytes) => _appendLogLines('STDOUT', bytes),
      );
      _stderrSub = _process!.stderrBytes.listen(
        (bytes) => _appendLogLines('STDERR', bytes),
      );

      // 6. Monitoraggio dell'uscita prematura del processo
      unawaited(_process!.exitCode.then((code) {
        _lastExitCode = code;
        if (_state == LlamaServerSupervisorState.starting ||
            _state == LlamaServerSupervisorState.probing) {
          _state = LlamaServerSupervisorState.failed;
          _failureCode = ManagedLlamaServerFailureCode.processExitedEarly;
          _failureReason =
              'Il processo llama-server è terminato prematuramente con exit code $code.';
        }
      }));

      // 7. Polling di readiness HTTP entro il timeout di avvio
      _state = LlamaServerSupervisorState.probing;
      final baseUri =
          Uri.parse('http://${_configuration.host}:$_allocatedPort');

      final pollStartTime = DateTime.now();
      while (DateTime.now().difference(pollStartTime) <
          _configuration.startupTimeout) {
        if (_state == LlamaServerSupervisorState.failed) {
          throw Exception(
              _failureReason ?? 'Processo terminato durante l\'avvio.');
        }

        final probeResult = await _healthProbe.probe(
          baseUri: baseUri,
          expectedModelAlias: _configuration.modelAlias,
          timeout: const Duration(seconds: 1),
        );

        if (probeResult.responsive && probeResult.modelVisible) {
          _state = LlamaServerSupervisorState.ready;
          _readyAt = DateTime.now();
          return _allocatedPort!;
        }

        await Future.delayed(_configuration.healthPollInterval);
      }

      // If we timed out before ready:
      _state = LlamaServerSupervisorState.failed;
      _failureCode = ManagedLlamaServerFailureCode.startupTimeout;
      _failureReason =
          'Timeout di avvio superato (${_configuration.startupTimeout.inSeconds}s) prima della prontezza HTTP.';
      await _terminateProcess(force: true);
      throw Exception(_failureReason);
    } catch (e) {
      _state = LlamaServerSupervisorState.failed;
      await _terminateProcess(force: true);
      rethrow;
    }
  }

  void _appendLogLines(String source, List<int> bytes) {
    try {
      final text = utf8.decode(bytes, allowMalformed: true);
      final lines = text.split('\n');
      for (final line in lines) {
        final trimmed = line.trimRight();
        if (trimmed.isNotEmpty) {
          _logBuffer.add('[$source] $trimmed');
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

  /// Ferma ordinatamente il processo in modo deterministico e single-flight.
  Future<void> stop() async {
    if (_state == LlamaServerSupervisorState.stopped ||
        _state == LlamaServerSupervisorState.disposed) {
      return;
    }

    if (_stopCompleter != null) {
      return _stopCompleter!.future;
    }

    _stopCompleter = Completer<void>();
    _state = LlamaServerSupervisorState.stopping;

    try {
      await _terminateProcess(force: false);
      _state = LlamaServerSupervisorState.stopped;
      _stopCompleter!.complete();
    } catch (e) {
      _state = LlamaServerSupervisorState.failed;
      _stopCompleter!.completeError(e);
      rethrow;
    }
  }

  Future<void> _terminateProcess({required bool force}) async {
    if (_process == null) return;

    try {
      if (force) {
        _process!.kill(ProcessSignal.sigkill);
      } else {
        _process!.kill(ProcessSignal.sigterm);
      }

      try {
        await _process!.exitCode.timeout(_configuration.shutdownTimeout);
      } on TimeoutException {
        // Se sigterm va in timeout, applica il force kill
        _process!.kill(ProcessSignal.sigkill);
        await _process!.exitCode
            .timeout(const Duration(seconds: 5), onTimeout: () => -1);
      }
    } catch (_) {
    } finally {
      await _stdoutSub?.cancel();
      await _stderrSub?.cancel();
      _stdoutSub = null;
      _stderrSub = null;
      _process = null;
    }
  }

  /// Dismette permanentemente il supervisor e le sue risorse.
  Future<void> dispose() async {
    if (_state == LlamaServerSupervisorState.disposed) return;
    await stop();
    _state = LlamaServerSupervisorState.disposed;
  }

  /// DTO diagnostico sanitizzato per l'ispezione pubblica.
  Map<String, dynamic> getDiagnostics() {
    return {
      'supervisorState': _state.name,
      'pid': pid,
      'allocatedPort': _allocatedPort,
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
