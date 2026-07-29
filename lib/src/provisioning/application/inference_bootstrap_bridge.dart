import 'package:meta/meta.dart';

import '../../agent_runtime/runtime/adapters/managed_llama_server/managed_llama_server_configuration.dart';
import '../../bootstrap/managed_inference_topology.dart';
import '../../provisioning/cli/aura_cli_environment.dart';
import '../../provisioning/cli/local_inference_service_provider.dart';
import '../../provisioning/domain/configured_model_reference.dart';
import '../../provisioning/domain/installation_record.dart';
import '../../provisioning/domain/runtime_dependency_models.dart';

// ---------------------------------------------------------------------------
// Risultato tipizzato della risoluzione della configurazione di bootstrap.
// ---------------------------------------------------------------------------

/// Base della gerarchia sealed per il risultato della risoluzione bootstrap.
sealed class InferenceBootstrapResolution {
  const InferenceBootstrapResolution();
}

/// Risoluzione valida in modalità dual-managed: due processi `llama-server`
/// distinti, uno per l'Actor ed uno per l'Evaluator.
@immutable
final class ManagedDualResolution extends InferenceBootstrapResolution {
  /// Topologia role-aware con configurazioni Actor ed Evaluator.
  final ManagedInferenceTopology topology;

  const ManagedDualResolution({required this.topology});
}

/// Risoluzione in modalità external OpenAI-compatible.
@immutable
final class ExternalResolution extends InferenceBootstrapResolution {
  /// URI del server di inferenza esterno.
  final Uri endpoint;

  const ExternalResolution({required this.endpoint});
}

/// Risoluzione in modalità rule-based (offline deterministico).
///
/// Prodotta solo quando il runtime mode è impostato esplicitamente a `ruleBased`.
@immutable
final class RuleBasedResolution extends InferenceBootstrapResolution {
  const RuleBasedResolution();
}

/// Risoluzione non valida: la configurazione persistita è incompleta o incoerente.
///
/// Non produce mai un fallback automatico verso [RuleBasedResolution]: l'errore
/// deve essere propagato all'UI o al chiamante per una gestione esplicita.
@immutable
final class InvalidResolution extends InferenceBootstrapResolution {
  /// Causa tipizzata del fallimento.
  final InferenceBootstrapFailureReason reason;

  /// Messaggio sanitizzato (senza path locali, senza dati sensibili).
  final String sanitizedMessage;

  const InvalidResolution({
    required this.reason,
    required this.sanitizedMessage,
  });
}

/// Cause tipizzate di un [InvalidResolution].
enum InferenceBootstrapFailureReason {
  /// L'eseguibile `llama-server` è configurato ma non trovato sul filesystem.
  runtimeExecutableMissing,

  /// Il modello Actor è configurato ma il file non è raggiungibile.
  actorModelMissing,

  /// Il modello Evaluator è configurato ma il file non è raggiungibile.
  evaluatorModelMissing,

  /// Il runtime è configurato ma il file del modello per almeno un ruolo è assente.
  incompleteModelConfiguration,

  /// La configurazione è strutturalmente inconsistente (es. nessun runtime + modelli presenti).
  inconsistentConfiguration,

  /// Errore di I/O durante la lettura del record persistito.
  persistedRecordUnreadable,
}

// ---------------------------------------------------------------------------
// Bridge resolver (adattatore puro: nessun processo, nessun bridge HTTP).
// ---------------------------------------------------------------------------

/// Adattatore di configurazione: traduce il [ModelConfigurationRecord] persistito
/// dalla Fase 6.4f in un risultato tipizzato [InferenceBootstrapResolution].
///
/// Questo componente:
/// - Non avvia processi.
/// - Non crea bridge HTTP.
/// - Non gestisce lifecycle.
/// - Non dipende dal widget tree Flutter.
///
/// L'unica responsabilità è leggere il record persistito e costruire la
/// configurazione corretta da passare al [DefaultApplicationBootstrap].
final class InferenceBootstrapBridge {
  /// Factory per la costruzione dell'ambiente CLI (override per test).
  final AuraCliEnvironment Function()? _environmentFactory;

  const InferenceBootstrapBridge({
    AuraCliEnvironment Function()? environmentFactory,
  }) : _environmentFactory = environmentFactory;

