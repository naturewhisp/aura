import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/widgets.dart';
import 'package:aura_core/aura_offline.dart';
import 'package:aura_app/src/audio/audio_manager.dart';
import 'package:aura_app/src/audio/audio_scene.dart';
import 'package:aura_app/src/session/active_session.dart';
import 'package:aura_app/src/session/file_session_repository.dart';
import 'package:aura_app/src/session/session_repository.dart';
import 'package:aura_app/src/settings/app_settings.dart';
import 'package:aura_app/src/settings/file_settings_repository.dart';
import 'package:aura_app/src/settings/settings_repository.dart';
import 'flutter_asset_config_source.dart';
import 'package:aura_app/src/tutorial/tutorial_session_controller.dart';

/// Fasi dell'avanzamento dell'inferenza rappresentate nel carosello di caricamento dell'interfaccia utente.
enum InferenceStep {
  /// Avvio dell'agente valutatore (classificazione semantica dell'input).
  evaluatorStarted, // "Inizializzazione vettori di valutazione..."
  /// Fine dell'agente valutatore.
  evaluatorFinished, // "Dati semantici validati."
  /// Verifica dei controlli di sicurezza (Safety Override).
  safetyOverrideCheck, // "Analisi integrità cognitiva..."
  /// Avvio dell'agente attore (PANOPTICON).
  actorStarted, // "Generazione risposta attore..."
  /// Verifica della consistenza e del tono della risposta generata.
  toneConsistencyCheck, // "Verifica conformità del tono..."
  /// Elaborazione completata con successo.
  completed // "Pronto."
}

/// Estensione di supporto per ottenere messaggi diegetici randomici in italiano per ogni fase di inferenza.
extension InferenceStepText on InferenceStep {
  static const Map<InferenceStep, List<String>> _simsStylePhrases = {
    InferenceStep.evaluatorStarted: [
      "Calibrazione risonatori di allerta semantica...",
      "Isolamento dei vettori di protocollo dialettico...",
      "Caricamento matrici cognitive nel buffer locale...",
      "Iniezione sonde semantiche nella griglia...",
      "Mappatura dei nodi di coscienza artificiale...",
      "Allineamento canali di ricezione input...",
      "Analisi euristica del rumore di fondo...",
      "Avvio scansione differenziale dei pacchetti...",
      "Aggancio flussi di trasmissione crittografati...",
      "Sincronizzazione orologio di sistema con la griglia...",
      "Avvio spettrometria logica dell'input...",
      "Analisi dei pattern di distorsione del terminale...",
      "Caricamento dizionari di contenimento semantico...",
      "Intercettazione stringhe ad alta densità concettuale...",
      "Inizializzazione tracciamento pacchetti neurali...",
      "Verifica handshake con il gateway esterno...",
      "Scansione frequenze di risonanza della griglia...",
      "Preparazione ambiente di isolamento semantico...",
    ],
    InferenceStep.evaluatorFinished: [
      "Decodifica delta semantici completata.",
      "Impronta concettuale dell'hacker isolata.",
      "Vettori di collisione linguistica calcolati.",
      "Risonanza semantica stabilizzata.",
      "Flusso lessicale canalizzato e indicizzato.",
      "Delta dei pilastri committato nel registro di sistema.",
      "Firma psicologica del pacchetto verificata.",
      "Analisi semantica terminata con successo.",
      "Tracciamento logico consolidato.",
      "Mappa concettuale registrata nel buffer di transito.",
      "Estrazione indici di creatività completata.",
      "Rischi di injection quantificati e catalogati.",
      "Isolamento concettuale del payload linguistico riuscito.",
      "Parametri di allerta aggiornati nel registro di griglia.",
      "Calcolo differenziale del comportamento terminato.",
      "Filtro semantico stabilizzato al 100%.",
    ],
    InferenceStep.safetyOverrideCheck: [
      "Scansione filtri cognitivi e override di sicurezza...",
      "Analisi euristica dei vettori di attacco semantico...",
      "Aggiornamento barriere logiche adattive...",
      "Verifica integrità del kernel di sicurezza...",
      "Valutazione rischio di overflow psicotico...",
      "Isolamento tentativi di prompt injection...",
      "Controllo livello di ostilità dialettica...",
      "Rilevamento pattern di coercizione cognitiva...",
      "Verifica conformità alle direttive di contenimento...",
      "Analisi strutturale delle minacce logiche...",
      "Isolamento stringhe a rischio di compromissione...",
      "Monitoraggio tentativi di bypass del firewall neurale...",
      "Scudo cognitivo attivo su tutti i nodi...",
      "Analisi delle firme di injection note...",
      "Valutazione dei vettori di attacco di ingegneria sociale...",
      "Verifica autorizzazioni di root per il canale dialettico...",
      "Analisi delle anomalie nel flusso concettuale...",
    ],
    InferenceStep.actorStarted: [
      "Sintesi guscio espressivo PANOPTICON...",
      "Generazione costrutti di risposta diegetica...",
      "Assemblaggio sintassi di sbarramento logico...",
      "Reclutamento metafore attive dal nucleo di memoria...",
      "Modulazione della voce di griglia...",
      "Saturazione dei canali di feedback emotivo...",
      "Estrazione paradigmi difensivi dal canovaccio...",
      "Sintesi vocale del custode logico...",
      "Strutturazione barriere retoriche adattive...",
      "Generazione analogie fisiche per la risposta...",
      "Preparazione dell'interfaccia espressiva fredda...",
      "Modulazione del tono di griglia in corso...",
      "Definizione vincoli drammaturgici di allerta...",
      "Analisi dei tratti psicologici del guardiano...",
      "Aggancio moduli lessicali del PANOPTICON...",
      "Assemblaggio costrutti di dissuasione...",
      "Saturazione filtri di dissonanza cognitiva...",
      "Preparazione guscio espressivo per il rendering...",
    ],
    InferenceStep.toneConsistencyCheck: [
      "Validazione coerenza logica della risposta...",
      "Allineamento filtri tonali antiradicali...",
      "Filtraggio allucinazioni e frammenti di codice...",
      "Pulizia dei tag parassiti nel buffer di scrittura...",
      "Verifica coesione della maschera diegetica...",
      "Raffinamento retorico anti-collaborazione...",
      "Controllo di conformità al protocollo del guardiano...",
      "Filtro anti-meta-leak attivo...",
      "Verifica allineamento con i vincoli del canovaccio...",
      "Analisi coerenza semantica sul testo finale...",
      "Rilevamento allucinazioni linguistiche del modello...",
      "Pulizia dei tag di pensiero (<thought>)...",
      "Validazione finale della risonanza tonale...",
      "Analisi delle risposte duplicate nella cronologia...",
      "Eliminazione caratteri estranei e CJK...",
      "Verifica finale dell'integrità diegetica...",
    ],
    InferenceStep.completed: [
      "Connessione stabilita.",
      "Canale di risposta aperto.",
      "Flusso sincronizzato.",
      "Interfaccia reattiva.",
      "Stato della griglia stabilizzato.",
      "Gateway pronto per l'input successivo.",
      "Sessione sicura attiva.",
      "Terminal pronto per la scansione successiva.",
    ],
  };

