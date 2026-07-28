import 'package:aura_core/aura_offline.dart';
import 'package:test/test.dart';

import 'llama_server_dependency_service_test.dart';

void main() {
  group('Tranche 6.4f.2 — WinGetDependencyAdapter Tests', () {
    test(
        'checkWinGetAvailable restituisce true quando winget --version risponde 0',
        () async {
      final launcher = TestProcessLauncher((req) async {
        if (req.executable == 'winget' && req.arguments.contains('--version')) {
          return TestManagedProcess(stdoutText: 'v1.7.10861');
        }
        return TestManagedProcess(exitCodeValue: 1);
      });

      final adapter = WinGetDependencyAdapter(processLauncher: launcher);
      final available = await adapter.checkWinGetAvailable();
      expect(available, isTrue);
    });

    test(
        'checkWinGetAvailable restituisce false quando winget non è disponibile',
        () async {
      final launcher = TestProcessLauncher((req) async {
        throw Exception('Process not found');
      });

      final adapter = WinGetDependencyAdapter(processLauncher: launcher);
      final available = await adapter.checkWinGetAvailable();
      expect(available, isFalse);
    });

    test(
        'getAssistance genera il comando di installazione assistita non bloccante',
        () async {
      final launcher = TestProcessLauncher((req) async {
        return TestManagedProcess(stdoutText: 'v1.7.10861');
      });

      final adapter = WinGetDependencyAdapter(processLauncher: launcher);
      final assistance = await adapter.getAssistance();

      expect(assistance.isWinGetAvailable, isTrue);
      expect(assistance.packageId, equals('ggerganov.llama.cpp'));
      expect(assistance.command,
          equals('winget install --id ggerganov.llama.cpp'));
      expect(assistance.requiresUserConfirmation, isTrue);
      expect(assistance.fallbackDownloadUri,
          equals('https://github.com/ggerganov/llama.cpp/releases'));
    });
  });
}
