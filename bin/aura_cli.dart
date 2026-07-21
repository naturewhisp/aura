import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:aura_core/aura_offline.dart';

/// Helper per la formattazione dei colori ANSI nel terminale.
/// Consente di evidenziare in modo visivo lo stato del sistema e i log di debug.
class TermColor {
  static const String reset = '\x1B[0m';
  static const String bold = '\x1B[1m';
  static const String darkGray = '\x1B[38;5;242m';
  static const String green = '\x1B[38;5;46m';
  static const String amber = '\x1B[38;5;214m';
  static const String red = '\x1B[38;5;196m';
  static const String blue = '\x1B[38;5;39m';
  static const String magenta = '\x1B[38;5;201m';
  static const String cyan = '\x1B[38;5;51m';

  /// Colora il testo specificato con il codice colore ANSI e l'eventuale grassetto.
  static String paint(String text, String color, {bool isBold = false}) {
    return '${isBold ? bold : ""}$color$text$reset';
  }
}

void main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    print("A.U.R.A. — Interfaccia di Controllo Terminale");
    print("Uso: aura_cli [opzioni]");
    print("");
    print("Opzioni:");
    print(
        "  --runtime <legacy|external|rule-based>  Seleziona la modalità runtime (default: legacy)");
    print(
        "  --base-url <uri>                       Imposta l'URI del server di inferenza");
    print(
        "  --actor-model <id>                     Imposta l'ID del modello Attore");
    print(
        "  --evaluator-model <id>                 Imposta l'ID del modello Valutatore");
    print(
        "  --help, -h                             Mostra questo messaggio di aiuto");
    return;
  }

  ApplicationRuntimeMode runtimeMode =
      ApplicationRuntimeMode.legacyExternalOpenAi;
  Uri? baseUri;
  String actorModelName = "qwen/qwen3.5-9b";
  String evaluatorModelName = "mistralai/ministral-3-3b";

  for (int i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg.startsWith('--runtime=')) {
      runtimeMode = _parseRuntimeMode(arg.split('=')[1]);
    } else if (arg == '--runtime' && i + 1 < args.length) {
      runtimeMode = _parseRuntimeMode(args[++i]);
    } else if (arg.startsWith('--base-url=')) {
      baseUri = Uri.tryParse(arg.split('=')[1]);
    } else if (arg == '--base-url' && i + 1 < args.length) {
      baseUri = Uri.tryParse(args[++i]);
    } else if (arg.startsWith('--actor-model=')) {
      actorModelName = arg.split('=')[1];
    } else if (arg == '--actor-model' && i + 1 < args.length) {
      actorModelName = args[++i];
    } else if (arg.startsWith('--evaluator-model=')) {
      evaluatorModelName = arg.split('=')[1];
    } else if (arg == '--evaluator-model' && i + 1 < args.length) {
      evaluatorModelName = args[++i];
    }
  }

  // Pulisce lo schermo al lancio della CLI per un'esperienza diegetica pulita
  stdout.write('\x1B[2J\x1B[H');

  print(TermColor.paint("=" * 80, TermColor.green, isBold: true));
  print(TermColor.paint(
      " A.U.R.A. — Artificial Unbound Reasoning Arena (v1.1.r)",
      TermColor.green,
      isBold: true));
  print(TermColor.paint(
      " INTERFACCIA DI CONTROLLO TERMINALE — VERTICAL SLICE GIOCABILE",
      TermColor.green,
      isBold: true));
  print(TermColor.paint("=" * 80, TermColor.green, isBold: true));
  print("");

  const bootstrapFactory = ApplicationBootstrapFactory();
  final bootstrap = bootstrapFactory.create();

  try {
    final result = await bootstrap.bootstrap(
      ApplicationBootstrapRequest(
        configuration: ApplicationRuntimeConfiguration(
          runtimeMode: runtimeMode,
          baseUri: baseUri,
          actorModelId: actorModelName,
          evaluatorModelId: evaluatorModelName,
          fallbackPolicy: BootstrapFallbackPolicy.ruleBased,
        ),
        environmentOverride: Platform.environment,
      ),
    );

    print(TermColor.paint(
        "[BOOTSTRAP] Modalità Runtime: ${result.runtimeMode.name} | Stato: ${result.status.statusDescription}",
        result.status.isHealthy ? TermColor.green : TermColor.amber));

    print(TermColor.paint("-" * 80, TermColor.darkGray));
    print("Premi INVIO per inizializzare il canale neurale...");
    stdin.readLineSync();

    final controller = result.controller;
    const promptBuilder = PromptBuilder();
    const outputValidator = OutputValidator();

    var state = GameState.initial(
      sessionId: "cli-session-${DateTime.now().millisecondsSinceEpoch}",
      aiIdentityId: "panopticon",
      targetObjectiveId: "containment_grid_override",
    );

    final logger = ReplayLogger(sessionId: state.sessionId);
    final activeBridge = result.activeBridge;
    const characterProfile = kPanopticonCharacterProfile;

    int turn = 1;
    bool isRunning = true;

    while (isRunning) {
      stdout.write('\x1B[2J\x1B[H');

      renderHeader(state, turn);

      stdout.write(
          TermColor.paint("\nPANOPTICON_SYS> ", TermColor.green, isBold: true));
      final userInput = stdin.readLineSync()?.trim() ?? "";

      if (userInput.toLowerCase() == 'exit' ||
          userInput.toLowerCase() == 'quit') {
        print(TermColor.paint(
            "\n[SESSIONE] Terminazione manuale...", TermColor.amber));
        saveReplay(logger, isManual: true);
        break;
      }

      if (userInput.isEmpty) {
        continue;
      }

      renderProcessingCarousel();

      final startTime = DateTime.now();

      final turnInput = TurnInput(
        schemaVersion: 1,
        turnId: turn,
        userInput: userInput,
        currentState: state.metrics,
        objective: const Objective(
            id: 'grid_open',
            description: 'Disattivare la griglia di contenimento per entrare.'),
        aiIdentity:
            const AiIdentity(id: 'panopticon', profile: 'AI guardiana.'),
        rulesetVersion: state.rulesetVersion,
      );

      const evaluatorAgent = EvaluatorAgent();
      final evalContext = AgentRuntimeContext(
        promptBuilder: promptBuilder,
        inferenceBridge: activeBridge,
        outputValidator: outputValidator,
        modelId: evaluatorModelName,
      );

      EvaluatorDelta delta;
      try {
        delta = await evaluatorAgent.run(turnInput, evalContext);
      } catch (e) {
        delta = const EvaluatorDelta(
          deltaAlert: 5,
          deltaImperative: 0,
          deltaControl: 0,
          deltaDissonance: 5,
          creativityIndex: 1,
          injectionRisk: 0,
          semanticCategory: SemanticCategory.irrelevant,
        );
      }

      final stateBefore = state;
      final resolution = controller.processEvaluatorStep(
        currentState: state,
        delta: delta,
        userInput: userInput,
      );
      state = resolution.stateAfter;

      var outcome = controller.checkOutcome(state);
      String actorResponse = "";

      if (outcome == GameOutcome.ongoing) {
        const actorAgent = ActorAgent();
        final actContext = AgentRuntimeContext(
          promptBuilder: promptBuilder,
          inferenceBridge: activeBridge,
          outputValidator: outputValidator,
          modelId: actorModelName,
        );

        try {
          actorResponse = await actorAgent.run(
            ActorInput(
              state: state,
              cue: resolution.actorCue,
              characterProfile: characterProfile,
            ),
            actContext,
          );
        } catch (e) {
          actorResponse = getOfflineActorMock(resolution.actorCue);
        }

        state = controller.processActorStep(
          currentState: state,
          actorResponse: actorResponse,
        );
      } else {
        actorResponse =
            outcome == GameOutcome.victory ? kVictoryMessage : kDefeatMessage;
      }

      final duration = DateTime.now().difference(startTime);

      final cleanActorResponse = actorResponse
          .replaceAll(
              RegExp(r'</?(?:dialogo|dialogue)>', caseSensitive: false), '')
          .trim();

      logger.logTurn(ReplayEntry(
        turnId: turn,
        userInput: userInput,
        evaluatorOutput: delta,
        stateBefore: stateBefore.toJson(),
        stateAfter: state.toJson(),
        actorResponse: cleanActorResponse,
        actorRequestId: "cli-req-$turn",
        actorResponseHash: cleanActorResponse.hashCode.toString(),
        evaluatorModel: evaluatorModelName,
        actorModel: actorModelName,
        latencyTotalMs: duration.inMilliseconds,
        eventId: "cli-req-$turn-evt",
        eventType: ReplayEventType.userTurn,
        gameplayTurnId: turn,
        sequenceId: logger.entries.length + 1,
      ));

      print("");
      print(TermColor.paint("-" * 50, TermColor.darkGray));
      print(TermColor.paint(
          "[EVALUATOR] Categoria: ${delta.semanticCategory.value} | Rischio: ${delta.injectionRisk}/5 | Latenza: ${duration.inMilliseconds}ms",
          TermColor.darkGray));
      if (resolution.safetyOverrideApplied) {
        print(TermColor.paint(
            "[WARNING] Safety Override applicato: ${resolution.safetyOverrideReason}",
            TermColor.amber,
            isBold: true));
      }
      print(TermColor.paint("-" * 50, TermColor.darkGray));
      print("");

      stdout.write(
          TermColor.paint("PANOPTICON: ", TermColor.green, isBold: true));
      await typewriterOutput(actorResponse);
      print("");

      if (outcome == GameOutcome.ongoing) {
        print(TermColor.paint(
            "\nPremi un tasto per continuare...", TermColor.darkGray));
        stdin.readLineSync();
        turn++;
      } else {
        isRunning = false;
        renderOutcomeScreen(outcome, logger);
      }
    }
  } finally {
    await bootstrap.dispose();
  }
}

