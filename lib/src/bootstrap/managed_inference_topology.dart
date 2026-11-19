import 'package:meta/meta.dart';
import '../agent_runtime/runtime/adapters/managed_llama_server/managed_llama_server_configuration.dart';

/// Ruoli di inferenza gestiti dal runtime dual-process di A.U.R.A.
enum InferenceModelRole {
  /// Ruolo diegetico: genera le risposte narrative in-character (PANOPTICON).
  actor,

  /// Ruolo analitico: classifica la semantica dell'input e produce i delta numerici.
  evaluator,
}

/// Configurazione runtime per un singolo ruolo di inferenza in modalità managed.
///
/// Associa in modo esplicito un ruolo ([role]) a un identificatore logico ([modelId])
/// e alla configurazione del processo `llama-server` ([serverConfiguration]).
@immutable
final class ManagedRoleRuntimeConfiguration {
  /// Ruolo di inferenza coperto da questa configurazione.
  final InferenceModelRole role;

  /// Identificatore logico del modello usato nel payload delle API.
  final String modelId;

  /// Configurazione del processo `llama-server` per questo ruolo.
  final ManagedLlamaServerConfiguration serverConfiguration;

  const ManagedRoleRuntimeConfiguration({
    required this.role,
    required this.modelId,
    required this.serverConfiguration,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ManagedRoleRuntimeConfiguration &&
          runtimeType == other.runtimeType &&
          role == other.role &&
          modelId == other.modelId &&
          serverConfiguration == other.serverConfiguration;

  @override
  int get hashCode => Object.hash(role, modelId, serverConfiguration);

  @override
  String toString() =>
      'ManagedRoleRuntimeConfiguration(role: ${role.name}, modelId: $modelId)';
}

/// Topologia di inferenza dual-role per la modalità `managedLlamaServer`.
///
/// Descrive l'intera composizione del runtime gestito: un processo Actor e un
/// processo Evaluator separati, ciascuno con il proprio modello e la propria
/// configurazione di server.
///
/// Regole di validità:
/// - Entrambi i campi [actor] ed [evaluator] devono essere presenti.
/// - Le porte preferite dei due ruoli non devono coincidere (se specificate).
@immutable
final class ManagedInferenceTopology {
  /// Configurazione runtime del ruolo Actor (PANOPTICON).
  final ManagedRoleRuntimeConfiguration actor;

  /// Configurazione runtime del ruolo Evaluator.
  final ManagedRoleRuntimeConfiguration evaluator;

  const ManagedInferenceTopology({
    required this.actor,
    required this.evaluator,
  });

  /// `true` se Actor ed Evaluator puntano allo stesso file GGUF.
  ///
  /// In questo caso il bootstrap avvia un solo processo `llama-server` servito a
  /// entrambi i ruoli: due processi caricherebbero due copie dello stesso modello,
  /// raddoppiando la VRAM invece di risparmiarla.
  bool get sharesModelFile {
    // Confronto case-insensitive solo per percorsi Windows (lettera di unità o
    // UNC): su POSIX due file che differiscono per maiuscole sono distinti.
    String normalize(String path) {
      final trimmed = path.trim();
      final isWindowsPath = RegExp(r'^([A-Za-z]:[\\/]|\\\\)').hasMatch(trimmed);
      return isWindowsPath
          ? trimmed.replaceAll('/', r'\').toLowerCase()
          : trimmed;
    }

    return normalize(actor.serverConfiguration.modelPath) ==
        normalize(evaluator.serverConfiguration.modelPath);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ManagedInferenceTopology &&
          runtimeType == other.runtimeType &&
          actor == other.actor &&
          evaluator == other.evaluator;

  @override
  int get hashCode => Object.hash(actor, evaluator);

  @override
  String toString() =>
      'ManagedInferenceTopology(actor: ${actor.modelId}, evaluator: ${evaluator.modelId})';
}
