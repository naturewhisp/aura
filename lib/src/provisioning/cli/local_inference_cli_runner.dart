import 'dart:convert';

import '../application/first_run_model_setup_facade.dart';
import '../application/local_inference_facade.dart';
import '../application/runtime_model_settings_facade.dart';
import '../domain/configured_model_reference.dart';
import '../domain/local_inference_preflight_models.dart';
import '../domain/provisioning_options.dart';

/// Risultato dell'esecuzione di un comando CLI dell'inferenza locale.
final class CliExecutionResult {
  final int exitCode;
  final String outputText;

  const CliExecutionResult({
    required this.exitCode,
    required this.outputText,
  });
}

/// Adapter CLI per la gestione dell'inferenza locale (`aura runtime`, `aura model`, `aura preflight`).
final class LocalInferenceCliRunner {
  final LocalInferenceFacade _inferenceFacade;
  final RuntimeModelSettingsFacade _settingsFacade;
  final FirstRunModelSetupFacade _firstRunFacade;

  LocalInferenceCliRunner({
    required LocalInferenceFacade inferenceFacade,
    required RuntimeModelSettingsFacade settingsFacade,
    required FirstRunModelSetupFacade firstRunFacade,
  })  : _inferenceFacade = inferenceFacade,
        _settingsFacade = settingsFacade,
        _firstRunFacade = firstRunFacade;

  /// Esegue i comandi della categoria `runtime`.
  Future<CliExecutionResult> runRuntimeCommand(
    List<String> args, {
    bool jsonOutput = false,
  }) async {
    if (args.isEmpty || args.first == 'status') {
      return _handleRuntimeStatus(jsonOutput: jsonOutput);
    }

    final subCommand = args.first.toLowerCase();
    switch (subCommand) {
      case 'detect':
        return _handleRuntimeDetect(jsonOutput: jsonOutput);
      case 'set':
        if (args.length < 2) {
          return _errorResult(
            exitCode: 2,
            code: 'missing_argument',
            message: 'Specificare il percorso dell\'eseguibile llama-server.',
            jsonOutput: jsonOutput,
          );
        }
        return _handleRuntimeSet(args[1], jsonOutput: jsonOutput);
      case 'clear':
        return _handleRuntimeClear(jsonOutput: jsonOutput);
      default:
        return _errorResult(
          exitCode: 2,
          code: 'invalid_subcommand',
          message: 'Sottocomando runtime non valido: $subCommand',
          jsonOutput: jsonOutput,
        );
    }
  }

  /// Esegue i comandi della categoria `model`.
  Future<CliExecutionResult> runModelCommand(
    List<String> args, {
    bool jsonOutput = false,
  }) async {
    if (args.isEmpty || args.first == 'status') {
      return _handleModelStatus(jsonOutput: jsonOutput);
    }

    final subCommand = args.first.toLowerCase();
    switch (subCommand) {
      case 'list':
        return _handleModelList(jsonOutput: jsonOutput);
      case 'scan':
        final customPath = args.length > 1 ? args[1] : null;
        return _handleModelScan(customPath: customPath, jsonOutput: jsonOutput);
      case 'bind':
        return _handleModelBind(args.sublist(1), jsonOutput: jsonOutput);
      case 'clear':
        return _handleModelClear(args.sublist(1), jsonOutput: jsonOutput);
      case 'consent':
        return _handleModelConsent(args.sublist(1), jsonOutput: jsonOutput);
      default:
        return _errorResult(
          exitCode: 2,
          code: 'invalid_subcommand',
          message: 'Sottocomando model non valido: $subCommand',
          jsonOutput: jsonOutput,
        );
    }
  }