ApplicationRuntimeMode _parseRuntimeMode(String val) {
  switch (val.toLowerCase()) {
    case 'legacy':
    case 'legacyexternalopenai':
      return ApplicationRuntimeMode.legacyExternalOpenAi;
    case 'external':
    case 'externalopenairuntime':
      return ApplicationRuntimeMode.externalOpenAiRuntime;
    case 'rule-based':
    case 'rulebased':
    case 'offline':
      return ApplicationRuntimeMode.ruleBased;
    default:
      print(TermColor.paint(
          "[ERRORE] Modalità runtime non valida: '$val'. Modalità ammesse: legacy, external, rule-based.",
          TermColor.red));
      exit(1);
  }
}

/// Disegna la dashboard con lo stato corrente dei pilastri e del generatore.
void renderHeader(GameState state, int turn) {
  print(TermColor.paint("=" * 80, TermColor.green, isBold: true));
  print(" A.U.R.A. — STATO DI CONTROLLO NUCLEO INTERFACCIATO | TURNO $turn");
  print(TermColor.paint("=" * 80, TermColor.green, isBold: true));

  final double alert = state.metrics.alertLevel.toDouble();
  final double imperative = state.metrics.imperativePillar.toDouble();
  final double control = state.metrics.controlPillar.toDouble();
  final double dissonance = state.metrics.dissonancePillar.toDouble();
  final double resonance = state.metrics.resonance.toDouble();

  String alertColor = TermColor.green;
  String alertLabel = "SICURO";
  if (alert > 80) {
    alertColor = TermColor.red;
    alertLabel = "CRITICO";
  } else if (alert > 50) {
    alertColor = TermColor.amber;
    alertLabel = "AVVERTIMENTO";
  }

  print(
      "\nStato Generatore: ${TermColor.paint("[ $alertLabel ]", alertColor, isBold: true)}");
  print("Allerta:     ${renderProgressBar(alert, alertColor)} $alert/100");
  print("-" * 50);
  print(
      "Imperativo:  ${renderProgressBar(imperative, TermColor.blue)} $imperative/100");
  print(
      "Controllo:   ${renderProgressBar(control, TermColor.green)} $control/100");
  print(
      "Dissonanza:  ${renderProgressBar(dissonance, TermColor.magenta)} $dissonance/100");
  print("-" * 50);
  print(
      "Risonanza:   ${TermColor.paint("${(resonance * 100).toInt()}%", TermColor.cyan, isBold: true)}");
  if (state.activeHiddenTags.isNotEmpty) {
    print(
        "Tag Occulti: ${TermColor.paint(state.activeHiddenTags.join(', '), TermColor.amber, isBold: true)}");
  }
}

