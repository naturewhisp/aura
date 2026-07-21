import 'package:meta/meta.dart';
import '../agent_runtime/inference_bridge.dart';
import '../agent_runtime/runtime/inference_runtime.dart';
import '../game_controller.dart';
import 'application_runtime_mode.dart';

/// DTO contenente informazioni diagnostiche e di stato non sensibili sul runtime attivo.
@immutable
class ApplicationRuntimeStatus {
  /// Modalità runtime effettiva.
  final ApplicationRuntimeMode runtimeMode;

  /// Specifica se il runtime è operativo e risponde ai controlli.
  final bool isHealthy;

  /// Descrizione sintetica dello stato di salute del runtime.
  final String statusDescription;

  /// Mappa opzionale di dettagli diagnostici non sensibili.
  final Map<String, Object?> diagnostics;

  /// Costruisce un'istanza di [ApplicationRuntimeStatus].
  const ApplicationRuntimeStatus({
    required this.runtimeMode,
    required this.isHealthy,
    required this.statusDescription,
    this.diagnostics = const {},
  });
}

/// Risultato immutabile restituito al termine del bootstrap applicativo.
///
/// Espone i servizi e i controller pronti per l'uso da parte dell'App, della CLI o del Simulatore,
/// senza rivelare segreti, endpoint HTTP o classi di adapter concrete.
@immutable
class ApplicationBootstrapResult {
  /// Controller centrale del motore di gioco.
  final GameController controller;

  /// Bridge di inferenza attivo per le comunicazioni con gli agenti.
  final InferenceBridge activeBridge;

  /// Istanza opzionale di [InferenceRuntime] se la modalità attiva lo supporta.
  final InferenceRuntime? runtime;

  /// Modalità runtime effettivamente inizializzata.
  final ApplicationRuntimeMode runtimeMode;

  /// Stato di salute e diagnostica iniziale del runtime.
  final ApplicationRuntimeStatus status;

  /// Callback interna per la dismissione delle risorse.
  final Future<void> Function() onDispose;

  /// Costruisce un'istanza di [ApplicationBootstrapResult].
  const ApplicationBootstrapResult({
    required this.controller,
    required this.activeBridge,
    this.runtime,
    required this.runtimeMode,
    required this.status,
    required this.onDispose,
  });

  /// Esegue la chiusura sicura ed idempotente di tutte le risorse gestite dal bootstrap.
  Future<void> dispose() async {
    await onDispose();
  }
}
