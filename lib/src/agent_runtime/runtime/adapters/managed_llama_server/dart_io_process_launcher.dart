import 'dart:async';
import 'dart:io' as io;
import 'process_launcher.dart';

class _DartIoManagedProcess implements ManagedProcess {
  final io.Process _process;

  _DartIoManagedProcess(this._process);

  @override
  int get pid => _process.pid;

  @override
  Stream<List<int>> get stdoutBytes => _process.stdout;

  @override
  Stream<List<int>> get stderrBytes => _process.stderr;

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  bool kill([io.ProcessSignal signal = io.ProcessSignal.sigterm]) {
    return _process.kill(signal);
  }
}

/// Implementazione concreta di [ProcessLauncher] basata sul pacchetto `dart:io`.
class DartIoProcessLauncher implements ProcessLauncher {
  const DartIoProcessLauncher();

  @override
  Future<ManagedProcess> start(ProcessLaunchRequest request) async {
    final process = await io.Process.start(
      request.executable,
      request.arguments,
      workingDirectory: request.workingDirectory,
      environment: request.environment,
      runInShell: false,
    );
    return _DartIoManagedProcess(process);
  }
}

/// Implementazione di [ManagedFileSystem] basata sul pacchetto `dart:io`.
class LocalFileSystem implements ManagedFileSystem {
  const LocalFileSystem();

  @override
  bool fileExists(String path) => io.File(path).existsSync();

  @override
  bool directoryExists(String path) => io.Directory(path).existsSync();
}
