import 'package:meta/meta.dart';

import '../../agent_runtime/runtime/adapters/managed_llama_server/dart_io_process_launcher.dart';
import '../../agent_runtime/runtime/adapters/managed_llama_server/process_launcher.dart';

/// Package ID di default consigliato per `llama.cpp` su WinGet.
const String kDefaultWinGetPackageId = 'ggerganov.llama.cpp';

/// URL di download delle release ufficiali di fallback.
const String kOfficialLlamaCppDownloadUrl =
    'https://github.com/ggerganov/llama.cpp/releases';

/// DTO che racchiude le istruzioni assistite per l'installazione di `llama-server`.
@immutable
final class InstallationAssistance {
  final bool isWinGetAvailable;
  final String packageId;
  final String command;
  final bool requiresUserConfirmation;
  final String fallbackDownloadUri;

  const InstallationAssistance({
    required this.isWinGetAvailable,
    required this.packageId,
    required this.command,
    this.requiresUserConfirmation = true,
    this.fallbackDownloadUri = kOfficialLlamaCppDownloadUrl,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InstallationAssistance &&
          runtimeType == other.runtimeType &&
          isWinGetAvailable == other.isWinGetAvailable &&
          packageId == other.packageId &&
          command == other.command &&
          requiresUserConfirmation == other.requiresUserConfirmation &&
          fallbackDownloadUri == other.fallbackDownloadUri;

  @override
  int get hashCode => Object.hash(
        isWinGetAvailable,
        packageId,
        command,
        requiresUserConfirmation,
        fallbackDownloadUri,
      );

  @override
  String toString() =>
      'InstallationAssistance(winGet: $isWinGetAvailable, command: "$command")';
}

/// Adapter infrastrutturale facoltativo per l'assistenza all'installazione di `llama-server` via Windows WinGet.
final class WinGetDependencyAdapter {
  final ProcessLauncher _processLauncher;
  final String defaultPackageId;

  WinGetDependencyAdapter({
    ProcessLauncher processLauncher = const DartIoProcessLauncher(),
    this.defaultPackageId = kDefaultWinGetPackageId,
  }) : _processLauncher = processLauncher;

  /// Verifica se l'eseguibile `winget` è installato ed eseguibile nel sistema.
  Future<bool> checkWinGetAvailable() async {
    try {
      final process = await _processLauncher.start(
        const ProcessLaunchRequest(
          executable: 'winget',
          arguments: ['--version'],
          runInShell: false,
        ),
      );

      final exitCode = await process.exitCode.timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          process.kill();
          return -1;
        },
      );

      return exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Genera l'assistenza di installazione basata sulla presenza di WinGet o sulle istruzioni di fallback.
  Future<InstallationAssistance> getAssistance({
    String? customPackageId,
  }) async {
    final isAvailable = await checkWinGetAvailable();
    final packageId = customPackageId?.trim().isNotEmpty == true
        ? customPackageId!.trim()
        : defaultPackageId;

    final command = 'winget install --id $packageId';

    return InstallationAssistance(
      isWinGetAvailable: isAvailable,
      packageId: packageId,
      command: command,
      requiresUserConfirmation: true,
      fallbackDownloadUri: kOfficialLlamaCppDownloadUrl,
    );
  }
}