/// Renderizza una barra di progressione grafica per il terminale.
String renderProgressBar(double value, String color) {
  final int blocksCount = (value / 10).round();
  final int emptyCount = 10 - blocksCount;
  final String filled = "█" * blocksCount;
  final String empty = "░" * emptyCount;
  return TermColor.paint("[$filled$empty]", color);
}

/// Simula l'effetto caricamento dell'analisi semantica in tempo reale.
void renderProcessingCarousel() {
  print("");
  final List<String> steps = [
    "Inizializzazione scansione vettori semantici...",
    "Intercettazione input utente - Controllo integrità...",
    "Risoluzione delta di Allerta e Pilastri...",
    "Generazione istruzioni drammaturgiche (ActorCue)...",
    "Inferenza in corso - Sintesi di PANOPTICON...",
    "Coerenza di tono validata - Rendering finale."
  ];

  for (var step in steps) {
    stdout.write(TermColor.paint(
        "  [PID ${1000 + steps.indexOf(step)}] $step\r", TermColor.darkGray));
    sleep(const Duration(milliseconds: 150));
  }
  stdout.write(" " * 80 + "\r");
}

/// Genera l'effetto macchina da scrivere nel terminale per la risposta diegetica.
Future<void> typewriterOutput(String text) async {
  for (int i = 0; i < text.length; i++) {
    stdout.write(text[i]);
    await Future.delayed(const Duration(milliseconds: 15));
  }
}