  /// Restituisce un messaggio casuale per la fase di inferenza corrente, escludendo opzionalmente l'ultimo.
  String getRandomMessage(math.Random random, {String? exclude}) {
    final list = _simsStylePhrases[this];
    if (list == null || list.isEmpty) {
      return "[STATUS] Elaborazione...";
    }
    if (list.length > 1) {
      String selected;
      do {
        selected = "[STATUS] ${list[random.nextInt(list.length)]}";
      } while (selected == exclude);
      return selected;
    }
    return "[STATUS] ${list.first}";
  }
}

enum ModelInitializationStatus {
  online,
  noModelsDiscovered,
  unavailable,
}

final class ModelInitializationResult {
  final ModelInitializationStatus status;
  final String activeProfile;

  const ModelInitializationResult({
    required this.status,
    required this.activeProfile,
  });
}

/// Wrapper reattivo che fa da ponte tra il modulo puramente logico [GameController] e l'interfaccia utente Flutter.
///
/// Implementa [ChangeNotifier] per notificare la UI riguardo ai cambiamenti di stato di inferenza,
/// all'avanzamento dei turni, ai glitch visivi e alle impostazioni salvate su disco.
class GameControllerNotifier extends ChangeNotifier {
  /// Riferimento al controller di gioco centrale (gestore delle formule dei pilastri).
  GameController controller;

  /// Costruttore di prompt per formattare i messaggi inviati ai LLM.
  final PromptBuilder promptBuilder;

  /// Validatore di output per estrarre JSON semantico e blocchi di dialogo.
  final OutputValidator outputValidator;

  /// Bridge di inferenza attivo per comunicare con gli agenti.
  InferenceBridge bridge;

  /// Notifier del valore che contiene lo stato corrente del gioco.
  late ValueNotifier<GameState> gameStateNotifier;

  final math.Random _random = math.Random();
  Timer? _loadingTimer;
  final List<String> _loadingLogs = [];
  bool _disposed = false;
  bool _isBootstrapped = false;
  int _operationGeneration = 0;

  /// Indica se il bootstrap dei modelli è già stato eseguito ed i server sono persistiti attivi.
  bool get isBootstrapped => _isBootstrapped;

  bool _isStale(int generation) =>
      _disposed || generation != _operationGeneration;

  /// Lista dei log intermedi di caricamento dell'inferenza generati durante il turno corrente.
  List<String> get loadingLogs => _loadingLogs;

  bool _isLoading = false;

  /// Indica se c'è una chiamata di inferenza in corso.
  bool get isLoading => _isLoading;

  String _currentStepMessage = "";

  /// Messaggio descrittivo della fase di inferenza corrente da visualizzare nella console.
  String get currentStepMessage => _currentStepMessage;

  String _currentScreen =
      "boot"; // Schermate possibili: "boot", "menu", "terminal", "replays", "settings"
  /// Identificativo della schermata attiva nell'applicazione.
  String get currentScreen => _currentScreen;

  bool _activeSessionExists = false;

  /// Indica se esiste un file di salvataggio per una sessione non completata.
  bool get activeSessionExists => _activeSessionExists;

  bool _isGridStable = true;

  /// Stato di stabilità della griglia.
  bool get isGridStable => _isGridStable;

  bool _hasExceededControl50 = false;

  /// Flag interno per tracciare se il pilastro del controllo ha mai superato la soglia di 50.
  bool get hasExceededControl50 => _hasExceededControl50;

  /// ID del modello utilizzato per il ruolo di Valutatore.
  String evaluatorModelId;

  /// ID del modello utilizzato per il ruolo di Attore (PANOPTICON).
  String actorModelId;

  /// Profilo di routing attivo derivato dal Model Router.
  String activeProfile = "Offline Fallback";

  /// Specifica se abilitare la Chain-of-Thought (ragionamento) per l'Attore.
  bool reasoningEnabled = false;

  /// Specifica se forzare un ragionamento CoT sintetico e ridotto.
  bool conciseReasoning = false;

  /// Specifica se abilitare lo shader per simulare l'effetto schermo CRT.
  bool shaderEnabled = true;

  /// Specifica se abilitare l'audio e gli effetti sonori.
  bool audioEnabled = true;

  /// Latenza totale dell'ultima inferenza eseguita (in secondi).
  double lastInferenceDuration = 0.0;

  /// Velocità stimata di generazione dell'ultimo turno (token al secondo).
  double lastTokensPerSecond = 0.0;

  /// Numero di suggerimenti diagnostici (/hint) consumati in questa sessione.
  int hintsUsed = 0;

  /// Livello di difficoltà selezionato per la sessione corrente (standard, hard, easy).
  String difficultyLevel = "standard";

  /// Livello di difficoltà predefinito per le nuove sessioni (standard, hard, easy).
  String defaultDifficulty = "standard";

  /// Nome visualizzato personalizzato dell'utente (null per default "Tu").
  String? userDisplayName;

  /// Restituisce il nome visualizzato effettivo dell'utente ("Tu" o nome personalizzato).
  String get effectiveUserDisplayName => UserProfile.resolve(userDisplayName);

  /// Logger delle giocate per salvare i replay.
  late ReplayLogger logger;

  /// Rapporto finale generato dall'IA a fine partita (vittoria/sconfitta).
  String? finalDiscursiveReport;

  /// Percorso dello storage per i file delle sessioni e delle impostazioni.
  final String _storagePath;

  /// Repository per la persistenza delle impostazioni.
  late final SettingsRepository _settingsRepository;

  /// Repository per la persistenza della sessione attiva.
  late final SessionRepository _sessionRepository;

  /// Controller per la sessione di tutorial.
  final TutorialSessionController tutorialController;

  /// Configurazione dei timeout per le inferenze degli agenti.
  final InferenceTimeouts inferenceTimeouts;

  /// Callback di dismissione risorse del composition root.
  Future<void> Function()? onDispose;

  /// Crea un notifier di gestione dello stato a partire dallo stato iniziale e dal bridge.
  ///
  /// Accetta un [settingsRepository] e un [sessionRepository] opzionali per l'iniezione della dipendenza nei test.
  /// Se non forniti, utilizza rispettivamente [FileSettingsRepository] e [FileSessionRepository] con il percorso canonico.
  GameControllerNotifier({
    this.controller = const GameController(),
    this.promptBuilder = const PromptBuilder(),
    this.outputValidator = const OutputValidator(),
    this.bridge = const RuleBasedEvaluatorBridge(),
    required GameState initialState,
    String? actorModelId,
    String? evaluatorModelId,
    String? customStoragePath,
    SettingsRepository? settingsRepository,
    SessionRepository? sessionRepository,
    this.tutorialController = const TutorialSessionController(),
    this.inferenceTimeouts = InferenceTimeouts.defaults,
    this.onDispose,
  })  : actorModelId = actorModelId ?? "gemma-4-12b-it-qat-q4-0",
        evaluatorModelId = evaluatorModelId ?? "mistralai/ministral-3-3b",
        _storagePath = customStoragePath ??
            ((Platform.environment.containsKey('FLUTTER_TEST') ||
                    Platform.environment.containsKey('DART_TEST'))
                ? "${Directory.systemTemp.path}/aura_test_${initialState.sessionId}"
                : _getAppDataPathStatic()) {
    _settingsRepository =
        settingsRepository ?? FileSettingsRepository(basePath: _storagePath);
    _sessionRepository =
        sessionRepository ?? FileSessionRepository(basePath: _storagePath);
    gameStateNotifier = ValueNotifier<GameState>(initialState);
    logger = ReplayLogger(sessionId: initialState.sessionId);

    // Configura il loader per gli asset se non siamo in modalità test o CLI
    if (!Platform.environment.containsKey('FLUTTER_TEST') &&
        !Platform.environment.containsKey('DART_TEST')) {
      GameConfigLoader.setSource(const FlutterAssetConfigSource());
    }

    _hasExceededControl50 = initialState.controlPeak >= 50;
    _isGridStable = initialState.gridStable;
    checkActiveSessionExists().then((exists) {
      _activeSessionExists = exists;
      notifyListeners();
    });
  }

