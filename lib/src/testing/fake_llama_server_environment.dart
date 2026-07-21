import 'dart:async';
import 'dart:convert';
import 'dart:io' show ProcessSignal;
import '../agent_runtime/runtime/adapters/managed_llama_server/llama_server_health_probe.dart';
import '../agent_runtime/runtime/adapters/managed_llama_server/port_allocator.dart';
import '../agent_runtime/runtime/adapters/managed_llama_server/process_launcher.dart';

/// ManagedProcess fake per l'esecuzione di test offline senza I/O reale.
class FakeManagedProcess implements ManagedProcess {
  @override
  final int pid;
  final StreamController<List<int>> _stdoutController =
      StreamController<List<int>>.broadcast();
  final StreamController<List<int>> _stderrController =
      StreamController<List<int>>.broadcast();
  final Completer<int> _exitCodeCompleter = Completer<int>();

  bool isKilled = false;
  ProcessSignal? lastSignal;
  bool killResult = true;

  bool get isExited => _exitCodeCompleter.isCompleted;

  FakeManagedProcess({this.pid = 4242});

  @override
  Stream<List<int>> get stdoutBytes => _stdoutController.stream;

  @override
  Stream<List<int>> get stderrBytes => _stderrController.stream;

  @override
  Future<int> get exitCode => _exitCodeCompleter.future;

  void emitStdout(String text) {
    if (!_stdoutController.isClosed) {
      _stdoutController.add(utf8.encode(text));
    }
  }

  void emitStderr(String text) {
    if (!_stderrController.isClosed) {
      _stderrController.add(utf8.encode(text));
    }
  }

  void completeExit(int code) {
    if (!_exitCodeCompleter.isCompleted) {
      _exitCodeCompleter.complete(code);
      _stdoutController.close();
      _stderrController.close();
    }
  }

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    isKilled = true;
    lastSignal = signal;
    if (!killResult) return false;
    if (!_exitCodeCompleter.isCompleted) {
      _exitCodeCompleter.complete(signal == ProcessSignal.sigkill ? -9 : 0);
      _stdoutController.close();
      _stderrController.close();
    }
    return true;
  }
}

/// ProcessLauncher fake che restituisce istanze di [FakeManagedProcess].
class FakeProcessLauncher implements ProcessLauncher {
  final FakeManagedProcess? _process;
  final FakeManagedProcess Function()? processFactory;
  final bool shouldFail;
  ProcessLaunchRequest? lastLaunchRequest;

  FakeProcessLauncher({
    FakeManagedProcess? process,
    this.processFactory,
    this.shouldFail = false,
  }) : _process = process;

  FakeManagedProcess get process => _process ?? FakeManagedProcess();

  @override
  Future<ManagedProcess> start(ProcessLaunchRequest request) async {
    lastLaunchRequest = request;
    if (shouldFail) {
      throw Exception('Impossibile avviare il processo fake.');
    }
    if (processFactory != null) {
      return processFactory!();
    }
    if (_process != null && !_process!.isExited) {
      return _process!;
    }
    return FakeManagedProcess();
  }
}

/// PortAllocator fake che restituisce la porta specificata o 8080.
class FakePortAllocator implements PortAllocator {
  final int allocatedPort;
  final bool shouldFail;

  const FakePortAllocator({this.allocatedPort = 8080, this.shouldFail = false});

  @override
  Future<int> allocatePort(
      {int? preferredPort, String host = '127.0.0.1'}) async {
    if (shouldFail) {
      throw Exception('Impossibile allocare una porta di loopback.');
    }
    return preferredPort ?? allocatedPort;
  }
}

/// HealthProbe fake per simulare risposte del server nei test offline.
class FakeLlamaServerHealthProbe implements HealthProbe {
  bool isResponsive;
  bool modelVisible;
  int statusCode;
  bool isDisposed = false;

  FakeLlamaServerHealthProbe({
    this.isResponsive = true,
    this.modelVisible = true,
    this.statusCode = 200,
  });

  @override
  Future<HealthProbeResult> probe({
    required Uri baseUri,
    String? expectedModelAlias,
    Duration timeout = const Duration(seconds: 2),
  }) async {
    return HealthProbeResult(
      responsive: isResponsive,
      statusCode: statusCode,
      modelVisible: modelVisible,
      observedAt: DateTime.now(),
      diagnostics: {'fake': true},
    );
  }

  @override
  Future<void> dispose() async {
    isDisposed = true;
  }
}

/// FileSystem fake per validare configurazioni nei test.
class FakeFileSystem implements ManagedFileSystem {
  final Set<String> existingFiles;
  final Set<String> existingDirectories;

  const FakeFileSystem({
    this.existingFiles = const {},
    this.existingDirectories = const {},
  });

  @override
  bool fileExists(String path) => existingFiles.contains(path);

  @override
  bool directoryExists(String path) => existingDirectories.contains(path);
}
