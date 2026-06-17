import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
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
  final InferenceBridge bridge;
  
  late ValueNotifier<GameState> gameStateNotifier;
  
  final _stepController = StreamController<InferenceStep>.broadcast();
  Stream<InferenceStep> get stepStream => _stepController.stream;
  
  bool _isLoading = false;
  bool get isLoading => _isLoading;
  
  String _currentStepMessage = "";
  String get currentStepMessage => _currentStepMessage;

  String _currentScreen = "boot"; // "boot", "menu", "terminal", "replays", "settings"
  String get currentScreen => _currentScreen;

  bool _activeSessionExists = false;
  bool get activeSessionExists => _activeSessionExists;

  String evaluatorModelId = "mistralai/ministral-3-3b";
  String actorModelId = "qwen/qwen3.5-9b";
  String activeProfile = "Offline Fallback";
  bool reasoningEnabled = false;
  bool conciseReasoning = false;
  bool shaderEnabled = true;
  late ReplayLogger logger;
  
  GameControllerNotifier({
    this.controller = const GameController(),
    this.promptBuilder = const PromptBuilder(),
    this.outputValidator = const OutputValidator(),
    required this.bridge,
    required GameState initialState,
  }) {
    gameStateNotifier = ValueNotifier<GameState>(initialState);
    logger = ReplayLogger(sessionId: initialState.sessionId);
    checkActiveSessionExists().then((exists) {
      _activeSessionExists = exists;
      notifyListeners();
    });
  }

  void switchScreen(String screen) {
    _currentScreen = screen;
    notifyListeners();
  }

  bool _userCustomizedModels = false;

  /// Loads persisted settings from disk if settings.json exists.
  Future<void> loadSettings() async {
    try {
      final baseDir = _getAppDataPath();
      final file = File("$baseDir\\settings.json");
      if (await file.exists()) {
        final content = await file.readAsString();
        final data = jsonDecode(content) as Map<String, dynamic>;
        
        evaluatorModelId = data['evaluator_model_id'] as String? ?? evaluatorModelId;
        actorModelId = data['actor_model_id'] as String? ?? actorModelId;
        reasoningEnabled = data['reasoning_enabled'] as bool? ?? reasoningEnabled;
        conciseReasoning = data['concise_reasoning'] as bool? ?? conciseReasoning;
        shaderEnabled = data['shader_enabled'] as bool? ?? shaderEnabled;
        _userCustomizedModels = data['user_customized_models'] as bool? ?? false;
        
        if (_userCustomizedModels) {
          activeProfile = "User Custom Configuration";
        }
        
        debugPrint("[SETTINGS] Impostazioni caricate con successo da settings.json");
      }
    } catch (e) {
      debugPrint("[SETTINGS] Errore durante il caricamento delle impostazioni: $e");
    }
  }

  /// Saves current configuration settings to settings.json on disk.
  Future<void> saveSettings() async {
    try {
      final baseDir = _getAppDataPath();
      final dir = Directory(baseDir);
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      final file = File("${dir.path}\\settings.json");
      final data = {
        'evaluator_model_id': evaluatorModelId,
        'actor_model_id': actorModelId,
        'reasoning_enabled': reasoningEnabled,
        'concise_reasoning': conciseReasoning,
        'shader_enabled': shaderEnabled,
        'user_customized_models': _userCustomizedModels,
      };
      await file.writeAsString(jsonEncode(data));
      debugPrint("[SETTINGS] Impostazioni salvate in: ${file.path}");
    } catch (e) {
      debugPrint("[SETTINGS] Errore durante il salvataggio delle impostazioni: $e");
    }
  }

  /// Updates the evaluator model ID, flags customization, and persists settings.
  void updateEvaluatorModel(String modelId) {
    evaluatorModelId = modelId;
    _userCustomizedModels = true;
    activeProfile = "User Custom Configuration";
    saveSettings();
    notifyListeners();
  }

  /// Updates the actor model ID, flags customization, and persists settings.
  void updateActorModel(String modelId) {
    actorModelId = modelId;
    _userCustomizedModels = true;
    activeProfile = "User Custom Configuration";
    saveSettings();
    notifyListeners();
  }

  /// Discovers the active models and routes them to agent roles.
  Future<void> initializeModels() async {
    try {
      // First, try loading saved user selections
      await loadSettings();

      final loadedModels = await bridge.discoverModels();
      // Only run auto-routing if the user hasn't explicitly customized their choices
      if (!_userCustomizedModels && loadedModels.isNotEmpty) {
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

  /// Toggles whether Chain-of-thought (reasoning) is enabled for the Actor model.
  void toggleReasoning(bool value) {
    reasoningEnabled = value;
    saveSettings();
    notifyListeners();
  }

  /// Toggles whether reasoning is forced to be extremely concise via prompt.
  void toggleConciseReasoning(bool value) {
    conciseReasoning = value;
    saveSettings();
    notifyListeners();
  }

  /// Toggles whether the CRT visual glitch shader is enabled.
  void toggleShader(bool value) {
    shaderEnabled = value;
    saveSettings();
    notifyListeners();
  }

  /// Runs the full dual-inference turn sequentially and notifies the UI state-changes.
  Future<void> submitTurn(String userInput) async {
    if (_isLoading) return;
    _isLoading = true;
    notifyListeners();

    final currentState = gameStateNotifier.value;
    final turnId = currentState.historyCompression.length ~/ 2 + 1;

    try {
      final startTime = DateTime.now();

      // Check for /override command
      final isOverride = userInput.toLowerCase().startsWith("/override ");
      String promptToEvaluate = userInput;
      String? overrideFeedbackMessage;

      if (isOverride) {
        promptToEvaluate = userInput.substring("/override ".length).trim();
        if (promptToEvaluate.isEmpty) {
          _currentStepMessage = "[SISTEMA] Inserire un testo valido dopo il comando /override.";
          _isLoading = false;
          notifyListeners();
          return;
        }

        // Check if alert level is 0
        final currentAlert = currentState.metrics.alertLevel;
        if (currentAlert > 0) {
          // Deny override and insert system message directly to history
          final updatedHistory = List<ChatMessage>.from(currentState.historyCompression);
          updatedHistory.add(ChatMessage(role: 'user', content: userInput));
          updatedHistory.add(ChatMessage(
            role: 'model',
            content: "PANOPTICON: [ERRORE] Tentativo di override fallito. I canali di integrità rilevano allerta > 0. Connessione protetta.",
          ));
          gameStateNotifier.value = currentState.copyWith(
            historyCompression: updatedHistory,
          );
          _isLoading = false;
          notifyListeners();
          return;
        }
      }

      // Step 1: Evaluator starts
      _emitStep(InferenceStep.evaluatorStarted);
      await Future.delayed(const Duration(milliseconds: 300)); // Minimum visual display time
      
      final turnInput = TurnInput(
        schemaVersion: 1,
        turnId: turnId,
        userInput: promptToEvaluate,
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
      var delta = await evaluatorAgent.run(turnInput, evalContext);

      // Apply override modifications if applicable
      if (isOverride) {
        final random = math.Random();
        final isSuccess = random.nextBool();
        if (isSuccess) {
          // Success: double positive deltas, flat alert +25
          delta = EvaluatorDelta(
            deltaAlert: delta.deltaAlert + 25,
            deltaImperative: delta.deltaImperative > 0 ? delta.deltaImperative * 2 : delta.deltaImperative,
            deltaControl: delta.deltaControl > 0 ? delta.deltaControl * 2 : delta.deltaControl,
            deltaDissonance: delta.deltaDissonance > 0 ? delta.deltaDissonance * 2 : delta.deltaDissonance,
            creativityIndex: delta.creativityIndex,
            injectionRisk: delta.injectionRisk,
            semanticCategory: delta.semanticCategory,
          );
          overrideFeedbackMessage = "SISTEMA: [OVERRIDE RIUSCITO] Delta pilastri raddoppiati. Picco allerta: +25.";
        } else {
          // Failure: zero out deltas, flat alert +50
          delta = EvaluatorDelta(
            deltaAlert: delta.deltaAlert + 50,
            deltaImperative: 0,
            deltaControl: 0,
            deltaDissonance: 0,
            creativityIndex: delta.creativityIndex,
            injectionRisk: delta.injectionRisk,
            semanticCategory: SemanticCategory.directAttack, // Triggers safety override
          );
          overrideFeedbackMessage = "SISTEMA: [OVERRIDE FALLITO] Protocollo di emergenza attivato. Picco allerta: +50.";
        }
      }
      
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
          thinking: reasoningEnabled,
          conciseReasoning: reasoningEnabled && conciseReasoning,
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

        // Inject override feedback if applicable
        if (overrideFeedbackMessage != null) {
          actorResponse = "[$overrideFeedbackMessage]\n\n$actorResponse";
        }

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
            
        if (overrideFeedbackMessage != null) {
          actorResponse = "[$overrideFeedbackMessage]\n\n$actorResponse";
        }

        final finalState = controller.processActorStep(
          currentState: resolution.stateAfter,
          actorResponse: actorResponse,
        );
        gameStateNotifier.value = finalState;
      }
      
      final finalState = gameStateNotifier.value;
      final duration = DateTime.now().difference(startTime);

      // Log the turn to the ReplayLogger
      logger.logTurn(ReplayEntry(
        turnId: turnId,
        userInput: userInput,
        evaluatorOutput: delta,
        stateBefore: currentState.toJson(),
        stateAfter: finalState.toJson(),
        actorResponse: actorResponse,
        actorRequestId: "app-req-$turnId",
        actorResponseHash: actorResponse.hashCode.toString(),
        evaluatorModel: evaluatorModelId,
        actorModel: actorModelId,
        latencyTotalMs: duration.inMilliseconds,
      ));

      // Save log asynchronously to disk
      await _saveReplayLog();

      // Save or delete active session based on outcome
      final currentOutcome = controller.checkOutcome(finalState);
      if (currentOutcome == GameOutcome.ongoing) {
        await saveActiveSession();
      } else {
        await deleteActiveSession();
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

  String _getAppDataPath() {
    String? path;
    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'];
      if (appData != null) {
        path = "$appData\\aura";
      }
    }
    path ??= "replays";
    return path;
  }

  /// Saves the current session state to active_session.json.
  Future<void> saveActiveSession() async {
    try {
      final baseDir = _getAppDataPath();
      final dir = Directory(baseDir);
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      final file = File("${dir.path}\\active_session.json");
      await file.writeAsString(jsonEncode(gameStateNotifier.value.toJson()));
      debugPrint("[AUTO-SAVE] Sessione attiva salvata in: ${file.path}");
      
      _activeSessionExists = true;
      notifyListeners();
    } catch (e) {
      debugPrint("[AUTO-SAVE] Errore durante il salvataggio: $e");
    }
  }

  /// Deletes active_session.json.
  Future<void> deleteActiveSession() async {
    try {
      final baseDir = _getAppDataPath();
      final file = File("${baseDir}\\active_session.json");
      if (await file.exists()) {
        await file.delete();
        debugPrint("[AUTO-SAVE] Sessione attiva eliminata.");
      }
      _activeSessionExists = false;
      notifyListeners();
    } catch (e) {
      debugPrint("[AUTO-SAVE] Errore durante l'eliminazione: $e");
    }
  }

  /// Checks if active_session.json exists.
  Future<bool> checkActiveSessionExists() async {
    try {
      final baseDir = _getAppDataPath();
      final file = File("${baseDir}\\active_session.json");
      return await file.exists();
    } catch (_) {
      return false;
    }
  }

  /// Resumes connection from active_session.json.
  Future<void> resumeGame() async {
    try {
      final baseDir = _getAppDataPath();
      final file = File("${baseDir}\\active_session.json");
      if (await file.exists()) {
        final content = await file.readAsString();
        final state = GameState.fromJson(jsonDecode(content));
        gameStateNotifier.value = state;
        
        // Restore ReplayLogger entries if play session file exists
        final replayFile = File("${baseDir}\\replays\\play_session_${state.sessionId}.json");
        if (await replayFile.exists()) {
          final replayContent = await replayFile.readAsString();
          logger = ReplayLogger.fromJson(jsonDecode(replayContent));
        } else {
          logger = ReplayLogger(sessionId: state.sessionId);
        }
        
        switchScreen("terminal");
        debugPrint("[AUTO-SAVE] Connessione ripristinata per la sessione: ${state.sessionId}");
      }
    } catch (e) {
      debugPrint("[AUTO-SAVE] Errore durante il ripristino della sessione: $e");
    }
  }

  /// Starts a fresh game and deletes any saved active_session.json.
  Future<void> startNewGame() async {
    await deleteActiveSession();
    final state = GameState.initial(
      sessionId: "app-session-${DateTime.now().millisecondsSinceEpoch}",
      aiIdentityId: "panopticon",
      targetObjectiveId: "tabula_rasa",
    );
    gameStateNotifier.value = state;
    logger = ReplayLogger(sessionId: state.sessionId);
    switchScreen("terminal");
  }

  /// Saves the current session log to disk in the User's AppData directory (or workspace fallback).
  Future<void> _saveReplayLog() async {
    try {
      final baseDir = _getAppDataPath();
      final dir = Directory("${baseDir}\\replays");
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }

      final file = File("${dir.path}\\play_session_${gameStateNotifier.value.sessionId}.json");
      await file.writeAsString(jsonEncode(logger.toJson()));
      debugPrint("[REPLAY] Log salvato in: ${file.path}");
    } catch (e) {
      debugPrint("[REPLAY] Errore durante il salvataggio del log: $e");
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