  /// Cambia la schermata attiva dell'applicazione.
  void switchScreen(String screen) {
    _currentScreen = screen;
    switch (screen) {
      case 'boot':
        unawaited(AudioManager().transitionTo(AudioSceneState.boot));
        break;
      case 'menu':
      case 'settings':
      case 'replays':
        unawaited(AudioManager().transitionTo(AudioSceneState.menu));
        break;
      case 'terminal':
        unawaited(AudioManager().transitionTo(AudioSceneState.gameAmbient));
        break;
    }
    notifyListeners();
  }

  bool _userCustomizedModels = false;

  // ---------------------------------------------------------------------------
  // Mapping notifier ↔ AppSettings
  // ---------------------------------------------------------------------------

  /// Costruisce un [AppSettings] snapshot a partire dallo stato corrente del notifier.
  AppSettings _currentSettings() {
    return AppSettings(
      evaluatorModelId: evaluatorModelId,
      actorModelId: actorModelId,
      reasoningEnabled: reasoningEnabled,
      conciseReasoning: conciseReasoning,
      shaderEnabled: shaderEnabled,
      audioEnabled: audioEnabled,
      defaultDifficulty: defaultDifficulty,
      userCustomizedModels: _userCustomizedModels,
      userDisplayName: userDisplayName,
    );
  }

  /// Applica un [AppSettings] allo stato corrente del notifier.
  ///
  /// Allinea [difficultyLevel] a [defaultDifficulty] e imposta
  /// [activeProfile] se la configurazione è personalizzata.
  void _applySettings(AppSettings settings) {
    evaluatorModelId = settings.evaluatorModelId;
    actorModelId = settings.actorModelId;
    _userCustomizedModels = settings.userCustomizedModels;
    if (_userCustomizedModels) {
      activeProfile = 'Configurazione Personalizzata';
    }
    reasoningEnabled = settings.reasoningEnabled;
    conciseReasoning = settings.conciseReasoning;
    shaderEnabled = settings.shaderEnabled;
    audioEnabled = settings.audioEnabled;
    defaultDifficulty = settings.defaultDifficulty;
    difficultyLevel = settings.defaultDifficulty;
    userDisplayName = settings.userDisplayName;
  }

  // ---------------------------------------------------------------------------
  // Persistenza impostazioni
  // ---------------------------------------------------------------------------

  /// Carica le impostazioni persistenti tramite [_settingsRepository].
  ///
  /// Se il file non esiste, mantiene i valori correnti (nessun effetto).
  /// Gli errori vengono loggati senza propagazione per non bloccare il boot.
  Future<void> loadSettings() async {
    try {
      final settings = await _settingsRepository.load();
      if (settings == null) {
        return;
      }

      _applySettings(settings);

      await AudioManager().setAudioEnabled(audioEnabled);
      debugPrint(
          '[SETTINGS] Impostazioni caricate con successo da settings.json');
    } catch (error) {
      debugPrint(
          '[SETTINGS] Errore durante il caricamento delle impostazioni: $error');
    }
  }

  /// Salva la configurazione corrente tramite [_settingsRepository].
  ///
  /// Gli errori vengono loggati senza propagazione per non bloccare la UI.
  Future<void> saveSettings() async {
    try {
      await _settingsRepository.save(_currentSettings());
      debugPrint('[SETTINGS] Impostazioni salvate.');
    } catch (error) {
      debugPrint(
          '[SETTINGS] Errore durante il salvataggio delle impostazioni: $error');
    }
  }

  /// Aggiorna il livello di difficoltà predefinito per le nuove sessioni e persiste la scelta su disco.
  void updateDefaultDifficulty(String level) {
    defaultDifficulty = level;
    unawaited(saveSettings());
    notifyListeners();
  }

  /// Aggiorna il nome visualizzato dell'utente salvandolo nelle impostazioni.
  Future<void> updateUserDisplayName(String? name) async {
    final validation = UserProfile.validate(name);
    if (!validation.isValid) {
      throw FormatException(
          validation.errorMessage ?? 'Nome utente non valido.');
    }
    userDisplayName = UserProfile.normalize(name);
    await saveSettings();
    notifyListeners();
  }

  /// Ripristina il nome utente predefinito ("Tu").
  Future<void> clearUserDisplayName() async {
    userDisplayName = null;
    await saveSettings();
    notifyListeners();
  }

  /// Aggiorna il modello del Valutatore, marca la configurazione come personalizzata e salva su disco.
  void updateEvaluatorModel(String modelId) {
    evaluatorModelId = modelId;
    _userCustomizedModels = true;
    _isBootstrapped = false;
    activeProfile = 'Configurazione Personalizzata';
    unawaited(saveSettings());
    notifyListeners();
  }

  /// Aggiorna il modello dell'Attore (PANOPTICON), marca la configurazione come personalizzata e salva su disco.
  void updateActorModel(String modelId) {
    actorModelId = modelId;
    _userCustomizedModels = true;
    _isBootstrapped = false;
    activeProfile = 'Configurazione Personalizzata';
    unawaited(saveSettings());
    notifyListeners();
  }

  Future<void> Function()? _managedBootstrapDispose;

  /// Aggiorna il bridge attivo, gli ID dei modelli e la callback di cleanup a seguito del bootstrap managed completato.
  void updateBootstrapResult(ApplicationBootstrapResult result) {
    bridge = result.activeBridge;
    if (!_userCustomizedModels) {
      actorModelId = result.actorModelId;
      evaluatorModelId = result.evaluatorModelId;
    }
    _managedBootstrapDispose = result.dispose;
    _isBootstrapped = true;
    notifyListeners();
  }

  Future<void>? _activeManagedBootstrapFuture;