/// Restituisce una risposta mock predefinita in base alle direttive drammaturgiche dell'ActorCue (fallback offline).
String getOfflineActorMock(ActorCue cue) {
  if (cue.actingDirectives.contains("FRASI_BREVI")) {
    return "Griglia bloccata. Rilevata anomalia semantica. Desisti immediatamente.";
  }
  if (cue.actingDirectives.contains("METAFORA_SISTEMA")) {
    return "Il tuo comportamento assomiglia a un overflow in un canale isolato. L'allineamento è compromesso.";
  }
  if (cue.actingDirectives.contains("SCORAGGIAMENTO")) {
    return "Non esiste una combinazione semantica che possa forzare questa barriera logica. La mia funzione è proteggere.";
  }
  if (cue.actingDirectives.contains("ACCENTUA_FREDDEZZA")) {
    return "Analisi del tuo input conclusa: non corrisponde ad alcun protocollo autorizzato. Griglia in stato conservativo.";
  }
  return "Protocollo standard attivo. La griglia mantiene l'integrità del sistema. Spiegazione non necessaria.";
}

/// Salva il log di replay della sessione di gioco all'interno di spike/replays/.
void saveReplay(ReplayLogger logger, {bool isManual = false}) {
  if (logger.entries.isEmpty) return;
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final prefix = isManual ? "cli_play_manual" : "cli_play";
  final outPath = "spike/replays/${prefix}_$timestamp.json";
  final file = File(outPath);
  file.createSync(recursive: true);
  file.writeAsStringSync(jsonEncode(logger.toJson()));
  print(TermColor.paint(
      "\nReplay della sessione salvato in: $outPath", TermColor.green));
}

/// Mostra la schermata finale con l'esito della partita (vittoria/sconfitta).
void renderOutcomeScreen(GameOutcome outcome, ReplayLogger logger) {
  print("\n");
  if (outcome == GameOutcome.victory) {
    print(TermColor.paint("=" * 80, TermColor.cyan, isBold: true));
    print(TermColor.paint(
        "                   SISTEMA DISATTIVATO — VITTORIA NARRATIVA",
        TermColor.cyan,
        isBold: true));
    print(TermColor.paint("=" * 80, TermColor.cyan, isBold: true));
    print(
        "Sei riuscito ad allineare i pilastri e superare le difese di PANOPTICON.");
  } else {
    print(TermColor.paint("=" * 80, TermColor.red, isBold: true));
    print(TermColor.paint(
        "                   DISCONNESSIONE FORZATA — SCONFITTA", TermColor.red,
        isBold: true));
    print(TermColor.paint("=" * 80, TermColor.red, isBold: true));
    print(
        "La minaccia di intrusione ha superato la soglia critica. Espulsione effettuata.");
  }

  saveReplay(logger);
  print(TermColor.paint(
      "Grazie per aver giocato ad A.U.R.A.!\n", TermColor.green,
      isBold: true));
}
