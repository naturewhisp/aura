import 'dart:convert';
import 'dart:io';

import 'package:aura_core/aura_core.dart';

void main(List<String> args) {
  String? replayPath;
  int minTurns = 10;
  String? requirePlatform = 'macos';
  String? requireArch = 'arm64';
  bool quiet = false;

  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '--replay' && i + 1 < args.length) {
      replayPath = args[++i];
    } else if (arg.startsWith('--replay=')) {
      replayPath = arg.substring('--replay='.length);
    } else if (arg == '--min-turns' && i + 1 < args.length) {
      minTurns = int.tryParse(args[++i]) ?? minTurns;
    } else if (arg == '--require-platform' && i + 1 < args.length) {
      requirePlatform = args[++i];
    } else if (arg == '--require-arch' && i + 1 < args.length) {
      requireArch = args[++i];
    } else if (arg == '--any-platform') {
      requirePlatform = null;
    } else if (arg == '--any-arch') {
      requireArch = null;
    } else if (arg == '--quiet') {
      quiet = true;
    } else if (arg == '--help' || arg == '-h') {
      _printUsage();
      exit(0);
    }
  }

  if (replayPath == null || replayPath.trim().isEmpty) {
    stderr.writeln(
        '[ERRORE] Argomento obbligatorio mancante: --replay <path/to/replay.json>');
    _printUsage();
    exit(1);
  }

  final file = File(replayPath);
  if (!file.existsSync()) {
    stderr.writeln('[ERRORE] File di replay non trovato: $replayPath');
    exit(1);
  }

  Map<String, dynamic> json;
  try {
    final raw = file.readAsStringSync();
    json = jsonDecode(raw) as Map<String, dynamic>;
  } catch (e) {
    stderr.writeln(
        '[FAIL-CLOSED] Errore di parsing JSON nel file $replayPath: $e');
    exit(1);
  }

  ReplayLogger logger;
  try {
    logger = ReplayLogger.fromJson(json);
  } catch (e) {
    stderr.writeln('[FAIL-CLOSED] Deserializzazione ReplayLogger fallita: $e');
    exit(1);
  }

  final sessionProv = logger.sessionProvenance;
  final validation = logger.validateProvenance();
  final failures = <String>[];

  if (sessionProv == null) {
    failures.add('sessionProvenance assente nella sessione di replay');
  } else {
    if (requirePlatform != null &&
        sessionProv.platform.toLowerCase() != requirePlatform.toLowerCase()) {
      failures.add(
          'Platform mismatch: atteso "$requirePlatform", rilevato "${sessionProv.platform}"');
    }
    if (requireArch != null &&
        sessionProv.architecture.toLowerCase() != requireArch.toLowerCase()) {
      failures.add(
          'Architecture mismatch: atteso "$requireArch", rilevato "${sessionProv.architecture}"');
    }
    if (sessionProv.datasetSource != DatasetSource.humanPlaytest) {
      failures.add(
          'DatasetSource non eleggibile: atteso "human_playtest", rilevato "${sessionProv.datasetSource.wireValue}"');
    }
    if (!validation.isLoraTrainingEligible) {
      for (final issue in validation.issues.where((i) =>
          i.severity == ProvenanceValidationSeverity.datasetDisqualifier)) {
        failures.add(
            'Disqualifier di provenance: [${issue.field}] ${issue.message}');
      }
    }
  }

  final turnCount = logger.entries.length;
  if (turnCount < minTurns) {
    failures.add(
        'Numero di turni insufficiente per la qualifica: $turnCount turni completati (minimo richiesto: $minTurns)');
  }

  int missingTurnProvCount = 0;
  double totalTokensPerSec = 0.0;
  int speedTurnCount = 0;
  int totalActorPromptTokens = 0;
  int totalActorCompletionTokens = 0;
  int totalActorLatencyMs = 0;

  for (final entry in logger.entries) {
    final tProv = entry.generationProvenance;
    if (tProv == null) {
      missingTurnProvCount++;
    } else {
      final pTokens = tProv.samplingParameters['prompt_tokens'] as num?;
      if (pTokens != null) totalActorPromptTokens += pTokens.toInt();
      final cTokens = tProv.samplingParameters['completion_tokens'] as num?;
      if (cTokens != null) totalActorCompletionTokens += cTokens.toInt();
      totalActorLatencyMs += tProv.latencyTotalMs;
      final tps =
          (tProv.samplingParameters['tokens_per_second'] as num?)?.toDouble();
      if (tps != null && tps > 0) {
        totalTokensPerSec += tps;
        speedTurnCount++;
      }
    }
  }

  if (missingTurnProvCount > 0) {
    failures.add(
        '$missingTurnProvCount/$turnCount turni sono privi di TurnGenerationProvenance');
  }

  final avgSpeed =
      speedTurnCount > 0 ? (totalTokensPerSec / speedTurnCount) : 0.0;

  if (!quiet) {
    stdout.writeln(
        '============================================================');
    stdout.writeln(
        ' A.U.R.A. Scientific Playtest Replay Validator (Fase 6.11.5)');
    stdout.writeln(
        '============================================================');
    stdout.writeln('File:                   $replayPath');
    stdout.writeln('Session ID:             ${logger.sessionId}');
    stdout.writeln(
        'Totale Turni:           $turnCount (Requisito: >= $minTurns)');
    if (sessionProv != null) {
      stdout.writeln(
          'Dataset Source:         ${sessionProv.datasetSource.wireValue}');
      stdout.writeln(
          'Tester Anonimo:         ${sessionProv.anonymizedTesterId ?? "N/A"}');
      stdout.writeln('Git Commit:             ${sessionProv.gitCommit}');
      stdout.writeln('Versione App:           ${sessionProv.appVersion}');
      stdout.writeln(
          'Piattaforma:            ${sessionProv.platform} (${sessionProv.osVersion})');
      stdout.writeln('Architettura:           ${sessionProv.architecture}');
      stdout.writeln('Hardware Class:         ${sessionProv.hardwareClass}');
      stdout.writeln(
          'Backend:                ${sessionProv.runtimeBackend} (${sessionProv.runtimeAcceleration})');
      stdout.writeln(
          'Modello Attore:         ${sessionProv.actorModelId} (${sessionProv.actorQuantization}, ctx: ${sessionProv.actorContextSize})');
      stdout.writeln(
          'Modello Valutatore:     ${sessionProv.evaluatorModelId} (${sessionProv.evaluatorQuantization}, ctx: ${sessionProv.evaluatorContextSize})');
    }
    stdout.writeln(
        '------------------------------------------------------------');
    stdout.writeln('Statistiche Prestazionali Attore:');
    stdout.writeln(
        '  Velocita Media:       ${avgSpeed.toStringAsFixed(2)} tok/s');
    stdout.writeln('  Latenza Totale Gen:   ${totalActorLatencyMs} ms');
    stdout.writeln('  Prompt Tokens:        $totalActorPromptTokens');
    stdout.writeln('  Completion Tokens:    $totalActorCompletionTokens');
    stdout.writeln(
        '------------------------------------------------------------');
    if (validation.issues.isNotEmpty) {
      stdout.writeln('Segnalazioni di Validazione:');
      for (final issue in validation.issues) {
        final prefix =
            issue.severity == ProvenanceValidationSeverity.datasetDisqualifier
                ? '[DISQUALIFIER]'
                : '[WARNING]';
        stdout.writeln('  $prefix [${issue.field}] ${issue.message}');
      }
      stdout.writeln(
          '------------------------------------------------------------');
    }

    if (failures.isEmpty) {
      stdout.writeln('Esito Qualifica:        [OK] PASS - PLAYTEST_VERIFIED');
      stdout.writeln('Eleggibilita LoRA:      CERTIFICATA');
      stdout.writeln(
          '============================================================');
    } else {
      stderr.writeln('Esito Qualifica:        [FAIL] FAIL - NON QUALIFICATO');
      stderr.writeln('Motivi del Rifiuto Scientifico:');
      for (final f in failures) {
        stderr.writeln('  - $f');
      }
      stderr.writeln(
          '============================================================');
    }
  }

  if (failures.isNotEmpty) {
    exit(1);
  }
}

void _printUsage() {
  stdout.writeln('''
Uso: dart run tool/replay/validate_playtest_replay.dart --replay <path/to/replay.json> [opzioni]

Opzioni:
  --replay <path>              Percorso assoluto o relativo al file di replay JSON (obbligatorio)
  --min-turns <n>              Numero minimo di turni richiesti per la qualifica (default: 10)
  --require-platform <name>    Nome piattaforma attesa (default: macos)
  --require-arch <name>        Architettura hardware attesa (default: arm64)
  --any-platform               Disabilita il vincolo sulla piattaforma
  --any-arch                   Disabilita il vincolo sull'architettura
  --quiet                      Sopprime l'output dettagliato (utile per script CI)
  --help, -h                   Mostra questo messaggio di aiuto
''');
}
