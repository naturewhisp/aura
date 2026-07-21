import 'dart:async';
import 'dart:io' show ProcessSignal;

/// Richiesta strutturata per l'avvio di un processo controllato dal runtime.
class ProcessLaunchRequest {
  final String executable;
  final List<String> arguments;
  final String? workingDirectory;
  final Map<String, String>? environment;
  final bool runInShell;
  final bool detached;

  const ProcessLaunchRequest({
    required this.executable,
    required this.arguments,
    this.workingDirectory,
    this.environment,
    this.runInShell = false,
    this.detached = false,
  });
}

/// Rappresenta un processo gestito in modo astratto ed platform-neutral.
abstract interface class ManagedProcess {
  int get pid;
  Stream<List<int>> get stdoutBytes;
  Stream<List<int>> get stderrBytes;
  Future<int> get exitCode;
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]);
}

/// Contratto iniettabile per il lancio dei processi sidecar.
abstract interface class ProcessLauncher {
  Future<ManagedProcess> start(ProcessLaunchRequest request);
}
