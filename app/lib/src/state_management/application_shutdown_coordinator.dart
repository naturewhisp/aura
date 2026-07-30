import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:aura_core/aura_core.dart';
import 'desktop_shell_controller.dart';
import 'game_controller_notifier.dart';

/// Coordinatore single-flight per la sequenza ordinata ed atomica di spegnimento dell'applicazione.
final class ApplicationShutdownCoordinator {
  final GameControllerNotifier notifier;
  final DesktopShellController shellController;
  final WindowGeometryPersistenceCoordinator persistenceCoordinator;
  final DesktopWindowController windowController;

  final void Function()? onNativeExit;

  Future<void>? _shutdownFuture;

  ApplicationShutdownCoordinator({
    required this.notifier,
    required this.shellController,
    required this.persistenceCoordinator,
    required this.windowController,
    this.onNativeExit,
  });

  /// Indica se lo spegnimento è attualmente in corso.
  bool get isShutdownInProgress => _shutdownFuture != null;

  /// Inizia o attende la sequenza di spegnimento ordinata (single-flight).
  Future<void> requestShutdown() {
    _shutdownFuture ??= _executeShutdown();
    return _shutdownFuture!;
  }

  Future<void> _executeShutdown() async {
    try {
      debugPrint(
          '[SHUTDOWN] Avvio coordinato dello spegnimento dell\'applicazione...');

      // 1. Flush finale della geometria e preferenze su disco (con tolleranza agli errori)
      try {
        await persistenceCoordinator.flush();
        debugPrint(
            '[SHUTDOWN] Preferenze e geometria della finestra salvate su disco.');
      } catch (e) {
        debugPrint(
            '[SHUTDOWN] Impossibile salvare le preferenze durante lo shutdown: $e');
      }

      // 2. Shutdown del runtime gestionale dei modelli (LlamaServer, GameController)
      try {
        await notifier.shutdown();
        debugPrint(
            '[SHUTDOWN] Managed runtime e server LLM arrestati con successo.');
      } catch (e) {
        debugPrint('[SHUTDOWN] Errore durante lo spegnimento del runtime: $e');
      }

      // 3. Chiusura e dispose dei controller della shell desktop
      try {
        shellController.dispose();
        await windowController.closeWindow();
        await windowController.dispose();
        debugPrint(
            '[SHUTDOWN] Finestra nativa e risorse della shell desktop rilasciate.');
      } catch (e) {
        debugPrint(
            '[SHUTDOWN] Errore durante la chiusura delle finestre/controller: $e');
      }
    } finally {
      // 4. Uscita dal processo nativo
      if (onNativeExit != null) {
        onNativeExit!();
      } else if (Platform.isWindows) {
        debugPrint('[SHUTDOWN] Uscita dal processo nativo.');
        exit(0);
      }
    }
  }
}