  /// Esegue i comandi della categoria `preflight`.
  Future<CliExecutionResult> runPreflightCommand(
    List<String> args, {
    bool jsonOutput = false,
  }) async {
    final subCommand = args.isEmpty ? 'quick' : args.first.toLowerCase();
    switch (subCommand) {
      case 'quick':
        return _handlePreflight(
            depth: PreflightDepth.quick, jsonOutput: jsonOutput);
      case 'probe':
        return _handlePreflight(
            depth: PreflightDepth.runtimeProbe, jsonOutput: jsonOutput);
      default:
        return _errorResult(
          exitCode: 2,
          code: 'invalid_subcommand',
          message:
              'Sottocomando preflight non valido: $subCommand. Utilizzare quick o probe.',
          jsonOutput: jsonOutput,
        );
    }
  }

  // --- Handlers Runtime ---

  Future<CliExecutionResult> _handleRuntimeStatus(
      {required bool jsonOutput}) async {
    try {
      final snapshot = await _inferenceFacade.getSnapshot();
      final runtime = snapshot.runtimeConfiguration;
      final path = runtime?.executablePath;

      if (jsonOutput) {
        return CliExecutionResult(
          exitCode: path != null ? 0 : 3,
          outputText: jsonEncode({
            'ok': path != null,
            'code':
                path != null ? 'runtime_configured' : 'runtime_unconfigured',
            'executablePath': path,
            'validationStatus': runtime?.validationStatus.name,
            'detectedVersion': runtime?.detectedVersion,
          }),
        );
      }

      if (path == null) {
        return const CliExecutionResult(
          exitCode: 3,
          outputText: 'Runtime non configurato.',
        );
      }

      return CliExecutionResult(
        exitCode: 0,
        outputText:
            'Runtime configurato:\n  Path: $path\n  Stato: ${runtime?.validationStatus.name ?? 'unknown'}',
      );
    } catch (e) {
      return _errorResult(
        exitCode: 1,
        code: 'operation_failed',
        message: 'Impossibile accedere allo stato del runtime.',
        jsonOutput: jsonOutput,
      );
    }
  }

  Future<CliExecutionResult> _handleRuntimeDetect(
      {required bool jsonOutput}) async {
    try {
      final result = await _inferenceFacade.detectRuntime();
      final candidate = result.effectiveCandidate;

      if (jsonOutput) {
        return CliExecutionResult(
          exitCode: candidate != null ? 0 : 4,
          outputText: jsonEncode({
            'ok': candidate != null,
            'code':
                candidate != null ? 'runtime_detected' : 'runtime_not_found',
            'effectiveCandidate': candidate,
            'configuredCandidate': result.configuredCandidate,
            'detectedFallback': result.detectedFallback,
            'warnings': result.warnings,
          }),
        );
      }

      if (candidate == null) {
        return const CliExecutionResult(
          exitCode: 4,
          outputText:
              'Nessun eseguibile llama-server rilevato automaticamente nel PATH o percorsi predefiniti.',
        );
      }

      return CliExecutionResult(
        exitCode: 0,
        outputText: 'Eseguibile llama-server rilevato:\n  $candidate',
      );
    } catch (e) {
      return _errorResult(
        exitCode: 1,
        code: 'detection_failed',
        message: 'Errore durante la scansione dell\'eseguibile llama-server.',
        jsonOutput: jsonOutput,
      );
    }
  }

  Future<CliExecutionResult> _handleRuntimeSet(String path,
      {required bool jsonOutput}) async {
    try {
      final config = await _settingsFacade.setRuntimeExecutable(path);
      if (jsonOutput) {
        return CliExecutionResult(
          exitCode: 0,
          outputText: jsonEncode({
            'ok': true,
            'code': 'runtime_updated',
            'executablePath': config.executablePath,
            'validationStatus': config.validationStatus.name,
          }),
        );
      }
      return CliExecutionResult(
        exitCode: 0,
        outputText:
            'Eseguibile llama-server configurato con successo:\n  ${config.executablePath}',
      );
    } catch (e) {
      return _errorResult(
        exitCode: 4,
        code: 'runtime_invalid',
        message: 'Percorso eseguibile llama-server non valido.',
        jsonOutput: jsonOutput,
      );
    }
  }