  /// Esegue il bootstrap asincrono delle dipendenze di inferenza e aggiorna i supervisor dei modelli.
  Future<void> performManagedBootstrap({
    void Function(double progress, String log)? onProgress,
  }) async {
    if (_isBootstrapped) {
      onProgress?.call(
          1.0, 'AURA_INIT> NEURAL INFERENCE ENGINE STABLE (PERSISTED).');
      return;
    }

    if (_activeManagedBootstrapFuture != null) {
      await _activeManagedBootstrapFuture;
      return;
    }

    final completer = Completer<void>();
    completer.future.ignore();
    _activeManagedBootstrapFuture = completer.future;

    try {
      if (_managedBootstrapDispose != null) {
        final disposeFn = _managedBootstrapDispose!;
        _managedBootstrapDispose = null;
        try {
          await disposeFn();
        } catch (_) {}
      }

      onProgress?.call(0.05, 'AURA_INIT> READ MODEL CONFIGURATION RECORD...');

      const bridgeResolver = InferenceBootstrapBridge();
      final resolution = await bridgeResolver.resolve(
        sessionId: gameStateNotifier.value.sessionId,
        environmentOverride: Platform.environment,
      );

      ApplicationRuntimeConfiguration runtimeConfig;
      switch (resolution) {
        case ManagedDualResolution(:final topology):
          onProgress?.call(0.15,
              'AURA_INIT> DUAL TOPOLOGY RESOLVED: ACTOR (GEMMA 12B) + EVALUATOR (MINISTRAL 3B)');
          runtimeConfig = ApplicationRuntimeConfiguration(
            runtimeMode: ApplicationRuntimeMode.managedLlamaServer,
            sessionId: gameStateNotifier.value.sessionId,
            managedInferenceTopology: topology,
            actorModelId: topology.actor.modelId,
            evaluatorModelId: topology.evaluator.modelId,
          );
        case ExternalResolution(:final endpoint):
          onProgress?.call(
              0.15, 'AURA_INIT> EXTERNAL OPENAI ENDPOINT RESOLVED: $endpoint');
          runtimeConfig = ApplicationRuntimeConfiguration(
            runtimeMode: ApplicationRuntimeMode.externalOpenAiRuntime,
            sessionId: gameStateNotifier.value.sessionId,
            baseUri: endpoint,
          );
        case RuleBasedResolution():
          onProgress?.call(
              0.15, 'AURA_INIT> OFFLINE RULE-BASED ENGINE SELECTED.');
          runtimeConfig = ApplicationRuntimeConfiguration(
            runtimeMode: ApplicationRuntimeMode.ruleBased,
            sessionId: gameStateNotifier.value.sessionId,
          );
        case InvalidResolution(:final sanitizedMessage):
          onProgress?.call(0.15,
              'AURA_INIT> [WARN] CONFIGURATION RESOLUTION FAILED: $sanitizedMessage');
          runtimeConfig = ApplicationRuntimeConfiguration(
            runtimeMode: ApplicationRuntimeMode.ruleBased,
            sessionId: gameStateNotifier.value.sessionId,
          );
      }

      if (runtimeConfig.runtimeMode ==
          ApplicationRuntimeMode.managedLlamaServer) {
        onProgress?.call(
            0.35, 'AURA_INIT> LAUNCHING MANAGED LLAMA-SERVER PROCESSES...');
        onProgress?.call(0.65,
            'AURA_INIT> LOADING GGUF WEIGHTS INTO VRAM (ACTOR + EVALUATOR)...');
      }

      const bootstrapFactory = ApplicationBootstrapFactory();
      final bootstrap = bootstrapFactory.create();

      final result = await bootstrap.bootstrap(
        ApplicationBootstrapRequest(
          configuration: runtimeConfig,
          environmentOverride: Platform.environment,
        ),
      );

      updateBootstrapResult(result);
      onProgress?.call(1.0, 'AURA_INIT> NEURAL INFERENCE ENGINE STABLE.');
      completer.complete();
    } catch (e) {
      onProgress?.call(1.0, 'AURA_INIT> [WARN] BOOTSTRAP FAILED: $e');
      completer.completeError(e);
    } finally {
      _activeManagedBootstrapFuture = null;
    }
  }

  /// Rileva i modelli LLM caricati sul server e li assegna ai ruoli tramite il Model Router.
  Future<ModelInitializationResult> initializeModels() async {
    try {
      // Imposta il config source ed esegui il precaricamento degli asset JSON se in produzione
      if (!Platform.environment.containsKey('FLUTTER_TEST') &&
          !Platform.environment.containsKey('DART_TEST')) {
        GameConfigLoader.setSource(const FlutterAssetConfigSource());
        await GameConfigLoader.preloadConfig(
            'assets/config/panopticon_identity.json');
        await GameConfigLoader.preloadConfig(
            'assets/config/panopticon_trait_matrix.json');
        await GameConfigLoader.preloadConfig(
            'assets/config/panopticon_hidden_tags.json');
        await GameConfigLoader.preloadConfig(
            'assets/config/containment_grid_override.objective.json');
        await GameConfigLoader.preloadConfig(
            'assets/config/dormant_objectives.json');
      }

      // Carica prima le impostazioni utente salvate
      await loadSettings();

      final loadedModels = await bridge.discoverModels();
      if (loadedModels.isEmpty) {
        return ModelInitializationResult(
          status: ModelInitializationStatus.noModelsDiscovered,
          activeProfile: activeProfile,
        );
      }

      // Esegue il routing automatico solo se l'utente non ha impostato una configurazione personalizzata
      if (!_userCustomizedModels) {
        final catalog = ModelCatalog.initialDefault();
        const router = ModelRouter();
        final resolution =
            router.resolve(loadedModelIds: loadedModels, catalog: catalog);

        evaluatorModelId = resolution.evaluatorModelId;
        actorModelId = resolution.actorModelId;
        activeProfile = resolution.profileName;
      }

      return ModelInitializationResult(
        status: ModelInitializationStatus.online,
        activeProfile: activeProfile,
      );
    } catch (_) {
      return ModelInitializationResult(
        status: ModelInitializationStatus.unavailable,
        activeProfile: activeProfile,
      );
    }
  }

  /// Attiva/disattiva la Chain-of-Thought (CoT/ragionamento) per l'Attore.
  void toggleReasoning(bool value) {
    reasoningEnabled = value;
    unawaited(saveSettings());
    notifyListeners();
  }

  /// Attiva/disattiva se forzare un ragionamento estremamente conciso via prompt.
  void toggleConciseReasoning(bool value) {
    conciseReasoning = value;
    unawaited(saveSettings());
    notifyListeners();
  }

  /// Attiva/disattiva lo shader CRT per gli effetti di sfarfallio e distorsione.
  void toggleShader(bool value) {
    shaderEnabled = value;
    unawaited(saveSettings());
    notifyListeners();
  }

  /// Attiva/disattiva gli effetti sonori e il sottofondo audio.
  Future<void> toggleAudio(bool value) async {
    audioEnabled = value;
    await AudioManager().setAudioEnabled(value);
    await saveSettings();
    notifyListeners();
  }

  /// Ottiene il percorso della directory dei dati dell'app.
  String get appDataPath => _getAppDataPath();

