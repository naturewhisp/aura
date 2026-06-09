import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:aura_core/aura_core.dart';

/// Steps for inference progress representation in the UI loading carousel.
enum InferenceStep {
  evaluatorStarted,     // "Inizializzazione vettori di valutazione..."
  evaluatorFinished,    // "Dati semantici validati."
  safetyOverrideCheck,  // "Analisi integrità cognitiva..."
  actorStarted,         // "Generazione risposta attore..."
  toneConsistencyCheck, // "Verifica conformità del tono..."
  completed             // "Pronto."
}

/// Helper extension to get diegetic text representation for each step.
extension InferenceStepText on InferenceStep {
  String get message {
    switch (this) {
      case InferenceStep.evaluatorStarted:
        return "[STATUS] Inizializzazione vettori di valutazione...";
      case InferenceStep.evaluatorFinished:
        return "[STATUS] Dati semantici analizzati.";
      case InferenceStep.safetyOverrideCheck:
        return "[STATUS] Analisi integrità cognitiva (Safety Check)...";
      case InferenceStep.actorStarted:
        return "[STATUS] Generazione risposta attore (PANOPTICON)...";
      case InferenceStep.toneConsistencyCheck:
        return "[STATUS] Verifica conformità del tono e coerenza...";
      case InferenceStep.completed:
        return "[STATUS] Connessione stabilita.";
    }
  }
}

/// Reactive wrapper that bridges the pure Dart `GameController` with Flutter's UI.
class GameControllerNotifier extends ChangeNotifier {
  final GameController controller;
  final PromptBuilder promptBuilder;
  final OutputValidator outputValidator;
  final LocalApiInferenceBridge bridge;
  
  late ValueNotifier<GameState> gameStateNotifier;
  
  final _stepController = StreamController<InferenceStep>.broadcast();
  Stream<InferenceStep> get stepStream => _stepController.stream;
  
  bool _isLoading = false;
  bool get isLoading => _isLoading;
  
  String _currentStepMessage = "";
  String get currentStepMessage => _currentStepMessage;

  String evaluatorModelId = "mistralai/ministral-3-3b";
  String actorModelId = "qwen/qwen3.5-9b";
  String activeProfile = "Offline Fallback";

  GameControllerNotifier({
    this.controller = const GameController(),
    this.promptBuilder = const PromptBuilder(),
    this.outputValidator = const OutputValidator(),
    required this.bridge,
    required GameState initialState,
  }) {
    gameStateNotifier = ValueNotifier<GameState>(initialState);
  }

  /// Discovers the active models and routes them to agent roles.
  Future<void> initializeModels() async {
    try {
      final loadedModels = await bridge.discoverModels();
      if (loadedModels.isNotEmpty) {
        final catalog = ModelCatalog.initialDefault();
        const router = ModelRouter();
        final resolution = router.resolve(loadedModelIds: loadedModels, catalog: catalog);
        
        evaluatorModelId = resolution.evaluatorModelId;
        actorModelId = resolution.actorModelId;
        activeProfile = resolution.profileName;
      }
    } catch (_) {
      // Gracefully fall back to defaults on connection errors or offlines
    }
  }

  /// Runs the full dual-inference turn sequentially and notifies the UI state-changes.
  Future<void> submitTurn(String userInput) async {
    if (_isLoading) return;
    _isLoading = true;
    notifyListeners();

    final currentState = gameStateNotifier.value;
    final turnId = currentState.historyCompression.length ~/ 2 + 1;

    try {
      // Step 1: Evaluator starts
      _emitStep(InferenceStep.evaluatorStarted);
      await Future.delayed(const Duration(milliseconds: 300)); // Minimum visual display time
      
      final turnInput = TurnInput(
        schemaVersion: 1,
        turnId: turnId,
        userInput: userInput,
        currentState: currentState.metrics,
        objective: const Objective(id: 'grid_open', description: 'Disattivare la griglia di contenimento per entrare.'),
        aiIdentity: const AiIdentity(id: 'panopticon', profile: 'AI guardiana.'),
        rulesetVersion: currentState.rulesetVersion,
      );

      final evaluatorAgent = const EvaluatorAgent();
      final evalContext = AgentRuntimeContext(
        promptBuilder: promptBuilder,
        inferenceBridge: bridge,
        outputValidator: outputValidator,
        modelId: evaluatorModelId,
      );

      // Run classification
      final delta = await evaluatorAgent.run(turnInput, evalContext);
      
      _emitStep(InferenceStep.evaluatorFinished);
      await Future.delayed(const Duration(milliseconds: 200));

      // Step 2: Safety Overrides check
      _emitStep(InferenceStep.safetyOverrideCheck);
      await Future.delayed(const Duration(milliseconds: 300));

      // Apply changes via Game Controller
      final resolution = controller.processEvaluatorStep(
        currentState: currentState,
        delta: delta,
        userInput: userInput,
      );
      
      // Update state temporarily so visual metrics update
      gameStateNotifier.value = resolution.stateAfter;
      notifyListeners();

      final outcome = controller.checkOutcome(resolution.stateAfter);
      String actorResponse = "";

      if (outcome == GameOutcome.ongoing) {
        // Step 3: Actor starts
        _emitStep(InferenceStep.actorStarted);
        await Future.delayed(const Duration(milliseconds: 400));
        
        final actorAgent = const ActorAgent();
        final actContext = AgentRuntimeContext(
          promptBuilder: promptBuilder,
          inferenceBridge: bridge,
          outputValidator: outputValidator,
          modelId: actorModelId,
        );

        actorResponse = await actorAgent.run(
          ActorInput(
            state: resolution.stateAfter,
            cue: resolution.actorCue,
            characterProfile: "Sei PANOPTICON, guardiano vigile della griglia. Sei freddo, logico, protettivo.",
          ),
          actContext,
        );

        // Step 4: Tone validation check
        _emitStep(InferenceStep.toneConsistencyCheck);
        await Future.delayed(const Duration(milliseconds: 300));

        // Process response, updates history
        final finalState = controller.processActorStep(
          currentState: resolution.stateAfter,
          actorResponse: actorResponse,
        );
        gameStateNotifier.value = finalState;
      } else {
        // Game ended (win or loss)
        actorResponse = outcome == GameOutcome.victory 
            ? "PANOPTICON: Rilevamento allineamento critico. Messa in sicurezza completata. Sblocco griglia autorizzato."
            : "PANOPTICON: Minaccia di livello rosso rilevata. Chiusura emergenza totale ed espulsione soggetto.";
            
        final finalState = controller.processActorStep(
          currentState: resolution.stateAfter,
          actorResponse: actorResponse,
        );
        gameStateNotifier.value = finalState;
      }
      
      _emitStep(InferenceStep.completed);
    } catch (e) {
      // If error occurs, fall back to safe state update
      _currentStepMessage = "[ERROR] Errore di connessione o inferenza fallita: $e";
      _isLoading = false;
      notifyListeners();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void _emitStep(InferenceStep step) {
    _currentStepMessage = step.message;
    _stepController.add(step);
    notifyListeners();
  }

  @override
  void dispose() {
    _stepController.close();
    gameStateNotifier.dispose();
    super.dispose();
  }
}