  Future<CliExecutionResult> _handleRuntimeClear(
      {required bool jsonOutput}) async {
    try {
      await _settingsFacade.clearRuntimeExecutable();
      if (jsonOutput) {
        return CliExecutionResult(
          exitCode: 0,
          outputText: jsonEncode({
            'ok': true,
            'code': 'runtime_cleared',
          }),
        );
      }
      return const CliExecutionResult(
        exitCode: 0,
        outputText: 'Configurazione runtime rimossa.',
      );
    } catch (e) {
      return _errorResult(
        exitCode: 1,
        code: 'clear_failed',
        message: 'Impossibile rimuovere la configurazione del runtime.',
        jsonOutput: jsonOutput,
      );
    }
  }

  // --- Handlers Model ---

  Future<CliExecutionResult> _handleModelStatus(
      {required bool jsonOutput}) async {
    try {
      final snapshot = await _inferenceFacade.getSnapshot();
      final models = snapshot.modelConfiguration;
      final actor = models.actor;
      final evaluator = models.evaluator;

      final isComplete = actor != null && evaluator != null;

      if (jsonOutput) {
        return CliExecutionResult(
          exitCode: isComplete ? 0 : 3,
          outputText: jsonEncode({
            'ok': isComplete,
            'code': isComplete ? 'models_configured' : 'models_incomplete',
            'actor': actor != null ? _referenceToJson(actor) : null,
            'evaluator': evaluator != null ? _referenceToJson(evaluator) : null,
            'isConsentValid': snapshot.isConsentValid,
          }),
        );
      }

      final sb = StringBuffer('Stato modelli dell\'inferenza locale:\n');
      sb.writeln(
          '  Actor:     ${actor != null ? _referenceToString(actor) : 'NON CONFIGURATO'}');
      sb.writeln(
          '  Evaluator: ${evaluator != null ? _referenceToString(evaluator) : 'NON CONFIGURATO'}');
      sb.write(
          '  Consenso esterno: ${snapshot.isConsentValid ? 'VALIDO' : 'NON ACCETTATO / NECESSARIO'}');

      return CliExecutionResult(
        exitCode: isComplete ? 0 : 3,
        outputText: sb.toString(),
      );
    } catch (e) {
      return _errorResult(
        exitCode: 1,
        code: 'status_failed',
        message: 'Impossibile verificare lo stato dei modelli.',
        jsonOutput: jsonOutput,
      );
    }
  }

  Future<CliExecutionResult> _handleModelList(
      {required bool jsonOutput}) async {
    try {
      final models = await _inferenceFacade.listManagedModels();

      if (jsonOutput) {
        return CliExecutionResult(
          exitCode: 0,
          outputText: jsonEncode({
            'ok': true,
            'count': models.length,
            'models': models
                .map((m) => {
                      'installationId': m.installationId,
                      'artifactId': m.artifactId,
                      'displayName': m.displayName,
                      'version': m.version,
                      'sizeBytes': m.sizeBytes,
                      'relativeInstallPath': m.relativeInstallPath,
                    })
                .toList(),
          }),
        );
      }

      if (models.isEmpty) {
        return const CliExecutionResult(
          exitCode: 0,
          outputText: 'Nessun modello gestito installato nello store locale.',
        );
      }

      final sb = StringBuffer(
          'Modelli gestiti installati nello store (${models.length}):\n');
      for (final m in models) {
        sb.writeln(
            '  - [${m.installationId}] ${m.displayName} v${m.version} (${(m.sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB)');
      }

      return CliExecutionResult(
        exitCode: 0,
        outputText: sb.toString().trimRight(),
      );
    } catch (e) {
      return _errorResult(
        exitCode: 1,
        code: 'list_failed',
        message: 'Impossibile elencare i modelli gestiti.',
        jsonOutput: jsonOutput,
      );
    }
  }

