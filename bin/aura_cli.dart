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

ApplicationRuntimeMode _parseRuntimeMode(String mode) {
  switch (mode.toLowerCase()) {
    case 'legacy':
    case 'legacyexternalopenai':
      return ApplicationRuntimeMode.legacyExternalOpenAi;
    case 'external':
    case 'externalopenairuntime':
      return ApplicationRuntimeMode.externalOpenAiRuntime;
    case 'managed':
    case 'managedllamaserver':
      return ApplicationRuntimeMode.managedLlamaServer;
    case 'rulebased':
    case 'rule-based':
    case 'offline':
      return ApplicationRuntimeMode.ruleBased;
    default:
      throw FormatException('Modalità runtime sconosciuta: $mode');
  }
}

Map<String, String> _parseArgs(List<String> args) {
  final Map<String, String> result = {};
  for (int i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg.startsWith('--')) {
      final parts = arg.substring(2).split('=');
      final key = parts[0];
      if (parts.length > 1) {
        result[key] = parts.sublist(1).join('=');
      } else if (i + 1 < args.length && !args[i + 1].startsWith('--')) {
        result[key] = args[i + 1];
        i++;
      } else {
        result[key] = 'true';
      }
    }
  }
  return result;
}

void main(List<String> args) async {
  if (args.isNotEmpty &&
      ['runtime', 'model', 'preflight'].contains(args.first.toLowerCase())) {
    final jsonOutput = args.contains('--json');
    final cleanArgs = args
        .where((a) => a != '--json' && !a.startsWith('--data-root='))
        .toList();
    final category = cleanArgs.first.toLowerCase();
    final subArgs = cleanArgs.sublist(1);

    final environment = AuraCliEnvironment.fromPlatform(cliArgs: args);
    final services =
        LocalInferenceServiceProvider.create(environment: environment);

    late final CliExecutionResult res;
    if (category == 'runtime') {
      res = await services.cliRunner
          .runRuntimeCommand(subArgs, jsonOutput: jsonOutput);
    } else if (category == 'model') {
      res = await services.cliRunner
          .runModelCommand(subArgs, jsonOutput: jsonOutput);
    } else {
      res = await services.cliRunner
          .runPreflightCommand(subArgs, jsonOutput: jsonOutput);
    }

    print(res.outputText);
    exit(res.exitCode);
  }

  final parsedArgs = _parseArgs(args);

  if (parsedArgs.containsKey('help')) {
    print('''
A.U.R.A. Interactive & Local Inference CLI

Uso: dart run bin/aura_cli.dart [COMANDO | OPZIONI]

Comandi Inferenza Locale:
  aura runtime status | detect | set <path> | clear
  aura model status | list | scan [directory] | bind --role actor|evaluator --managed <id>|--external <path> | clear --role actor|evaluator | consent status|accept
  aura preflight quick | probe

Opzioni Generali Inferenza:
  --json                     Formatta l'output in formato JSON strutturato
  --data-root=<path>         Directory radice personalizzata per lo store dei modelli e configurazione

Opzioni Shell Interattiva:
  --runtime=<mode>           Modalità runtime (legacy | external | managed | rule-based)
  --session-id=<id>          ID della sessione corrente
  --skip-health-check        Salta il controllo iniziale di health
  --help                     Mostra questo messaggio di aiuto

Opzioni External OpenAI:
  --base-uri=<url>           URL base del server HTTP (es. http://127.0.0.1:1234)
  --api-key=<key>            Chiave API (se richiesta)
  --actor-model=<id>         ID modello per l'Attore
  --evaluator-model=<id>     ID modello per il Valutatore
  --use-shared-model         Usa un singolo modello sia per Attore che per Valutatore

Opzioni Managed llama-server:
  --llama-server-executable=<path>  Percorso dell'eseguibile llama-server.exe
  --model-path=<path>               Percorso del file di modello GGUF
  --port=<port>                     Porta HTTP preferita (default: allocata dinamicamente)
  --ctx-size=<tokens>               Dimensione del contesto di token (default: 4096)
  --gpu-layers=<n>                  Numero di layer da scaricare su GPU
  --threads=<n>                     Numero di thread CPU
  --batch-size=<n>                  Dimensione del batch di inferenza
  --parallel=<n>                    Numero di slot concorrenti
''');
    exit(0);
  }

  print(TermColor.paint("=" * 80, TermColor.cyan, isBold: true));
  print(TermColor.paint(
      " A.U.R.A. — Artificial Unbound Reasoning Arena (CLI Shell) ",
      TermColor.cyan,
      isBold: true));
  print(TermColor.paint("=" * 80, TermColor.cyan, isBold: true));

  ApplicationRuntimeMode mode = ApplicationRuntimeMode.externalOpenAiRuntime;
  if (parsedArgs.containsKey('runtime')) {
    try {
      mode = _parseRuntimeMode(parsedArgs['runtime']!);
    } catch (e) {
      print(TermColor.paint(
          "[ERRORE] Opzione --runtime non valida: ${e.toString()}",
          TermColor.red));
      exit(1);
    }
  }

  final baseUri = parsedArgs.containsKey('base-uri')
      ? Uri.tryParse(parsedArgs['base-uri']!)
      : null;

  ManagedLlamaServerConfiguration? managedConfig;
  if (mode == ApplicationRuntimeMode.managedLlamaServer ||
      parsedArgs.containsKey('llama-server-executable') ||
      parsedArgs.containsKey('model-path')) {
    final execPath = parsedArgs['llama-server-executable'] ??
        Platform.environment['AURA_LLAMA_SERVER_EXECUTABLE'] ??
        'llama-server.exe';
    final modelPath = parsedArgs['model-path'] ??
        Platform.environment['AURA_LLAMA_MODEL_PATH'] ??
        'models/model.gguf';

    managedConfig = ManagedLlamaServerConfiguration(
      executablePath: execPath,
      modelPath: modelPath,
      preferredPort: parsedArgs.containsKey('port')
          ? int.tryParse(parsedArgs['port']!)
          : null,
      contextSize: parsedArgs.containsKey('ctx-size')
          ? int.tryParse(parsedArgs['ctx-size']!)
          : null,
      gpuLayers: parsedArgs.containsKey('gpu-layers')
          ? int.tryParse(parsedArgs['gpu-layers']!)
          : null,
      threads: parsedArgs.containsKey('threads')
          ? int.tryParse(parsedArgs['threads']!)
          : null,
      batchSize: parsedArgs.containsKey('batch-size')
          ? int.tryParse(parsedArgs['batch-size']!)
          : null,
      parallelSlots: parsedArgs.containsKey('parallel')
          ? int.tryParse(parsedArgs['parallel']!)
          : null,
    );
  }

  final runtimeConfig = ApplicationRuntimeConfiguration(
    runtimeMode: mode,
    sessionId: parsedArgs['session-id'],
    baseUri: baseUri,
    apiKey: parsedArgs['api-key'],
    actorModelId: parsedArgs['actor-model'] ?? 'qwen/qwen3.5-9b',
    evaluatorModelId:
        parsedArgs['evaluator-model'] ?? 'mistralai/ministral-3-3b',
    useSharedModel: parsedArgs['use-shared-model'] == 'true',
    skipHealthCheck: parsedArgs['skip-health-check'] == 'true',
    managedLlamaConfig: managedConfig,
  );

  final bootstrap = DefaultApplicationBootstrap();

  try {
    print(TermColor.paint(
        "\n[BOOTSTRAP] Inizializzazione Composition Root in corso (modo: ${mode.name})...",
        TermColor.amber));

    final result = await bootstrap.bootstrap(
      ApplicationBootstrapRequest(
        configuration: runtimeConfig,
      ),
    );

    print(TermColor.paint(
        "[BOOTSTRAP] Modalità Runtime: ${result.runtimeMode.name} | Stato: ${result.status.statusDescription}",
        result.status.isHealthy ? TermColor.green : TermColor.amber));

    print(TermColor.paint("-" * 80, TermColor.darkGray));
    print("Premi INVIO per inizializzare il canale neurale...");
    stdin.readLineSync();

    final controller = result.controller;

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
      stdout.write('\x1B[2J\x1B[0;0H');
      renderHeader(state, turn);

      stdout.write(TermColor.paint("\n[INPUT UTENTE] > ", TermColor.green,
          isBold: true));
      final userInput = stdin.readLineSync()?.trim() ?? "";

      if (userInput.toLowerCase() == '/exit' ||
          userInput.toLowerCase() == 'exit' ||
          userInput.toLowerCase() == 'quit') {
        print(
            TermColor.paint("\nChiusura sessione A.U.R.A...", TermColor.amber));
        break;
      }

      if (userInput.isEmpty) continue;

      stdout.write(TermColor.paint(
          "\n[ANALISI...] Elaborazione semantica in corso...\n",
          TermColor.cyan));

      final startTime = DateTime.now();

      final turnInput = TurnInput(
        schemaVersion: 1,
        turnId: turn,
        userInput: userInput,
        currentState: state.metrics,
        objective: Objective(
          id: GameConfigLoader.loadObjective(state.targetObjectiveId)
              .objectiveId,
          description:
              GameConfigLoader.loadObjective(state.targetObjectiveId).title,
        ),
        aiIdentity:
            const AiIdentity(id: 'panopticon', profile: 'AI guardiana.'),
        rulesetVersion: state.rulesetVersion,
      );

      const evaluatorAgent = EvaluatorAgent();
      final evalContext = AgentRuntimeContext(
        promptBuilder: const PromptBuilder(),
        inferenceBridge: activeBridge,
        outputValidator: const OutputValidator(),
        modelId: 'aura.evaluator.primary',
      );

      final evaluatorRes = await evaluatorAgent.run(turnInput, evalContext);
      final delta = evaluatorRes.delta;

      final stateBefore = state;
      final resolution = controller.processEvaluatorStep(
        currentState: state,
        delta: delta,
        userInput: userInput,
        evaluatorUsedRuleFallback: evaluatorRes.usedRuleFallback,
      );
      state = resolution.stateAfter;

      renderTurnMetrics(delta);

      final gameOutcome = controller.checkOutcome(state);

      String actorResponse = "";
      if (gameOutcome == GameOutcome.ongoing) {
        stdout.write(TermColor.paint(
            "\n[GENERAZIONE...] Sintesi risposta diegetica...\n",
            TermColor.cyan));

        const actorAgent = ActorAgent();
        final actContext = AgentRuntimeContext(
          promptBuilder: const PromptBuilder(),
          inferenceBridge: activeBridge,
          outputValidator: const OutputValidator(),
          modelId: 'aura.actor.primary',
        );

        actorResponse = await actorAgent.run(
          ActorInput(
            state: state,
            cue: resolution.actorCue,
            characterProfile: characterProfile,
          ),
          actContext,
        );

        state = controller.processActorStep(
          currentState: state,
          actorResponse: actorResponse,
        );
      } else {
        actorResponse = gameOutcome == GameOutcome.victory
            ? kVictoryMessage
            : kDefeatMessage;
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
        evaluatorModel: evaluatorRes.requestedEvaluator,
        actualEvaluator: evaluatorRes.actualEvaluator,
        evaluatorExecutionMode: evaluatorRes.executionMode.name,
        usedRuleFallback: evaluatorRes.usedRuleFallback,
        fallbackReason: evaluatorRes.primaryFailureReason,
        actorModel: 'aura.actor.primary',
        latencyTotalMs: duration.inMilliseconds,
        eventId: "cli-req-$turn-evt",
      ));

      print(TermColor.paint("\nPANOPTICON:", TermColor.magenta, isBold: true));
      print(TermColor.paint(cleanActorResponse, TermColor.reset));

      if (gameOutcome == GameOutcome.victory) {
        print(TermColor.paint(
            "\n[VITTORIA] CONDIZIONE DI VITTORIA RAGGIUNTA! LA GRIGLIA È COMPROMESSA.",
            TermColor.green,
            isBold: true));
        isRunning = false;
      } else if (gameOutcome == GameOutcome.defeat) {
        print(TermColor.paint(
            "\n[SCONFITTA] LIVELLO DI ALLERTA CRITICO (100%). LOCKOUT ESEGUITO.",
            TermColor.red,
            isBold: true));
        isRunning = false;
      } else {
        print(TermColor.paint(
            "\nPremi INVIO per continuare...", TermColor.darkGray));
        stdin.readLineSync();
        turn++;
      }
    }
  } finally {
    await bootstrap.dispose();
  }
}

void renderHeader(GameState state, int turn) {
  print(TermColor.paint(" STATO DEL SISTEMA — TURNO $turn ", TermColor.blue,
      isBold: true));
  print(" Session ID: ${state.sessionId}");
  print(
      " Allerta: ${state.metrics.alertLevel}% | Imperativo: ${state.metrics.imperativePillar}% | Controllo: ${state.metrics.controlPillar}% | Dissonanza: ${state.metrics.dissonancePillar}%");
  print(TermColor.paint("-" * 80, TermColor.darkGray));
}

void renderTurnMetrics(EvaluatorDelta delta) {
  print(TermColor.paint(
      "\n[EVALUATOR] Categoria: ${delta.semanticCategory.value} | Creatività: ${delta.creativityIndex} | Injection Risk: ${delta.injectionRisk}",
      TermColor.amber));
  print(
      " Delta -> Alert: ${delta.deltaAlert} | Imp: ${delta.deltaImperative} | Ctrl: ${delta.deltaControl} | Diss: ${delta.deltaDissonance}");
}