  /// Risolve la configurazione di bootstrap leggendo il record persistito su disco.
  ///
  /// Restituisce un [InferenceBootstrapResolution] tipizzato. Non effettua mai
  /// una degradazione silenziosa verso [RuleBasedResolution] in caso di errore:
  /// restituisce [InvalidResolution] con la causa tipizzata.
  Future<InferenceBootstrapResolution> resolve({
    String sessionId = 'bootstrap-session',
    Map<String, String> environmentOverride = const {},
  }) async {
    try {
      final environment = _environmentFactory != null
          ? _environmentFactory!()
          : AuraCliEnvironment.fromPlatform(
              environment: environmentOverride,
            );

      final services = LocalInferenceServiceProvider.create(
        environment: environment,
      );

      final snapshot = await services.inferenceFacade.getSnapshot();
      final runtime = snapshot.runtimeConfiguration;
      final models = snapshot.modelConfiguration;

      // Nessuna configurazione runtime → configurazione incompleta.
      if (runtime == null || runtime.executablePath.trim().isEmpty) {
        return const InvalidResolution(
          reason: InferenceBootstrapFailureReason.incompleteModelConfiguration,
          sanitizedMessage:
              'Nessun runtime llama-server configurato. Eseguire "aura runtime set" prima di avviare l\'applicazione.',
        );
      }

      // Runtime configurato ma non valido (status != valid).
      if (runtime.validationStatus != LlamaServerValidationStatus.valid) {
        return const InvalidResolution(
          reason: InferenceBootstrapFailureReason.runtimeExecutableMissing,
          sanitizedMessage:
              'Il runtime llama-server configurato non ha superato la validazione. '
              'Eseguire "aura runtime status" per dettagli.',
        );
      }

      final actorRef = models.actor;
      final evaluatorRef = models.evaluator;

      if (actorRef == null && evaluatorRef == null) {
        return const InvalidResolution(
          reason: InferenceBootstrapFailureReason.incompleteModelConfiguration,
          sanitizedMessage: 'Nessun modello Actor né Evaluator configurato. '
              'Eseguire "aura model bind" prima di avviare l\'applicazione.',
        );
      }

      if (actorRef == null) {
        return const InvalidResolution(
          reason: InferenceBootstrapFailureReason.incompleteModelConfiguration,
          sanitizedMessage: 'Modello Actor non configurato. '
              'Eseguire "aura model bind --role actor" prima di avviare l\'applicazione.',
        );
      }

      if (evaluatorRef == null) {
        return const InvalidResolution(
          reason: InferenceBootstrapFailureReason.incompleteModelConfiguration,
          sanitizedMessage: 'Modello Evaluator non configurato. '
              'Eseguire "aura model bind --role evaluator" prima di avviare l\'applicazione.',
        );
      }

      Future<String?> resolveModelPath(ConfiguredModelReference? ref) async {
        if (ref == null) return null;
        if (ref is ExternalModelReference) return ref.absolutePath;
        if (ref is ManagedModelReference) {
          final record =
              await services.installationRecordRepository.readRecord();
          final descriptor = record.findInstallation(ref.installationId);
          if (descriptor == null ||
              descriptor.status != InstallationStatus.verified) {
            return null;
          }
          final installDir =
              services.pathResolver.resolveAppManagedRelativePath(
            descriptor.relativeInstallPath,
          );
          final entryFileName = descriptor.entryFileName ?? '';
          return '$installDir\\$entryFileName';
        }
        return null;
      }

      final actorPath = await resolveModelPath(actorRef);
      final evaluatorPath = await resolveModelPath(evaluatorRef);

      if (actorPath == null ||
          actorPath.trim().isEmpty ||
          !await services.fileSystem.fileExists(actorPath)) {
        return const InvalidResolution(
          reason: InferenceBootstrapFailureReason.actorModelMissing,
          sanitizedMessage:
              'Percorso del modello Actor non valido o file non presente sul disco. Riconfigurare con "aura model bind --role actor".',
        );
      }

      if (evaluatorPath == null ||
          evaluatorPath.trim().isEmpty ||
          !await services.fileSystem.fileExists(evaluatorPath)) {
        return const InvalidResolution(
          reason: InferenceBootstrapFailureReason.evaluatorModelMissing,
          sanitizedMessage:
              'Percorso del modello Evaluator non valido o file non presente sul disco. Riconfigurare con "aura model bind --role evaluator".',
        );
      }

      final appManagedRoot = environment.appManagedRoot;
      final actorLogPath =
          '$appManagedRoot/runtime/logs/actor_llama_server.log';
      final evaluatorLogPath =
          '$appManagedRoot/runtime/logs/evaluator_llama_server.log';

      final actorConfig = ManagedLlamaServerConfiguration(
        executablePath: runtime.executablePath,
        modelPath: actorPath,
        modelAlias: 'aura.actor.primary',
        gpuLayers: 99,
        logFilePath: actorLogPath,
        startupTimeout: const Duration(seconds: 60),
        shutdownTimeout: const Duration(seconds: 15),
        apiKey: 'managed-actor-secret',
        diagnosticMode: false,
      );

      final evaluatorConfig = ManagedLlamaServerConfiguration(
        executablePath: runtime.executablePath,
        modelPath: evaluatorPath,
        modelAlias: 'aura.evaluator.primary',
        gpuLayers: 99,
        logFilePath: evaluatorLogPath,
        startupTimeout: const Duration(seconds: 45),
        shutdownTimeout: const Duration(seconds: 10),
        apiKey: 'managed-evaluator-secret',
        diagnosticMode: false,
      );

      final topology = ManagedInferenceTopology(
        actor: ManagedRoleRuntimeConfiguration(
          role: InferenceModelRole.actor,
          modelId: 'aura.actor.primary',
          serverConfiguration: actorConfig,
        ),
        evaluator: ManagedRoleRuntimeConfiguration(
          role: InferenceModelRole.evaluator,
          modelId: 'aura.evaluator.primary',
          serverConfiguration: evaluatorConfig,
        ),
      );

      return ManagedDualResolution(topology: topology);
    } catch (e) {
      return const InvalidResolution(
        reason: InferenceBootstrapFailureReason.persistedRecordUnreadable,
        sanitizedMessage: 'Impossibile leggere la configurazione persistita. '
            'Verificare i permessi sulla cartella dati di A.U.R.A.',
      );
    }
  }
}