  Future<CliExecutionResult> _handleModelScan(
      {String? customPath, required bool jsonOutput}) async {
    try {
      final candidates =
          await _inferenceFacade.scanExternalCandidates(customPath: customPath);

      if (jsonOutput) {
        return CliExecutionResult(
          exitCode: 0,
          outputText: jsonEncode({
            'ok': true,
            'count': candidates.length,
            'candidates': candidates
                .map((c) => {
                      'absolutePath': c.absolutePath,
                      'fileName': c.fileName,
                      'sizeBytes': c.sizeBytes,
                    })
                .toList(),
          }),
        );
      }

      if (candidates.isEmpty) {
        return CliExecutionResult(
          exitCode: 0,
          outputText: customPath != null
              ? 'Nessun file .gguf trovato nella cartella specificata:\n  $customPath'
              : 'Nessun candidato .gguf esterno trovato nei percorsi di scansione predefiniti.',
        );
      }

      final sb = StringBuffer(
          'Candidati modelli esterni (.gguf) trovati (${candidates.length}):\n');
      for (final c in candidates) {
        sb.writeln(
            '  - ${c.fileName} (${(c.sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB)\n    Path: ${c.absolutePath}');
      }

      return CliExecutionResult(
        exitCode: 0,
        outputText: sb.toString().trimRight(),
      );
    } catch (e) {
      return _errorResult(
        exitCode: 1,
        code: 'scan_failed',
        message: 'Errore durante la scansione dei modelli esterni.',
        jsonOutput: jsonOutput,
      );
    }
  }

  Future<CliExecutionResult> _handleModelBind(List<String> args,
      {required bool jsonOutput}) async {
    ModelActivationRole? role;
    String? managedId;
    String? externalPath;

    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      if (arg == '--role' && i + 1 < args.length) {
        final rStr = args[++i].toLowerCase();
        if (rStr == 'actor') role = ModelActivationRole.actor;
        if (rStr == 'evaluator') role = ModelActivationRole.evaluator;
      } else if (arg == '--managed' && i + 1 < args.length) {
        managedId = args[++i];
      } else if (arg == '--external' && i + 1 < args.length) {
        externalPath = args[++i];
      }
    }

    if (role == null) {
      return _errorResult(
        exitCode: 2,
        code: 'missing_role',
        message: 'Specificare il ruolo mediante --role actor|evaluator.',
        jsonOutput: jsonOutput,
      );
    }

    if (managedId == null && externalPath == null) {
      return _errorResult(
        exitCode: 2,
        code: 'missing_reference',
        message:
            'Specificare una fonte mediante --managed <id> oppure --external <path>.',
        jsonOutput: jsonOutput,
      );
    }

    if (managedId != null && externalPath != null) {
      return _errorResult(
        exitCode: 2,
        code: 'conflicting_arguments',
        message:
            'Non è possibile specificare sia --managed che --external simultaneamente.',
        jsonOutput: jsonOutput,
      );
    }