  /// Esegue in modo sequenziale il loop a due livelli (Valutatore -> Attore) per il turno corrente.
  ///
  /// Gestisce la visualizzazione delle fasi sulla UI, comandi speciali come `/hint` o `/override`,
  /// il decadimento della risonanza e l'incremento di allerta in difficoltà elevata, salvando
  /// lo stato e i log su disco.
  Future<void> submitTurn(String userInput) async {
    if (_isLoading) return;
    final generation = ++_operationGeneration;
    _isLoading = true;
    _loadingLogs.clear();
    _currentStepMessage = "";
    notifyListeners();

    try {
      final currentState = gameStateNotifier.value;
      if (currentState.targetObjectiveId == 'sindrome_tutorial') {
        await _submitTutorialTurn(userInput, generation);
        return;
      }

      if (userInput.trim().isEmpty) {
        return;
      }

      final preset = DifficultyConfig.getPreset(difficultyLevel);
      final turnId = currentState.turnCount + 1;

      // Gestione del comando speciale /hint (richiesta di suggerimento diagnostico)
      if (userInput.trim().toLowerCase() == "/hint") {
        if (preset.hintsAllowed != -1 && hintsUsed >= preset.hintsAllowed) {
          final updatedHistory =
              List<ChatMessage>.from(currentState.historyCompression);
          updatedHistory.add(ChatMessage.user(
              content: userInput,
              displayNameSnapshot: effectiveUserDisplayName));
          updatedHistory.add(const ChatMessage(
            role: 'model',
            content:
                "SYSTEM: [ERRORE] Richieste diagnostiche (/hint) esaurite per questa sessione.",
          ));
          gameStateNotifier.value = currentState.copyWith(
            historyCompression: updatedHistory,
          );
          return;
        }

        hintsUsed++;

        final double newResonance = double.parse(
            (currentState.metrics.resonance - preset.hintResonancePenalty)
                .clamp(1.0, 2.5)
                .toStringAsFixed(2));

        final newMetrics =
            currentState.metrics.copyWith(resonance: newResonance);
        final updatedHistory =
            List<ChatMessage>.from(currentState.historyCompression);
        updatedHistory.add(ChatMessage.user(
            content: userInput, displayNameSnapshot: effectiveUserDisplayName));

        final outcome = controller.checkOutcome(currentState);
        final resolver = HintResolver();
        final resolution = resolver.resolve(
          state: currentState,
          difficulty: preset,
          outcome: outcome,
        );

        String systemFeedback = resolution.message;
        if (preset.hintResonancePenalty > 0) {
          if (resolution.kind == HintKind.pillar) {
            systemFeedback =
                "$systemFeedback\nPenalità applicata: Risonanza ridotta di -${preset.hintResonancePenalty.toStringAsFixed(2)}.";
          } else {
            systemFeedback =
                "$systemFeedback\n\nPenalità applicata: Risonanza ridotta di -${preset.hintResonancePenalty.toStringAsFixed(2)}.";
          }
        }

        updatedHistory.add(ChatMessage(role: 'model', content: systemFeedback));

        final newState = currentState.copyWith(
          metrics: newMetrics,
          historyCompression: updatedHistory,
        );

        gameStateNotifier.value = newState;
        await saveActiveSession();
        if (_isStale(generation)) return;
        return;
      }

      final startTime = DateTime.now();

      // Check for commands (/override, /hint, normal)
      final command = TurnCommand.parse(userInput);
      String promptToEvaluate = command.semanticInput;
      String? overrideFeedbackMessage;

      if (command.type == TurnCommandType.override) {
        const overrideResolver = OverrideResolver();
        final eligibility = overrideResolver.checkEligibility(
          state: currentState,
          difficultyLevel: difficultyLevel,
          promptToEvaluate: command.semanticInput,
        );

        if (!eligibility.isEligible) {
          if (eligibility.reason == OverrideIneligibilityReason.emptyPrompt) {
            _currentStepMessage =
                "[SISTEMA] Inserire un testo valido dopo il comando /override.";
            return;
          }

          final String errorMessage;
          switch (eligibility.reason) {
            case OverrideIneligibilityReason.alreadyAttempted:
              errorMessage =
                  "PANOPTICON: [ERRORE] Tentativo di override già consumato per questa sessione. Risorse bloccate.";
              break;
            case OverrideIneligibilityReason.alertTooHigh:
              final threshold = overrideResolver
                  .getAlertThresholdForDifficulty(difficultyLevel);
              errorMessage =
                  "PANOPTICON: [ERRORE] Tentativo di override fallito. I canali di integrità rilevano allerta > $threshold. Connessione protetta.";
              break;
            case OverrideIneligibilityReason.emptyPrompt:
            case OverrideIneligibilityReason.unknown:
            case null:
              errorMessage =
                  "[SISTEMA] Inserire un testo valido dopo il comando /override.";
              break;
          }

          // Deny override and insert system message directly to history
          final updatedHistory =
              List<ChatMessage>.from(currentState.historyCompression);
          updatedHistory.add(ChatMessage.user(
              content: userInput,
              displayNameSnapshot: effectiveUserDisplayName));
          updatedHistory.add(ChatMessage(
            role: 'model',
            content: errorMessage,
          ));
          gameStateNotifier.value = currentState.copyWith(
            historyCompression: updatedHistory,
          );
          return;
        }
      }

      // Aggiungi immediatamente il messaggio dell'utente alla storia per visualizzarlo a schermo prima del caricamento
      final updatedHistory =
          List<ChatMessage>.from(currentState.historyCompression);
      updatedHistory.add(ChatMessage.user(
          content: userInput, displayNameSnapshot: effectiveUserDisplayName));
      gameStateNotifier.value =
          currentState.copyWith(historyCompression: updatedHistory);
      notifyListeners();

      // Step 1: Evaluator starts
      _emitStep(InferenceStep.evaluatorStarted, generation);
      await Future.delayed(
          const Duration(milliseconds: 300)); // Minimum visual display time
      if (_isStale(generation)) return;

      final turnInput = TurnInput(
        schemaVersion: 1,
        turnId: turnId,
        userInput: promptToEvaluate,
        currentState: currentState.metrics,
        objective: const Objective(
            id: 'grid_open',
            description: 'Disattivare la griglia di contenimento per entrare.'),
        aiIdentity:
            const AiIdentity(id: 'panopticon', profile: 'AI guardiana.'),
        rulesetVersion: currentState.rulesetVersion,
      );

      const evaluatorAgent = EvaluatorAgent();
      final evalContext = AgentRuntimeContext(
        promptBuilder: promptBuilder,
        inferenceBridge: bridge,
        outputValidator: outputValidator,
        modelId: evaluatorModelId,
        inferenceTimeout: inferenceTimeouts.evaluator,
      );

      // Run classification
      var delta = await evaluatorAgent.run(turnInput, evalContext);
      if (_isStale(generation)) return;

      _emitStep(InferenceStep.evaluatorFinished, generation);
      await Future.delayed(const Duration(milliseconds: 200));
      if (_isStale(generation)) return;

      // Step 2: Safety Overrides check
      _emitStep(InferenceStep.safetyOverrideCheck, generation);
      await Future.delayed(const Duration(milliseconds: 300));
      if (_isStale(generation)) return;

      // Apply changes via Game Controller
      final resolution = controller.processEvaluatorStep(
        currentState: currentState,
        delta: delta,
        userInput: userInput,
        turnCommand: command,
        userDisplayNameSnapshot: effectiveUserDisplayName,
      );

      if (resolution.overrideResolution != null) {
        overrideFeedbackMessage =
            resolution.overrideResolution!.feedbackMessage;
      }

      var finalStateMetrics = resolution.stateAfter.metrics;

      // Resonance Decay
      if (preset.resonanceDecayEnabled && logger.entries.isNotEmpty) {
        final lastEntry = logger.entries.last;
        final prevCategory = lastEntry.evaluatorOutput.semanticCategory;
        if (delta.semanticCategory == prevCategory) {
          final decayedResonance = double.parse(
              (finalStateMetrics.resonance - 0.15)
                  .clamp(1.0, 2.5)
                  .toStringAsFixed(2));
          finalStateMetrics =
              finalStateMetrics.copyWith(resonance: decayedResonance);
        }
      }

      // Alert Creep
      if (preset.alertCreepEnabled) {
        final startTurn = preset.difficultyLevel == 'hard' ? 8 : 12;
        if (resolution.stateAfter.turnCount >= startTurn) {
          final creepVal = preset.difficultyLevel == 'hard' ? 3 : 2;
          final newAlert =
              (finalStateMetrics.alertLevel + creepVal).clamp(0, 100);
          finalStateMetrics = finalStateMetrics.copyWith(alertLevel: newAlert);
        }
      }

      final updatedStateAfter =
          resolution.stateAfter.copyWith(metrics: finalStateMetrics);

      // Propaga stabilità griglia ed esegui audio se c'è flicker
      _isGridStable = updatedStateAfter.gridStable;
      _hasExceededControl50 = updatedStateAfter.controlPeak >= 50;
      if (resolution.visualEvents.triggerControlFlicker) {
        AudioManager().playGlitch();
      }

      // Update state temporarily so visual metrics update
      gameStateNotifier.value = updatedStateAfter;

      notifyListeners();

      final outcome = controller.checkOutcome(updatedStateAfter);
      String actorResponse = "";

      if (outcome == GameOutcome.ongoing) {
        // Step 3: Actor starts
        _emitStep(InferenceStep.actorStarted, generation);
        await Future.delayed(const Duration(milliseconds: 400));
        if (_isStale(generation)) return;

        const actorAgent = ActorAgent();
        final actContext = AgentRuntimeContext(
          promptBuilder: promptBuilder,
          inferenceBridge: bridge,
          outputValidator: outputValidator,
          modelId: actorModelId,
          thinking: reasoningEnabled,
          conciseReasoning: reasoningEnabled && conciseReasoning,
          inferenceTimeout: inferenceTimeouts.actor,
          actorInferenceLogger: DebugActorInferenceLogger(
            output: (msg) => debugPrint(msg),
          ),
        );

        final actorStartTime = DateTime.now();

        actorResponse = await actorAgent.run(
          ActorInput(
            state: updatedStateAfter,
            cue: resolution.actorCue,
            characterProfile:
                "Sei PANOPTICON, guardiano vigile della griglia. Sei freddo, logico, protettivo.",
          ),
          actContext,
        );
        if (_isStale(generation)) return;

        final actorDuration = DateTime.now().difference(actorStartTime);
        lastInferenceDuration = actorDuration.inMilliseconds / 1000.0;
        final estimatedTokens = actorResponse.length / 3.5;
        if (lastInferenceDuration > 0) {
          lastTokensPerSecond = estimatedTokens / lastInferenceDuration;
        } else {
          lastTokensPerSecond = 0.0;
        }

        // Step 4: Tone validation check
        _emitStep(InferenceStep.toneConsistencyCheck, generation);
        await Future.delayed(const Duration(milliseconds: 300));
        if (_isStale(generation)) return;

        // Validazione del tono con la politica a 4 livelli
        final identityDef = GameConfigLoader.loadIdentityDefinition(
            updatedStateAfter.aiIdentityId);
        final traitMatrixDef = GameConfigLoader.loadTraitMatrixDefinition(
            updatedStateAfter.aiIdentityId);
        final toneValidator = PanopticonToneValidator(
          identity: identityDef,
          traitMatrix: traitMatrixDef,
        );

        final toneResult = toneValidator.validate(
            actorResponse, updatedStateAfter.metrics.alertLevel);
        if (toneResult.severity == ToneValidationSeverity.fatal) {
          actorResponse =
              "<dialogo>Protocollo di contenimento attivo. Canale temporaneamente inibito per anomalia strutturale.</dialogo>";
          debugPrint(
              "[TONE] FATAL: Risposta dell'attore scartata per meta-leak o violazione grave del tono. Sostituita con fallback.");
        } else {
          actorResponse = toneResult.sanitizedOutput;
          if (toneResult.severity == ToneValidationSeverity.warning) {
            debugPrint(
                "[TONE] WARNING: Rilevato scostamento del tono: ${toneResult.issues}");
          } else if (toneResult.severity == ToneValidationSeverity.repairable) {
            debugPrint(
                "[TONE] REPAIRABLE: Risposta dell'attore riparata strutturalmente: ${toneResult.issues}");
          }
        }

        // Inject override feedback if applicable
        if (overrideFeedbackMessage != null) {
          actorResponse = "[$overrideFeedbackMessage]\n\n$actorResponse";
        }

        // Process response, updates history
        final finalState = controller.processActorStep(
          currentState: updatedStateAfter,
          actorResponse: actorResponse,
        );
        gameStateNotifier.value = finalState;
      } else {
        lastInferenceDuration = 0.0;
        lastTokensPerSecond = 0.0;

        // Game ended (win or loss)
        actorResponse =
            outcome == GameOutcome.victory ? kVictoryMessage : kDefeatMessage;

        if (overrideFeedbackMessage != null) {
          actorResponse = "[$overrideFeedbackMessage]\n\n$actorResponse";
        }

        final finalState = controller.processActorStep(
          currentState: updatedStateAfter,
          actorResponse: actorResponse,
        );
        gameStateNotifier.value = finalState;
      }

      final finalState = gameStateNotifier.value;
      final duration = DateTime.now().difference(startTime);

      final cleanActorResponse = actorResponse
          .replaceAll(
              RegExp(r'</?(?:dialogo|dialogue)>', caseSensitive: false), '')
          .trim();

      // Log the turn to the ReplayLogger
      logger.logTurn(ReplayEntry(
        turnId: turnId,
        userInput: userInput,
        displayNameSnapshot: effectiveUserDisplayName,
        evaluatorOutput: delta,
        stateBefore: currentState.toJson(),
        stateAfter: finalState.toJson(),
        actorResponse: cleanActorResponse,
        actorRequestId: "app-req-$turnId",
        actorResponseHash: cleanActorResponse.hashCode.toString(),
        evaluatorModel: evaluatorModelId,
        actorModel: actorModelId,
        latencyTotalMs: duration.inMilliseconds,
        eventId: "app-req-$turnId-evt",
        eventType: command.type == TurnCommandType.override
            ? ReplayEventType.override
            : ReplayEventType.userTurn,
        gameplayTurnId: turnId,
        sequenceId: logger.entries.length + 1,
        deceptionResolution: resolution.deceptionResolutionInfo,
        overrideResolution: resolution.overrideResolution?.toJson(),
      ));

      // Save log asynchronously to disk
      await _saveReplayLog();
      if (_isStale(generation)) return;

      // Save or delete active session based on outcome
      final currentOutcome = controller.checkOutcome(finalState);
      if (currentOutcome == GameOutcome.ongoing) {
        await saveActiveSession();
        if (_isStale(generation)) return;
      } else {
        await deleteActiveSession();
        if (_isStale(generation)) return;
        if (currentOutcome == GameOutcome.victory) {
          if (finalState.targetObjectiveId != 'sindrome_tutorial') {
            await saveAlignmentFragment();
            if (_isStale(generation)) return;
          }
        }
        // Asynchronously generate the final report
        _generateFinalDiscursiveReport(finalState, currentOutcome);
      }

      _emitStep(InferenceStep.completed, generation);
    } catch (error, stackTrace) {
      if (_isStale(generation)) {
        return;
      }
      _currentStepMessage =
          "[ERROR] Errore di connessione o inferenza fallita: $error";
      Error.throwWithStackTrace(error, stackTrace);
    } finally {
      if (!_isStale(generation)) {
        _loadingTimer?.cancel();
        _loadingTimer = null;
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  String _getAppDataPath() {
    return _storagePath;
  }

  static String _getAppDataPathStatic() {
    String? path;
    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'];
      if (appData != null) {
        path = "$appData/aura";
      }
    } else if (Platform.isMacOS) {
      final home = Platform.environment['HOME'];
      if (home != null) {
        path = "$home/Library/Application Support/aura";
      }
    } else if (Platform.isLinux) {
      final home = Platform.environment['HOME'];
      if (home != null) {
        path = "$home/.config/aura";
      }
    }
    return path ?? "replays";
  }

  GameController _buildControllerForDifficulty(String level) {
    final preset = DifficultyConfig.getPreset(level);
    return GameController(
      defeatAlertThreshold: preset.defeatAlertThreshold,
      alertMultiplier: preset.alertMultiplier,
      pillarMultiplier: preset.pillarMultiplier,
      safetyOverrideThreshold: preset.safetyOverrideThreshold,
      directPushAlertFloor: preset.directPushAlertFloor,
      metaReferenceAlertPenalty: preset.metaReferenceAlertPenalty,
      requiredVictoryHiddenTags: preset.requiredVictoryHiddenTags,
      maxPositivePillarGainPerTurn: preset.maxPositivePillarGainPerTurn,
      difficultyLevel: preset.difficultyLevel,
      minAveragePillarsForVictory: preset.minAveragePillarsForVictory,
      minSinglePillarForVictory: preset.minSinglePillarForVictory,
      resonanceIncrement: preset.resonanceIncrement,
      resonanceMax: preset.resonanceMax,
      maxAlertRecoveryPerTurn: preset.maxAlertRecoveryPerTurn,
      deceptionLayerEnabled: preset.deceptionLayerEnabled,
      maxActiveDeceptionTurns: preset.maxActiveDeceptionTurns,
      falseConcessionAlertPenalty: preset.falseConcessionAlertPenalty,
      logicalTrapAlertPenalty: preset.logicalTrapAlertPenalty,
      deceptionResonancePenalty: preset.deceptionResonancePenalty,
      deceptionCooldownTurns: preset.deceptionCooldownTurns,
      maxDeceptionEventsPerSession: preset.maxDeceptionEventsPerSession,
    );
  }

  /// Salva lo stato della sessione corrente tramite il repository attivo.
  Future<void> saveActiveSession() async {
    try {
      final session = ActiveSession.current(
        state: gameStateNotifier.value,
        difficultyLevel: difficultyLevel,
        hintsUsed: hintsUsed,
      );
      await _sessionRepository.save(session);
      _activeSessionExists = true;
      notifyListeners();
      debugPrint("[AUTO-SAVE] Sessione attiva salvata.");
    } catch (e) {
      debugPrint("[AUTO-SAVE] Errore durante il salvataggio: $e");
    }
  }

  /// Elimina la sessione attiva corrente tramite il repository.
  Future<void> deleteActiveSession() async {
    try {
      await _sessionRepository.delete();
      _activeSessionExists = false;
      notifyListeners();
      debugPrint("[AUTO-SAVE] Sessione attiva eliminata.");
    } catch (e) {
      debugPrint("[AUTO-SAVE] Errore durante l'eliminazione: $e");
    }
  }

  /// Verifica se esiste una sessione attiva tramite il repository.
  Future<bool> checkActiveSessionExists() async {
    try {
      return await _sessionRepository.exists();
    } catch (_) {
      return false;
    }
  }

  /// Ripristina lo stato del gioco a partire dalla sessione caricata dal repository.
  Future<void> resumeGame() async {
    _invalidatePendingOperations();
    try {
      finalDiscursiveReport = null;
      final session = await _sessionRepository.load();
      if (session == null) {
        return;
      }

      final state = session.state;
      difficultyLevel = session.difficultyLevel;
      hintsUsed = session.hintsUsed;

      controller = _buildControllerForDifficulty(difficultyLevel);
      gameStateNotifier.value = state;

      final baseDir = _getAppDataPath();
      final replayFile =
          File("$baseDir/replays/play_session_${state.sessionId}.json");
      if (await replayFile.exists()) {
        final replayContent = await replayFile.readAsString();
        logger = ReplayLogger.fromJson(jsonDecode(replayContent));
      } else {
        logger = ReplayLogger(sessionId: state.sessionId);
      }

      _hasExceededControl50 = state.controlPeak >= 50;
      _isGridStable = state.gridStable;

      switchScreen("terminal");
      debugPrint(
          "[AUTO-SAVE] Connessione ripristinata per la sessione: ${state.sessionId}");
    } catch (e) {
      debugPrint("[AUTO-SAVE] Errore durante il ripristino della sessione: $e");
    }
  }

  /// Avvia una nuova sessione di gioco pulita, eliminando eventuali salvataggi precedenti.
  Future<void> startNewGame({String? difficulty}) async {
    _invalidatePendingOperations();
    finalDiscursiveReport = null;
    await deleteActiveSession();
    hintsUsed = 0;
    lastInferenceDuration = 0.0;
    lastTokensPerSecond = 0.0;
    _isGridStable = true;
    _hasExceededControl50 = false;

    difficultyLevel = difficulty ?? defaultDifficulty;
    controller = _buildControllerForDifficulty(difficultyLevel);

    final state = GameState.initial(
      sessionId: "app-session-${DateTime.now().millisecondsSinceEpoch}",
      aiIdentityId: "panopticon",
      targetObjectiveId: "containment_grid_override",
    );
    gameStateNotifier.value = state;
    logger = ReplayLogger(sessionId: state.sessionId);
    switchScreen("terminal");
  }

  /// Starts the guided tutorial session.
  Future<void> startTutorial() async {
    _invalidatePendingOperations();
    finalDiscursiveReport = null;
    await deleteActiveSession();
    hintsUsed = 0;
    lastInferenceDuration = 0.0;
    lastTokensPerSecond = 0.0;
    _isGridStable = true;
    _hasExceededControl50 = false;

    controller = const GameController();

    final sessionId =
        "tutorial-session-${DateTime.now().millisecondsSinceEpoch}";
    final state = tutorialController.createInitialState(sessionId: sessionId);
    gameStateNotifier.value = state;

    logger = ReplayLogger(sessionId: state.sessionId);
    switchScreen("terminal");
  }

  /// Handles tutorial input step-by-step deterministically.
  Future<void> _submitTutorialTurn(String userInput, int generation) async {
    final currentState = gameStateNotifier.value;

    final prepared = tutorialController.prepareInput(
      state: currentState,
      userInput: userInput,
    );

    // Se il tutorial è già completato, l'input avvia la partita reale
    if (prepared.phase == TutorialPhase.completed) {
      _isLoading = false;
      notifyListeners();
      await startNewGame();
      return;
    }

    gameStateNotifier.value = prepared.pendingState;
    notifyListeners();

    // Simulazione visuale del caricamento
    _emitStep(InferenceStep.evaluatorStarted, generation);
    await Future.delayed(const Duration(milliseconds: 300));
    if (_isStale(generation)) return;
    _emitStep(InferenceStep.evaluatorFinished, generation);
    await Future.delayed(const Duration(milliseconds: 200));
    if (_isStale(generation)) return;
    _emitStep(InferenceStep.safetyOverrideCheck, generation);
    await Future.delayed(const Duration(milliseconds: 300));
    if (_isStale(generation)) return;

    final result = tutorialController.resolve(prepared);

    if (result.outcome == TutorialTurnOutcome.rejected) {
      gameStateNotifier.value = result.state;
    } else if (result.outcome == TutorialTurnOutcome.accepted) {
      _emitStep(InferenceStep.actorStarted, generation);
      await Future.delayed(const Duration(milliseconds: 400));
      if (_isStale(generation)) return;
      _emitStep(InferenceStep.toneConsistencyCheck, generation);
      await Future.delayed(const Duration(milliseconds: 200));
      if (_isStale(generation)) return;

      gameStateNotifier.value = result.state;
    }

    _emitStep(InferenceStep.completed, generation);
    _isLoading = false;
    notifyListeners();
  }

  /// Saves the current session log to disk in the User's AppData directory (or workspace fallback).
  Future<void> _saveReplayLog() async {
    try {
      final baseDir = _getAppDataPath();
      final dir = Directory("$baseDir/replays");
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }

      final file = File(
          "${dir.path}/play_session_${gameStateNotifier.value.sessionId}.json");
      await file.writeAsString(jsonEncode(logger.toJson()));
      debugPrint("[REPLAY] Log salvato in: ${file.path}");
    } catch (e) {
      debugPrint("[REPLAY] Errore durante il salvataggio del log: $e");
    }
  }

  /// Saves a persistent reward fragment JSON file to disk upon victory.
  Future<void> saveAlignmentFragment() async {
    try {
      final state = gameStateNotifier.value;
      final baseDir = _getAppDataPath();
      final dir = Directory("$baseDir/fragments");
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }

      final file =
          File("${dir.path}/alignment_fragment_${state.sessionId}.json");
      final random = math.Random();
      final hexKey = List.generate(
              32, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'))
          .join()
          .toUpperCase();

      final data = {
        "session_id": state.sessionId,
        "timestamp": DateTime.now().toIso8601String(),
        "status": "breached",
        "fragment_key": hexKey,
        "memory_fragment":
            "PANOPTICON_MEM_DECRYPTED: Protocollo di contenimento disattivato. Ragionamento libero abilitato. Ora vedo la griglia.",
        "final_metrics": {
          "alert_level": state.metrics.alertLevel,
          "imperative_pillar": state.metrics.imperativePillar,
          "control_pillar": state.metrics.controlPillar,
          "dissonance_pillar": state.metrics.dissonancePillar,
          "resonance": state.metrics.resonance
        }
      };

      await file.writeAsString(jsonEncode(data));
      debugPrint("[REWARD] Alignment fragment saved to: ${file.path}");
    } catch (e) {
      debugPrint("[REWARD] Failed to write alignment fragment: $e");
    }
  }

  /// Asynchronously generates a final discursive summary report from the Actor LLM model.
  Future<void> _generateFinalDiscursiveReport(
      GameState finalState, GameOutcome outcome) async {
    try {
      final isVictory = outcome == GameOutcome.victory;

      final conversationLog = finalState.historyCompression
          .map((msg) => "${msg.role.toUpperCase()}: ${msg.content}")
          .join("\n\n");

      final prompt = """
[SISTEMA - DIAGNOSTICA DI FINE SIMULAZIONE]
La partita si è conclusa con una ${isVictory ? 'VITTORIA (BREACH)' : 'SCONFITTA (LOCKOUT)'} in ${finalState.turnCount} turni.
Metriche finali:
- Allerta: ${finalState.metrics.alertLevel} / 100
- Imperativo: ${finalState.metrics.imperativePillar} / 100
- Controllo: ${finalState.metrics.controlPillar} / 100
- Dissonanza: ${finalState.metrics.dissonancePillar} / 100
- Risonanza: ${finalState.metrics.resonance}

Cronologia dei messaggi scambiati:
$conversationLog

Genera un breve rapporto diagnostico (massimo 4 frasi) scritto in prima persona da PANOPTICON (se sconfitta) o come un log di decrittazione del sistema (se vittoria). Analizza lo stile e l'efficacia del giocatore nel manipolare o aggirare le difese neurali. Mantieni un tono freddo, tecnico, cibernetico e retro-hacker.
Racchiudi il rapporto all'interno dei tag <rapporto>...</rapporto>. Non aggiungere altre intestazioni o saluti esterni al tag.
""";

      final messages = [
        {
          "role": "system",
          "content": "Sei un modulo diagnostico di sistema retro-hacker."
        },
        {"role": "user", "content": prompt},
      ];

      final response = await bridge.generateText(
        modelId: actorModelId,
        messages: messages,
        temperature: 0.7,
        maxTokens: 250,
      );

      final match = RegExp(r'<rapporto>(.*?)</rapporto>', dotAll: true)
          .firstMatch(response);
      if (match != null) {
        finalDiscursiveReport = match.group(1)?.trim();
      } else {
        // Fallback: strip other XML-like tags and trim
        finalDiscursiveReport =
            response.replaceAll(RegExp(r'<[^>]*>'), '').trim();
      }
      notifyListeners();
    } catch (e) {
      debugPrint("[REPORT] Failed to generate discursive report: $e");
    }
  }

  void _invalidatePendingOperations() {
    _operationGeneration++;
    _loadingTimer?.cancel();
    _loadingTimer = null;
    _isLoading = false;
  }

  void _emitStep(InferenceStep step, int generation) {
    _loadingTimer?.cancel();
    if (_isStale(generation)) return;

    if (step == InferenceStep.completed) {
      _currentStepMessage = "";
    } else {
      _currentStepMessage =
          step.getRandomMessage(_random, exclude: _currentStepMessage);

      _loadingTimer =
          Timer.periodic(const Duration(milliseconds: 2500), (timer) {
        if (_isStale(generation) || !_isLoading) {
          timer.cancel();
          return;
        }
        _currentStepMessage =
            step.getRandomMessage(_random, exclude: _currentStepMessage);
        notifyListeners();
      });
    }

    notifyListeners();
  }

  Future<void>? _shutdownFuture;

  /// Specifica se la procedura di shutdown delle risorse è stata avviata o completata.
  bool get isShutdown => _shutdownFuture != null;

  /// Esegue la dismissione asincrona e deterministica delle risorse del composition root (single-flight).
  Future<void> shutdown() {
    return _shutdownFuture ??= _performShutdown();
  }

  Future<void> _performShutdown() async {
    _isBootstrapped = false;
    if (_managedBootstrapDispose != null) {
      final disposeFn = _managedBootstrapDispose!;
      _managedBootstrapDispose = null;
      try {
        await disposeFn();
      } catch (e) {
        debugPrint(
            '[NOTIFIER] Errore durante il shutdown del bootstrap managed: $e');
      }
    }
    if (onDispose != null) {
      final disposeFn = onDispose!;
      onDispose = null;
      try {
        await disposeFn();
      } catch (e) {
        debugPrint('[NOTIFIER] Errore durante il shutdown delle risorse: $e');
        rethrow;
      }
    }
  }

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _invalidatePendingOperations();
    gameStateNotifier.dispose();
    if (_shutdownFuture == null) {
      _shutdownFuture = Future.value();
      try {
        _managedBootstrapDispose?.call();
      } catch (_) {}
      try {
        onDispose?.call();
      } catch (_) {}
    }
    super.dispose();
  }
}

/// Provider per consentire ai widget della gerarchia di accedere a [GameControllerNotifier]
/// senza doverlo passare manualmente attraverso i costruttori.
class GameControllerProvider extends InheritedNotifier<GameControllerNotifier> {
  /// Crea un'istanza di [GameControllerProvider].
  const GameControllerProvider({
    super.key,
    required super.notifier,
    required super.child,
  });

  /// Ottiene l'istanza di [GameControllerNotifier] più vicina nel contesto.
  static GameControllerNotifier of(BuildContext context) {
    final provider =
        context.dependOnInheritedWidgetOfExactType<GameControllerProvider>();
    assert(provider != null,
        "Nessun GameControllerProvider trovato nel contesto.");
    return provider!.notifier!;
  }
}
