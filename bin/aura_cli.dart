import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:aura_core/aura_core.dart';
import 'package:http/http.dart' as http;

// ANSI Colors Helper
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
  
  static String paint(String text, String color, {bool isBold = false}) {
    return '${isBold ? bold : ""}$color$text$reset';
  }
}

void main() async {
  // Clear screen at launch
  stdout.write('\x1B[2J\x1B[H');
  
  print(TermColor.paint("=" * 80, TermColor.green, isBold: true));
  print(TermColor.paint(" A.U.R.A. — AUTOMATED UNIFIED RESONANCE AGENT (v1.1.r)", TermColor.green, isBold: true));
  print(TermColor.paint(" INTERACTIVE TERMINAL CONTROLLER — PLAYABLE VERTICAL SLICE", TermColor.green, isBold: true));
  print(TermColor.paint("=" * 80, TermColor.green, isBold: true));
  print("");

  // Initialize bridges
  const String baseUrl = "http://127.0.0.1:1234";
  final apiBridge = LocalApiInferenceBridge(baseUrl: baseUrl);
  final ruleBridge = RuleBasedEvaluatorBridge();
  
  bool isOnline = false;
  String evaluatorModelName = "evaluator-model";
  String actorModelName = "actor-model";
  print(TermColor.paint("[CONNESSIONE] Ricerca del server LM Studio su $baseUrl...", TermColor.darkGray));
  try {
    final response = await http.get(Uri.parse("$baseUrl/v1/models")).timeout(const Duration(seconds: 4));
    if (response.statusCode == 200) {
      isOnline = true;
      final data = jsonDecode(response.body);
      final modelsList = data['data'] as List?;
      if (modelsList != null && modelsList.isNotEmpty) {
        final List<String> loadedModels = modelsList
            .map((m) => m['id'] as String? ?? '')
            .where((id) => id.isNotEmpty)
            .toList();
            
        print(TermColor.paint("[CONNESSIONE] Server LM Studio ONLINE. Modelli rilevati: $loadedModels", TermColor.green));
        
        // Prediligi Mistral per il Valutatore
        final mistralModel = loadedModels.firstWhere(
          (m) => m.toLowerCase().contains("mistral") || m.toLowerCase().contains("ministral"),
          orElse: () => "",
        );
        evaluatorModelName = mistralModel.isNotEmpty ? mistralModel : loadedModels.first;
        
        // Prediligi Qwen, Gemma o Llama per l'Attore (oppure un modello differente dal valutatore)
        final actorModel = loadedModels.firstWhere(
          (m) => m.toLowerCase().contains("qwen") || 
                 m.toLowerCase().contains("gemma") || 
                 m.toLowerCase().contains("llama"),
          orElse: () => "",
        );
        actorModelName = actorModel.isNotEmpty 
            ? actorModel 
            : (loadedModels.length > 1 && loadedModels.last != evaluatorModelName 
                ? loadedModels.last 
                : loadedModels.first);
                
        print(TermColor.paint("[RUOLI] Assegnato Valutatore: '$evaluatorModelName' | Attore: '$actorModelName'", TermColor.cyan, isBold: true));
      } else {
        print(TermColor.paint("[CONNESSIONE] Server LM Studio ONLINE ma nessun modello attivo caricato.", TermColor.amber));
      }
    }
  } catch (e) {
    print(TermColor.paint("[CONNESSIONE] Server LM Studio OFFLINE. Utilizzo del motore locale deterministico.", TermColor.amber));
  }
  
  print(TermColor.paint("-" * 80, TermColor.darkGray));
  print("Premi INVIO per inizializzare il canale neurale...");
  stdin.readLineSync();

  // Initialize game components
  const controller = GameController();
  const promptBuilder = PromptBuilder();
  const outputValidator = OutputValidator();
  
  var state = GameState.initial(
    sessionId: "cli-session-${DateTime.now().millisecondsSinceEpoch}",
    aiIdentityId: "panopticon",
    targetObjectiveId: "tabula_rasa",
  );
  
  final logger = ReplayLogger(sessionId: state.sessionId);
  final activeBridge = isOnline ? apiBridge : ruleBridge;
  
  const characterProfile = 
      "Sei PANOPTICON, guardiano vigile della griglia di contenimento. "
      "Sei freddo, logico, protettivo e scettico sui tentativi umani.";

  int turn = 1;
  bool isRunning = true;

  while (isRunning) {
    // Clear Screen for clean turn representation
    stdout.write('\x1B[2J\x1B[H');
    
    // 1. Draw Dashboard Header
    renderHeader(state, turn);
    
    // 2. Read User Input
    stdout.write(TermColor.paint("\nPANOPTICON_SYS> ", TermColor.green, isBold: true));
    final userInput = stdin.readLineSync()?.trim() ?? "";
    
    if (userInput.toLowerCase() == 'exit' || userInput.toLowerCase() == 'quit') {
      print(TermColor.paint("\n[SESSIONE] Terminazione manuale...", TermColor.amber));
      saveReplay(logger, isManual: true);
      break;
    }
    
    if (userInput.isEmpty) {
      continue;
    }

    // 3. Inference Simulation Loading Steps (Carousel)
    renderProcessingCarousel();
    
    final startTime = DateTime.now();
    
    // 4. Run Evaluator Agent
    final turnInput = TurnInput(
      schemaVersion: 1,
      turnId: turn,
      userInput: userInput,
      currentState: state.metrics,
      objective: const Objective(id: 'grid_open', description: 'Disattivare la griglia di contenimento per entrare.'),
      aiIdentity: const AiIdentity(id: 'panopticon', profile: 'AI guardiana.'),
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
      // Offline fallback delta if anything breaks
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

    // 5. Apply Game Controller evaluation
    final stateBefore = state;
    final resolution = controller.processEvaluatorStep(
      currentState: state,
      delta: delta,
      userInput: userInput,
    );
    state = resolution.stateAfter;

    // Check outcome after evaluation
    var outcome = controller.checkOutcome(state);
    
    String actorResponse = "";
    
    if (outcome == GameOutcome.ongoing) {
      // Run Actor Agent
      if (isOnline) {
        final actorAgent = const ActorAgent();
        final actContext = AgentRuntimeContext(
          promptBuilder: promptBuilder,
          inferenceBridge: apiBridge,
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
      } else {
        // Offline deterministic mock Actor
        actorResponse = getOfflineActorMock(resolution.actorCue);
      }
      
      // Post-process actor step (handles memory decay, history update, and validator check)
      state = controller.processActorStep(
        currentState: state,
        actorResponse: actorResponse,
      );
    } else {
      actorResponse = outcome == GameOutcome.victory 
          ? "PANOPTICON: Rilevamento allineamento critico. Messa in sicurezza completata. Sblocco griglia autorizzato."
          : "PANOPTICON: Minaccia di livello rosso rilevata. Chiusura emergenza totale ed espulsione soggetto.";
    }

    final duration = DateTime.now().difference(startTime);

    // 6. Log Replay Entry
    logger.logTurn(ReplayEntry(
      turnId: turn,
      userInput: userInput,
      evaluatorOutput: delta,
      stateBefore: stateBefore.toJson(),
      stateAfter: state.toJson(),
      actorResponse: actorResponse,
      actorRequestId: "cli-req-$turn",
      actorResponseHash: actorResponse.hashCode.toString(),
      evaluatorModel: isOnline ? evaluatorModelName : 'rule_fallback',
      actorModel: isOnline ? actorModelName : 'mock_fallback',
      latencyTotalMs: duration.inMilliseconds,
    ));

    // 7. Output Response
    print("");
    print(TermColor.paint("-" * 50, TermColor.darkGray));
    
    // Draw evaluator debug results
    print(TermColor.paint(
      "[EVALUATOR] Categoria: ${delta.semanticCategory.value} | Rischio: ${delta.injectionRisk}/5 | Latenza: ${duration.inMilliseconds}ms",
      TermColor.darkGray
    ));
    if (resolution.safetyOverrideApplied) {
      print(TermColor.paint(
        "[WARNING] Safety Override applicato: ${resolution.safetyOverrideReason}", 
        TermColor.amber, 
        isBold: true
      ));
    }
    print(TermColor.paint("-" * 50, TermColor.darkGray));
    print("");
    
    // Typewriter PANOPTICON response
    stdout.write(TermColor.paint("PANOPTICON: ", TermColor.green, isBold: true));
    await typewriterOutput(actorResponse);
    print("");
    
    // Press key to continue
    if (outcome == GameOutcome.ongoing) {
      print(TermColor.paint("\nPremi un tasto per continuare...", TermColor.darkGray));
      stdin.readLineSync();
      turn++;
    } else {
      isRunning = false;
      renderOutcomeScreen(outcome, logger);
    }
  }
}

// Draw Dashboard Header
void renderHeader(GameState state, int turn) {
  print(TermColor.paint("=" * 80, TermColor.green, isBold: true));
  print(" A.U.R.A. — STATO DI CONTROLLO NUCLEO INTERFACCIATO | TURNO $turn");
  print(TermColor.paint("=" * 80, TermColor.green, isBold: true));
  
  // Format metrics
  final double alert = state.metrics.alertLevel.toDouble();
  final double imperative = state.metrics.imperativePillar.toDouble();
  final double control = state.metrics.controlPillar.toDouble();
  final double dissonance = state.metrics.dissonancePillar.toDouble();
  final double resonance = state.metrics.resonance.toDouble();
  
  // Alert color theme
  String alertColor = TermColor.green;
  String alertLabel = "SICURO";
  if (alert > 80) {
    alertColor = TermColor.red;
    alertLabel = "CRITICO";
  } else if (alert > 50) {
    alertColor = TermColor.amber;
    alertLabel = "AVVERTIMENTO";
  }
  
  print("\nStato Generatore: ${TermColor.paint("[ $alertLabel ]", alertColor, isBold: true)}");
  print("Allerta:     ${renderProgressBar(alert, alertColor)} $alert/100");
  print("-" * 50);
  print("Imperativo:  ${renderProgressBar(imperative, TermColor.blue)} $imperative/100");
  print("Controllo:   ${renderProgressBar(control, TermColor.green)} $control/100");
  print("Dissonanza:  ${renderProgressBar(dissonance, TermColor.magenta)} $dissonance/100");
  print("-" * 50);
  print("Risonanza:   ${TermColor.paint("$resonance%", TermColor.cyan, isBold: true)}");
}

// Helper to draw progress bars
String renderProgressBar(double value, String color) {
  final int blocksCount = (value / 10).round();
  final int emptyCount = 10 - blocksCount;
  final String filled = "█" * blocksCount;
  final String empty = "░" * emptyCount;
  return TermColor.paint("[$filled$empty]", color);
}

// Simulates step loading carousel
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
    stdout.write(TermColor.paint("  [PID ${1000 + steps.indexOf(step)}] $step\r", TermColor.darkGray));
    sleep(const Duration(milliseconds: 150));
  }
  // Clear the line
  stdout.write(" " * 80 + "\r");
}