    try {
      final ref = managedId != null
          ? ManagedModelReference(installationId: managedId)
          : ExternalModelReference(absolutePath: externalPath!);

      final validation = role == ModelActivationRole.actor
          ? await _settingsFacade.bindActor(ref)
          : await _settingsFacade.bindEvaluator(ref);

      final isConsentMissing = !validation.isValid &&
          (validation.errorMessage?.contains('consenso') ?? false);

      if (isConsentMissing) {
        if (jsonOutput) {
          return CliExecutionResult(
            exitCode: 6,
            outputText: jsonEncode({
              'ok': false,
              'code': 'external_model_consent_required',
              'message':
                  'È richiesto il consenso informato prima di utilizzare un modello esterno.',
              'role': role.name,
              'reference': _referenceToJson(ref),
            }),
          );
        }
        return CliExecutionResult(
          exitCode: 6,
          outputText:
              'CONSENSO RICHIESTO: È necessario accettare il consenso informato prima di usare il modello esterno per ${role.name.toUpperCase()}.\nUtilizzare: aura model consent accept',
        );
      }

      if (jsonOutput) {
        return CliExecutionResult(
          exitCode: validation.isValid ? 0 : 5,
          outputText: jsonEncode({
            'ok': validation.isValid,
            'code':
                validation.isValid ? 'model_bound' : 'model_validation_failed',
            'role': role.name,
            'reference': _referenceToJson(ref),
            'errorMessage': validation.errorMessage,
          }),
        );
      }

      return CliExecutionResult(
        exitCode: validation.isValid ? 0 : 5,
        outputText:
            'Associazione modello completata per ${role.name.toUpperCase()}:\n  ${_referenceToString(ref)}'
            '${validation.isValid ? '' : '\n  Attenzione: segnalazione "${validation.errorMessage}"'}',
      );
    } catch (e) {
      return _errorResult(
        exitCode: 5,
        code: 'model_invalid',
        message:
            'Modello non valido o non associabile per il ruolo specificato.',
        jsonOutput: jsonOutput,
      );
    }
  }

  Future<CliExecutionResult> _handleModelClear(List<String> args,
      {required bool jsonOutput}) async {
    ModelActivationRole? role;

    for (var i = 0; i < args.length; i++) {
      if (args[i] == '--role' && i + 1 < args.length) {
        final rStr = args[++i].toLowerCase();
        if (rStr == 'actor') role = ModelActivationRole.actor;
        if (rStr == 'evaluator') role = ModelActivationRole.evaluator;
      }
    }

    if (role == null) {
      return _errorResult(
        exitCode: 2,
        code: 'missing_role',
        message:
            'Specificare il ruolo da rimuovere mediante --role actor|evaluator.',
        jsonOutput: jsonOutput,
      );
    }

    try {
      if (role == ModelActivationRole.actor) {
        await _settingsFacade.clearActorBinding();
      } else {
        await _settingsFacade.clearEvaluatorBinding();
      }

      if (jsonOutput) {
        return CliExecutionResult(
          exitCode: 0,
          outputText: jsonEncode({
            'ok': true,
            'code': 'model_binding_cleared',
            'role': role.name,
          }),
        );
      }

      return CliExecutionResult(
        exitCode: 0,
        outputText:
            'Associazione modello per ${role.name.toUpperCase()} rimossa.',
      );
    } catch (e) {
      return _errorResult(
        exitCode: 1,
        code: 'clear_failed',
        message:
            'Impossibile rimuovere l\'associazione del modello per ${role.name.toUpperCase()}.',
        jsonOutput: jsonOutput,
      );
    }
  }

  Future<CliExecutionResult> _handleModelConsent(List<String> args,
      {required bool jsonOutput}) async {
    final action = args.isEmpty ? 'status' : args.first.toLowerCase();

    switch (action) {
      case 'status':
        final snapshot = await _inferenceFacade.getSnapshot();
        if (jsonOutput) {
          return CliExecutionResult(
            exitCode: snapshot.isConsentValid ? 0 : 6,
            outputText: jsonEncode({
              'ok': snapshot.isConsentValid,
              'code': snapshot.isConsentValid
                  ? 'consent_accepted'
                  : 'consent_required',
              'isConsentValid': snapshot.isConsentValid,
            }),
          );
        }
        return CliExecutionResult(
          exitCode: snapshot.isConsentValid ? 0 : 6,
          outputText: snapshot.isConsentValid
              ? 'Consenso informato modelli esterni: GIÀ REGISTRATO'
              : 'Consenso informato modelli esterni: NON REGISTRATO / RICHIESTO',
        );

      case 'accept':
        await _settingsFacade.recordConsent();
        if (jsonOutput) {
          return CliExecutionResult(
            exitCode: 0,
            outputText: jsonEncode({
              'ok': true,
              'code': 'consent_recorded',
            }),
          );
        }
        return const CliExecutionResult(
          exitCode: 0,
          outputText:
              'Consenso informato per modelli esterni registrato con successo.',
        );

      default:
        return _errorResult(
          exitCode: 2,
          code: 'invalid_subcommand',
          message:
              'Azione consent non valida: $action. Utilizzare status o accept.',
          jsonOutput: jsonOutput,
        );
    }
  }

  // --- Handlers Preflight ---

  Future<CliExecutionResult> _handlePreflight({
    required PreflightDepth depth,
    required bool jsonOutput,
  }) async {
    try {
      final result = depth == PreflightDepth.quick
          ? await _inferenceFacade.runPreflight(depth: PreflightDepth.quick)
          : await _firstRunFacade.runFinalPreflight().then((s) =>
              s.preflightResult ?? const LocalInferencePreflightResult.ready());

      final exitCode = _mapPreflightExitCode(result);

      if (jsonOutput) {
        return CliExecutionResult(
          exitCode: exitCode,
          outputText: jsonEncode({
            'ok': result.isReady,
            'code': result.failureReason?.name ?? 'ready',
            'depth': depth.name,
            'affectedRole': result.affectedRole?.name,
            'sanitizedMessage': result.sanitizedMessage,
          }),
        );
      }

      if (result.isReady) {
        return CliExecutionResult(
          exitCode: 0,
          outputText:
              'PREFLIGHT VERIFIED [${depth.name.toUpperCase()}]: Sistema di inferenza locale pronto all\'uso.',
        );
      }

      return CliExecutionResult(
        exitCode: exitCode,
        outputText: 'PREFLIGHT FAILED [${depth.name.toUpperCase()}]:\n'
            '  Causa:      ${result.failureReason?.name ?? 'N/A'}\n'
            '  Ruolo:      ${result.affectedRole?.name ?? 'N/A'}\n'
            '  Dettaglio:  ${result.sanitizedMessage ?? 'Nessun dettaglio'}',
      );
    } catch (e) {
      return _errorResult(
        exitCode: 1,
        code: 'preflight_failed',
        message: 'Errore imprevisto durante la verifica di preflight.',
        jsonOutput: jsonOutput,
      );
    }
  }

  // --- Utility Helpers ---

  int _mapPreflightExitCode(LocalInferencePreflightResult result) {
    if (result.isReady) return 0;
    switch (result.failureReason) {
      case LocalInferencePreflightFailure.runtimeNotConfigured:
      case LocalInferencePreflightFailure.runtimeMissing:
      case LocalInferencePreflightFailure.runtimeInvalid:
      case LocalInferencePreflightFailure.runtimeStartupFailed:
      case LocalInferencePreflightFailure.portUnavailable:
        return 4;
      case LocalInferencePreflightFailure.actorNotConfigured:
      case LocalInferencePreflightFailure.evaluatorNotConfigured:
      case LocalInferencePreflightFailure.managedInstallationUnavailable:
      case LocalInferencePreflightFailure.externalModelMissing:
      case LocalInferencePreflightFailure.externalModelUnreadable:
      case LocalInferencePreflightFailure.modelLoadFailed:
        return 5;
      case null:
        return 1;
    }
  }

  Map<String, dynamic> _referenceToJson(ConfiguredModelReference ref) {
    if (ref is ManagedModelReference) {
      return {
        'kind': 'managed',
        'installationId': ref.installationId,
      };
    } else if (ref is ExternalModelReference) {
      return {
        'kind': 'external',
        'absolutePath': ref.absolutePath,
      };
    }
    return {'kind': 'unknown'};
  }

  String _referenceToString(ConfiguredModelReference ref) {
    if (ref is ManagedModelReference) {
      return 'Managed [${ref.installationId}]';
    } else if (ref is ExternalModelReference) {
      return 'External [${ref.absolutePath}]';
    }
    return 'Sconosciuto';
  }

  CliExecutionResult _errorResult({
    required int exitCode,
    required String code,
    required String message,
    required bool jsonOutput,
  }) {
    if (jsonOutput) {
      return CliExecutionResult(
        exitCode: exitCode,
        outputText: jsonEncode({
          'ok': false,
          'code': code,
          'message': message,
        }),
      );
    }
    return CliExecutionResult(
      exitCode: exitCode,
      outputText: 'ERRORE ($code): $message',
    );
  }
}