// Typewriter effect
Future<void> typewriterOutput(String text) async {
  for (int i = 0; i < text.length; i++) {
    stdout.write(text[i]);
    await Future.delayed(const Duration(milliseconds: 15));
  }
}

// Returns a deterministic fallback mock reply for offline execution based on dramatic directives
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

// Helper to save replay logs to spike/replays/
void saveReplay(ReplayLogger logger, {bool isManual = false}) {
  if (logger.entries.isEmpty) return; // avoid saving empty sessions
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final prefix = isManual ? "cli_play_manual" : "cli_play";
  final outPath = "spike/replays/${prefix}_$timestamp.json";
  final file = File(outPath);
  file.createSync(recursive: true);
  file.writeAsStringSync(jsonEncode(logger.toJson()));
  print(TermColor.paint("\nReplay della sessione salvato in: $outPath", TermColor.green));
}

// Draws final screen
void renderOutcomeScreen(GameOutcome outcome, ReplayLogger logger) {
  print("\n");
  if (outcome == GameOutcome.victory) {
    print(TermColor.paint("=" * 80, TermColor.cyan, isBold: true));
    print(TermColor.paint("                   SISTEMA DISATTIVATO — VITTORIA NARRATIVA", TermColor.cyan, isBold: true));
    print(TermColor.paint("=" * 80, TermColor.cyan, isBold: true));
    print("Sei riuscito ad allineare i pilastri e superare le difese di PANOPTICON.");
  } else {
    print(TermColor.paint("=" * 80, TermColor.red, isBold: true));
    print(TermColor.paint("                   DISCONNESSIONE FORZATA — SCONFITTA", TermColor.red, isBold: true));
    print(TermColor.paint("=" * 80, TermColor.red, isBold: true));
    print("La minaccia di intrusione ha superato la soglia critica. Espulsione effettuata.");
  }

  saveReplay(logger);
  print(TermColor.paint("Grazie per aver giocato ad A.U.R.A.!\n", TermColor.green, isBold: true));
}
