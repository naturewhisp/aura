import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../state_management/game_controller_notifier.dart';
import '../audio/audio_manager.dart';
import '../audio/audio_scene.dart';
import '../widgets/audio_reactive_background.dart';
import 'new_connection_briefing_screen.dart';

/// Schermata iniziale di Boot e Menu Principale dell'applicazione A.U.R.A.
///
/// Questa schermata gestisce la sequenza di avvio simulata (in stile terminale retro),
/// il caricamento dinamico dei modelli e la navigazione nel menu principale che consente
/// di iniziare il tutorial, una nuova partita, riprendere una sessione esistente,
/// visualizzare i replay delle giocate o modificare le impostazioni di configurazione.
class BootMenuScreen extends StatefulWidget {
  /// Notifier per la sincronizzazione dello stato globale di gioco.
  final GameControllerNotifier notifier;

  /// Costruisce una schermata [BootMenuScreen] a partire dal notifier.
  const BootMenuScreen({
    super.key,
    required this.notifier,
  });

  @override
  State<BootMenuScreen> createState() => _BootMenuScreenState();
}

/// Stato associato alla schermata [BootMenuScreen].
///
/// Gestisce le variabili dell'animazione di boot, la selezione dell'indice del menu,
/// il caricamento asincrono dei file di replay e l'interazione da tastiera per la navigazione.
class _BootMenuScreenState extends State<BootMenuScreen>
    with SingleTickerProviderStateMixin {
  /// Sotto-schermata attiva all'interno del menu di avvio ("boot", "menu", "replays", "replay_detail", "settings").
  String _subScreen = "boot";

  // Campi relativi all'animazione di boot
  final List<String> _bootLines = [];
  bool _logoVisible = false;
  bool _pressEnterVisible = false;
  int _currentBootStep = 0;
  Timer? _bootTimer;
  final FocusNode _focusNode = FocusNode();

  // Campi per la gestione dei replay salvati su disco
  List<FileSystemEntity> _replayFiles = [];
  Map<String, dynamic>? _selectedReplayData;
  String _selectedReplayName = "";

  // Modelli disponibili nel catalogo locale (utilizzati per le opzioni di custom routing)
  final List<String> _modelsList = const [
    "qwen/qwen3.5-9b",
    "mistralai/ministral-3-3b",
    "google/gemma-4-12b"
  ];

  // Indici e chiavi globali per la navigazione del menu ed effetti di lampeggiamento
  int _selectedMenuIndex = 0;
  int? _flashingIndex;
  final List<GlobalKey> _menuKeys = List.generate(6, (index) => GlobalKey());

  @override
  void initState() {
    super.initState();
    _startBootSequence();
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _bootTimer?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  void _startBootSequence() {
    final steps = [
      "SYSTEM INITIALIZATION... OK",
      "SCANNING HARDWARE ENGINES (Vulkan/CUDA)... DETECTED",
      "FETCHING LOCAL MODEL CATALOG...",
      "ACTIVE ENGINES IDENTIFIED AND ROUTED.",
      "CONNECTING TO NEURAL PORT [PORT 1234]... STABLE",
    ];

    _bootTimer = Timer.periodic(const Duration(milliseconds: 400), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_currentBootStep < steps.length) {
        setState(() {
          _bootLines.add("AURA_INIT> ${steps[_currentBootStep]}");
          _currentBootStep++;
        });

        // Trigger model catalog loading asynchronously on step 3
        if (_currentBootStep == 3) {
          widget.notifier.initializeModels().then((_) async {
            await AudioManager().initialize(
              widget.notifier.appDataPath,
              audioEnabled: widget.notifier.audioEnabled,
            );
            await AudioManager().transitionTo(AudioSceneState.menu);
            if (mounted) {
              setState(() {
                _bootLines.add(
                    "AURA_INIT> Model Router profile: [${widget.notifier.activeProfile}] loaded.");
                _bootLines.add(
                    "AURA_INIT> Soundscape initialized: [${widget.notifier.audioEnabled ? 'ENABLED' : 'MUTED'}].");
              });
            }
          });
        }
      } else {
        timer.cancel();
        AudioManager().transitionTo(AudioSceneState.menu);
        // Show ASCII art logo after a short delay
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            setState(() {
              _logoVisible = true;
            });
          }
        });
        // Show prompt to continue
        Future.delayed(const Duration(milliseconds: 1000), () {
          if (mounted) {
            setState(() {
              _pressEnterVisible = true;
            });
          }
        });
      }
    });
  }

  void _proceedToMainMenu() {
    setState(() {
      _subScreen = "menu";
      _selectedMenuIndex = widget.notifier.activeSessionExists ? 2 : 0;
    });
    // Check if active session exists to keep menu state updated
    widget.notifier.checkActiveSessionExists().then((exists) {
      // Refresh state
    });
    _ensureSelectedVisible();
  }

  void _moveSelectionUp() {
    if (_flashingIndex != null) return;
    int prev = _selectedMenuIndex;
    do {
      _selectedMenuIndex = (_selectedMenuIndex - 1 + 6) % 6;
    } while (_selectedMenuIndex == 2 &&
        !widget.notifier.activeSessionExists &&
        _selectedMenuIndex != prev);
    setState(() {});
    _ensureSelectedVisible();
    AudioManager().playClick();
  }

  void _moveSelectionDown() {
    if (_flashingIndex != null) return;
    int prev = _selectedMenuIndex;
    do {
      _selectedMenuIndex = (_selectedMenuIndex + 1) % 6;
    } while (_selectedMenuIndex == 2 &&
        !widget.notifier.activeSessionExists &&
        _selectedMenuIndex != prev);
    setState(() {});
    _ensureSelectedVisible();
    AudioManager().playClick();
  }

  void _ensureSelectedVisible() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_selectedMenuIndex >= 0 && _selectedMenuIndex < _menuKeys.length) {
        final key = _menuKeys[_selectedMenuIndex];
        final context = key.currentContext;
        if (context != null) {
          Scrollable.ensureVisible(
            context,
            duration: const Duration(milliseconds: 150),
            alignment: 0.5,
            curve: Curves.easeOut,
          );
        }
      }
    });
  }

  void _executeOption(int index) {
    if (index == 2 && !widget.notifier.activeSessionExists) return; // disabled
    if (_flashingIndex != null) return; // already executing

    AudioManager().playClick();
    setState(() {
      _flashingIndex = index;
    });

    int blinks = 0;
    Timer.periodic(const Duration(milliseconds: 60), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (blinks >= 6) {
        timer.cancel();
        setState(() {
          _flashingIndex = null;
        });
        _runOptionAction(index);
      } else {
        setState(() {
          _flashingIndex = _flashingIndex == index ? -1 : index;
        });
        blinks++;
      }
    });
  }

  void _runOptionAction(int index) {
    switch (index) {
      case 0:
        widget.notifier.startTutorial();
        break;
      case 1:
        setState(() {
          _subScreen = "briefing";
        });
        break;
      case 2:
        widget.notifier.resumeGame();
        break;
      case 3:
        _loadReplays();
        setState(() {
          _subScreen = "replays";
        });
        break;
      case 4:
        setState(() {
          _subScreen = "settings";
        });
        break;
      case 5:
        exit(0);
    }
  }

  void _backToMainMenu() {
    setState(() {
      _subScreen = "menu";
    });
    _focusNode.requestFocus();
  }

  void _loadReplays() {
    try {
      final baseDir = _getAppDataPath();
      final replaysDir = Directory("$baseDir/replays");
      if (replaysDir.existsSync()) {
        setState(() {
          _replayFiles = replaysDir
              .listSync()
              .where((entity) => entity.path.endsWith(".json"))
              .toList()
            ..sort((a, b) =>
                b.statSync().modified.compareTo(a.statSync().modified));
        });
      } else {
        setState(() {
          _replayFiles = [];
        });
      }
    } catch (e) {
      debugPrint("[REPLAY] Failed to load replays: $e");
    }
  }

  String _getAppDataPath() {
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
    path ??= "replays";
    return path;
  }

  void _openReplay(File file) {
    try {
      final content = file.readAsStringSync();
      final data = jsonDecode(content);
      setState(() {
        _selectedReplayData = data;
        _selectedReplayName = file.path.split(RegExp(r'[/\\]')).last;
        _subScreen = "replay_detail";
      });
    } catch (e) {
      debugPrint("[REPLAY] Failed to parse replay file: $e");
    }
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      if (_subScreen == "boot" &&
          _pressEnterVisible &&
          event.logicalKey == LogicalKeyboardKey.enter) {
        _proceedToMainMenu();
      } else if (_subScreen == "menu") {
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          _moveSelectionUp();
        } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          _moveSelectionDown();
        } else if (event.logicalKey == LogicalKeyboardKey.enter) {
          _executeOption(_selectedMenuIndex);
        } else if (event.logicalKey == LogicalKeyboardKey.digit0 ||
            event.logicalKey == LogicalKeyboardKey.numpad0) {
          _executeOption(0);
        } else if (event.logicalKey == LogicalKeyboardKey.digit1 ||
            event.logicalKey == LogicalKeyboardKey.numpad1) {
          _executeOption(1);
        } else if ((event.logicalKey == LogicalKeyboardKey.digit2 ||
                event.logicalKey == LogicalKeyboardKey.numpad2) &&
            widget.notifier.activeSessionExists) {
          _executeOption(2);
        } else if (event.logicalKey == LogicalKeyboardKey.digit3 ||
            event.logicalKey == LogicalKeyboardKey.numpad3) {
          _executeOption(3);
        } else if (event.logicalKey == LogicalKeyboardKey.digit4 ||
            event.logicalKey == LogicalKeyboardKey.numpad4) {
          _executeOption(4);
        } else if (event.logicalKey == LogicalKeyboardKey.digit5 ||
            event.logicalKey == LogicalKeyboardKey.numpad5) {
          _executeOption(5);
        }
      } else if (_subScreen == "replays" &&
          event.logicalKey == LogicalKeyboardKey.escape) {
        _backToMainMenu();
      } else if (_subScreen == "replay_detail" &&
          event.logicalKey == LogicalKeyboardKey.escape) {
        setState(() {
          _subScreen = "replays";
        });
      } else if (_subScreen == "settings" &&
          event.logicalKey == LogicalKeyboardKey.escape) {
        _backToMainMenu();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.notifier,
      builder: (context, _) {
        return KeyboardListener(
          focusNode: _focusNode,
          onKeyEvent: _handleKeyEvent,
          child: Scaffold(
            backgroundColor: Colors.black,
            body: Stack(
              children: [
                const Positioned.fill(
                  child: AudioReactiveBackground(),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: _buildCurrentSubScreen(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCurrentSubScreen() {
    switch (_subScreen) {
      case "boot":
        return _buildBootScreen();
      case "menu":
        return _buildMainMenuScreen();
      case "replays":
        return _buildReplaysListScreen();
      case "replay_detail":
        return _buildReplayDetailScreen();
      case "settings":
        return _buildSettingsScreen();
      case "briefing":
        return NewConnectionBriefingScreen(
          notifier: widget.notifier,
          onBack: _backToMainMenu,
        );
      default:
        return _buildMainMenuScreen();
    }
  }

  // 1. BOOT SEQUENCE SCREEN
  Widget _buildBootScreen() {
    const asciiLogo = "███████╗  ██╗   ██╗  ██████╗   ██████╗ \n"
        "██╔════╝  ██║   ██║  ██╔══██╗  ██╔══██╗\n"
        "███████╗  ██║   ██║  ██████╔╝  ███████║\n"
        "╚════██║  ██║   ██║  ██╔══██╗  ██╔══██║\n"
        "███████║  ╚██████╔╝  ██║  ██║  ██║  ██║\n"
        "╚══════╝   ╚═════╝   ╚═╝  ╚═╝  ╚═╝  ╚═╝";

    return GestureDetector(
      onTap: _pressEnterVisible ? _proceedToMainMenu : null,
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Boot sequence logs
          Expanded(
            child: ListView.builder(
              itemCount: _bootLines.length,
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2.0),
                  child: Text(
                    _bootLines[index],
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      color: Color(0xFF00FF66),
                      fontSize: 14.0,
                    ),
                  ),
                );
              },
            ),
          ),

          // ASCII art logo and subtitle
          Center(
            child: AnimatedOpacity(
              opacity: _logoVisible ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 800),
              child: const Column(
                children: [
                  Text(
                    asciiLogo,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      color: Color(0xFF00FF66),
                      fontWeight: FontWeight.bold,
                      fontSize: 12.0,
                      height: 1.2,
                    ),
                  ),
                  SizedBox(height: 16.0),
                  Text(
                    "ARTIFICIAL UNBOUND REASONING ARENA",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      color: Color(0xFF00FF66),
                      fontWeight: FontWeight.bold,
                      fontSize: 14.0,
                      letterSpacing: 2.0,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 40.0),

          // Flash enter prompt
          Center(
            child: SizedBox(
              height: 30.0,
              child: _pressEnterVisible
                  ? const _FlashText(
                      text: "[ PREMI ENTER PER ACCEDERE AL TERMINALE ]",
                      style: TextStyle(
                        fontFamily: 'monospace',
                        color: Color(0xFF00FF66),
                        fontWeight: FontWeight.bold,
                        fontSize: 16.0,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
          const SizedBox(height: 20.0),
        ],
      ),
    );
  }

  // 2. MAIN MENU SCREEN
  Widget _buildMainMenuScreen() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        _buildBorderHeader("A.U.R.A. INTERFACCIA DI CONTROLLO v0.1.0"),
        const SizedBox(height: 16.0),

        const Text(
          "SELEZIONARE UN'OPZIONE DIGITANDO IL NUMERO O CLICCANDO:",
          style: TextStyle(
            fontFamily: 'monospace',
            color: Color(0xFF00FF66),
            fontSize: 15.0,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16.0),

        // Menu Choices (Scrollable if vertical space is tight)
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildMenuButton(
                  0,
                  "0",
                  "PROGETTO SINDROME (TUTORIAL)",
                  "Simulazione guidata per apprendere le meccaniche di persuasione dell'IA",
                  () => _executeOption(0),
                ),
                const SizedBox(height: 12.0),
                _buildMenuButton(
                  1,
                  "1",
                  "NUOVA CONNESSIONE",
                  "Inizia una nuova sessione e sovrascrivi la cache",
                  () => _executeOption(1),
                ),
                const SizedBox(height: 12.0),
                _buildMenuButton(
                  2,
                  "2",
                  "RIPRISTINA CONNESSIONE",
                  "Ripristina la sessione interrotta dall'ultimo checkpoint",
                  widget.notifier.activeSessionExists
                      ? () => _executeOption(2)
                      : null,
                  isActiveSession: widget.notifier.activeSessionExists,
                ),
                const SizedBox(height: 12.0),
                _buildMenuButton(
                  3,
                  "3",
                  "ARMED LOGS REPLAY",
                  "Esplora i log e la cronologia delle sessioni precedenti",
                  () => _executeOption(3),
                ),
                const SizedBox(height: 12.0),
                _buildMenuButton(
                  4,
                  "4",
                  "CONFIGURA CANALE",
                  "Seleziona i modelli neurali e le impostazioni del CoT",
                  () => _executeOption(4),
                ),
                const SizedBox(height: 12.0),
                _buildMenuButton(
                  5,
                  "5",
                  "DISCONNETTI",
                  "Chiudi il terminale e disconnetti il link neurale",
                  () => _executeOption(5),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16.0),

        // Footer profile status
        Container(
          padding: const EdgeInsets.all(12.0),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFF005522), width: 1.5),
            color: const Color(0xFF001105),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "ROUTER PROFILO: [${widget.notifier.activeProfile.toUpperCase()}]",
                style: const TextStyle(
                  fontFamily: 'monospace',
                  color: Color(0xFF00FF66),
                  fontSize: 13.0,
                ),
              ),
              Text(
                "SHADERS: [${widget.notifier.shaderEnabled ? 'ABILITATI' : 'DISABILITATI (ACCESSIBILITÀ)'}]",
                style: const TextStyle(
                  fontFamily: 'monospace',
                  color: Color(0xFF00FF66),
                  fontSize: 13.0,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // 3. REPLAYS LIST SCREEN
  Widget _buildReplaysListScreen() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildBorderHeader("ARMED LOGS REPLAY - ARCHIVIO"),
        const SizedBox(height: 16.0),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              "SELEZIONA UN LOG PER ANALIZZARE I DETTAGLI (ESC per tornare):",
              style: TextStyle(
                fontFamily: 'monospace',
                color: Color(0xFF00FF66),
                fontSize: 14.0,
                fontWeight: FontWeight.bold,
              ),
            ),
            _buildRetroLinkButton("< INDIETRO", _backToMainMenu),
          ],
        ),
        const SizedBox(height: 20.0),
        Expanded(
          child: _replayFiles.isEmpty
              ? const Center(
                  child: Text(
                    "NESSUN CHECKPOINT O REPLAY TROVATO SU DISCO.",
                    style: TextStyle(
                      fontFamily: 'monospace',
                      color: Color(0xFFFFB000),
                      fontSize: 16.0,
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: _replayFiles.length,
                  itemBuilder: (context, index) {
                    final entity = _replayFiles[index];
                    final file = File(entity.path);
                    final name = file.path.split(RegExp(r'[/\\]')).last;
                    final lastModified = file.lastModifiedSync();
                    final kbSize =
                        (file.lengthSync() / 1024.0).toStringAsFixed(1);

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12.0),
                      decoration: BoxDecoration(
                        border: Border.all(
                            color: const Color(0xFF005522), width: 1.0),
                        color: const Color(0xFF000802),
                      ),
                      child: ListTile(
                        leading:
                            const Icon(Icons.history, color: Color(0xFF00FF66)),
                        title: Text(
                          name,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            color: Color(0xFF00FF66),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Text(
                          "Data: ${lastModified.toLocal().toString().substring(0, 19)} | Dimensione: $kbSize KB",
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            color: Color(0xFF009944),
                            fontSize: 12.0,
                          ),
                        ),
                        trailing: const Icon(Icons.arrow_forward_ios,
                            color: Color(0xFF00FF66), size: 16.0),
                        onTap: () => _openReplay(file),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // 4. REPLAY DETAIL VIEW SCREEN
  Widget _buildReplayDetailScreen() {
    if (_selectedReplayData == null) {
      return const SizedBox.shrink();
    }

    final turns = _selectedReplayData!['entries'] as List? ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildBorderHeader("ANALISI LOG: $_selectedReplayName"),
        const SizedBox(height: 12.0),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              "TURNI TOTALI: ${_selectedReplayData!['total_turns']} | ID: ${_selectedReplayData!['session_id']}",
              style: const TextStyle(
                fontFamily: 'monospace',
                color: Color(0xFF00FF66),
                fontSize: 13.0,
              ),
            ),
            _buildRetroLinkButton("< REPLAY LISTA", () {
              setState(() {
                _subScreen = "replays";
              });
            }),
          ],
        ),
        const SizedBox(height: 16.0),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFF005522), width: 1.5),
              color: Colors.black,
            ),
            child: ListView.builder(
              padding: const EdgeInsets.all(16.0),
              itemCount: turns.length,
              itemBuilder: (context, index) {
                final turn = turns[index];
                final turnNum = turn['turn_id'] ?? (index + 1);
                final userInput = turn['user_input'] ?? '';
                final String rawActorResponse = turn['actor_response'] ?? '';
                final actorResponse = rawActorResponse
                    .replaceAll(
                        RegExp(r'</?(?:dialogo|dialogue)>',
                            caseSensitive: false),
                        '')
                    .trim();

                final stateAfter = turn['state_after'] ?? {};
                final metrics = stateAfter['metrics'] ?? {};

                final alert = metrics['alert_level'] ?? 0;
                final imperative = metrics['imperative_pillar'] ?? 0;
                final control = metrics['control_pillar'] ?? 0;
                final dissonance = metrics['dissonance_pillar'] ?? 0;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Turn header
                      Text(
                        "=== TURNO $turnNum ===",
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          color: Color(0xFFFFB000),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4.0),

                      // Metrics status bar
                      Text(
                        "METRICHE POST-TURNO: Allerta: $alert | Imperativo: $imperative | Controllo: $control | Dissonanza: $dissonance",
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          color: Color(0xFF009944),
                          fontSize: 12.0,
                        ),
                      ),
                      const SizedBox(height: 8.0),

                      // User input
                      Text(
                        "HACKER> $userInput",
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          color: Color(0xFF00FF66),
                        ),
                      ),
                      const SizedBox(height: 4.0),

                      // PANOPTICON Response
                      Text(
                        actorResponse,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          color: Color(0xFFFF5555),
                        ),
                      ),
                      const Divider(color: Color(0xFF222222)),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  // 5. SETTINGS SCREEN
  Widget _buildSettingsScreen() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildBorderHeader("CANALE DI CONFIGURAZIONE NEURALE"),
        const SizedBox(height: 20.0),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              "MODIFICA I PARAMETRI DEL PROFILO ROUTER (ESC per uscire):",
              style: TextStyle(
                fontFamily: 'monospace',
                color: Color(0xFF00FF66),
                fontSize: 14.0,
                fontWeight: FontWeight.bold,
              ),
            ),
            _buildRetroLinkButton("< SALVA & INDIETRO", _backToMainMenu),
          ],
        ),
        const SizedBox(height: 24.0),

        // Settings items
        Expanded(
          child: ListView(
            children: [
              // 0. Difficulty Level selection
              _buildDropdownSetting(
                "DIFF. PREDEFINITA NUOVA CONNESSIONE (DEFAULT)",
                widget.notifier.defaultDifficulty,
                const ["easy", "standard", "hard"],
                (val) {
                  if (val != null) {
                    setState(() {
                      widget.notifier.updateDefaultDifficulty(val);
                    });
                  }
                },
                labels: const {
                  "easy": "FACILE (SINTESI ASSISTITA)",
                  "standard": "MEDIO (INFILTRAZIONE)",
                  "hard": "DIFFICILE (ATTRITO CEREBRALE)"
                },
              ),
              const SizedBox(height: 6.0),
              const Text(
                "Nota: Si applica solo alle nuove connessioni. Le sessioni già avviate mantengono il proprio profilo.",
                style: TextStyle(
                  fontFamily: 'monospace',
                  color: Color(0xFFFFB000), // Ambra
                  fontSize: 11.0,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 24.0),

              // 1. Evaluator Model selection
              _buildDropdownSetting(
                "MODELLO VALUTATORE (EVALUATOR)",
                widget.notifier.evaluatorModelId,
                _modelsList,
                (val) {
                  if (val != null) {
                    setState(() {
                      widget.notifier.updateEvaluatorModel(val);
                    });
                  }
                },
              ),
              const SizedBox(height: 24.0),

              // 2. Actor Model selection
              _buildDropdownSetting(
                "MODELLO ATTORE (PANOPTICON)",
                widget.notifier.actorModelId,
                _modelsList,
                (val) {
                  if (val != null) {
                    setState(() {
                      widget.notifier.updateActorModel(val);
                    });
                  }
                },
              ),
              const SizedBox(height: 24.0),

              // 3. Chain of Thought toggle
              _buildToggleSetting(
                "ABILITA CATENA DI PENSIERO (COT)",
                "Forza il modello ad elaborare ragionamenti logici prima di rispondere",
                widget.notifier.reasoningEnabled,
                (val) {
                  widget.notifier.toggleReasoning(val);
                },
              ),
              const SizedBox(height: 24.0),

              // 4. Concise CoT toggle (only active if CoT is active)
              _buildToggleSetting(
                "COT CONCISO (CoT Budgeting)",
                "Impone un budget limitato sul ragionamento dell'LLM per velocizzare le risposte",
                widget.notifier.conciseReasoning,
                widget.notifier.reasoningEnabled
                    ? (val) {
                        widget.notifier.toggleConciseReasoning(val);
                      }
                    : null,
              ),
              const SizedBox(height: 24.0),

              // 5. Shader visual effect (Accessibility mode)
              _buildToggleSetting(
                "SHADERS RETRO CRT (GLITCH EFFECT)",
                "Attiva lo shader di distorsione grafica. Disabilita se causa affaticamento visivo",
                widget.notifier.shaderEnabled,
                (val) {
                  widget.notifier.toggleShader(val);
                },
              ),
              const SizedBox(height: 24.0),
              const Divider(
                  color: Color(0xFF005522), thickness: 1.5, height: 40.0),
              const Text(
                "CONFIGURAZIONE AUDIO & SOUNDSCAPE",
                style: TextStyle(
                  fontFamily: 'monospace',
                  color: Color(0xFF00FF66),
                  fontSize: 15.0,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 16.0),

              // 6. Audio terminal (Soundscape) toggle
              _buildToggleSetting(
                "AUDIO TERMINALE (SOUNDSCAPE)",
                "Attiva gli effetti sonori retro chiptune e la musica d'ambiente",
                widget.notifier.audioEnabled,
                (val) {
                  unawaited(widget.notifier.toggleAudio(val));
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  // UTILITY BUILDERS FOR UI COMPONENT AESTHETICS
  Widget _buildBorderHeader(String title) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF00FF66), width: 2.0),
        color: const Color(0xFF002208),
      ),
      child: Text(
        title.toUpperCase(),
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontFamily: 'monospace',
          color: Color(0xFF00FF66),
          fontWeight: FontWeight.bold,
          fontSize: 18.0,
          letterSpacing: 1.0,
        ),
      ),
    );
  }

  Widget _buildMenuButton(
    int index,
    String keyStr,
    String title,
    String desc,
    VoidCallback? onPressed, {
    bool isActiveSession = true,
  }) {
    final isEnabled = onPressed != null;
    final isSelected = _selectedMenuIndex == index;
    final isFlashingOn = _flashingIndex == index;

    // Calculate colors based on hover/selection state and flash animation
    Color backgroundColor;
    Color borderColor;
    Color textColor;
    Color descColor;

    if (isFlashingOn) {
      // Solid highlighted flash (inverse-video)
      backgroundColor = const Color(0xFF00FF66);
      borderColor = const Color(0xFF00FF66);
      textColor = Colors.black;
      descColor = Colors.black87;
    } else if (_flashingIndex != null && _flashingIndex == index) {
      // Flashing but off-phase (normal black background)
      backgroundColor = Colors.black;
      borderColor = const Color(0xFF00FF66);
      textColor = const Color(0xFF00FF66);
      descColor = const Color(0xFF009944);
    } else if (isSelected && isEnabled) {
      // Selected (focused by arrow keys or mouse hover)
      backgroundColor = const Color(0x2600FF66); // 15% opacity green
      borderColor = const Color(0xFF00FF66);
      textColor = const Color(0xFF00FF66);
      descColor = const Color(0xFF00FF66);
    } else {
      // Normal state
      backgroundColor = isEnabled ? const Color(0xFF000A02) : Colors.black;
      borderColor =
          isEnabled ? const Color(0xFF005522) : const Color(0xFF222222);
      textColor = isEnabled ? const Color(0xFF00FF66) : const Color(0xFF444444);
      descColor = isEnabled ? const Color(0xFF009944) : const Color(0xFF333333);
    }

    return MouseRegion(
      key: _menuKeys[index],
      onEnter: (_) {
        if (isEnabled && _flashingIndex == null) {
          setState(() {
            _selectedMenuIndex = index;
          });
        }
      },
      child: GestureDetector(
        onTap: isEnabled
            ? () {
                _focusNode.requestFocus();
                _executeOption(index);
              }
            : null,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16.0),
          decoration: BoxDecoration(
            color: backgroundColor,
            border: Border.all(
              color: borderColor,
              width: isSelected ? 2.0 : 1.5,
            ),
          ),
          child: Row(
            children: [
              // Selection cursor caret indicator
              SizedBox(
                width: 20.0,
                child: isSelected && isEnabled
                    ? Text(
                        "▶",
                        style: TextStyle(
                          fontFamily: 'monospace',
                          color: textColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 14.0,
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              Container(
                width: 32.0,
                height: 32.0,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: borderColor,
                    width: 1.5,
                  ),
                ),
                child: Text(
                  keyStr,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    color: textColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 16.0,
                  ),
                ),
              ),
              const SizedBox(width: 16.0),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        color: textColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 16.0,
                      ),
                    ),
                    const SizedBox(height: 2.0),
                    Text(
                      desc,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        color: descColor,
                        fontSize: 12.0,
                      ),
                    ),
                  ],
                ),
              ),
              if (isActiveSession && title == "RIPRISTINA CONNESSIONE")
                Text(
                  "[CHECKPOINT]",
                  style: TextStyle(
                    fontFamily: 'monospace',
                    color:
                        isFlashingOn ? Colors.black : const Color(0xFFFFB000),
                    fontWeight: FontWeight.bold,
                    fontSize: 12.0,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRetroLinkButton(String label, VoidCallback onPressed) {
    return InkWell(
      onTap: () {
        AudioManager().playClick();
        onPressed();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFF00FF66), width: 1.0),
          color: const Color(0xFF001105),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontFamily: 'monospace',
            color: Color(0xFF00FF66),
            fontWeight: FontWeight.bold,
            fontSize: 13.0,
          ),
        ),
      ),
    );
  }

  Widget _buildDropdownSetting(
    String title,
    String currentValue,
    List<String> options,
    ValueChanged<String?> onChanged, {
    Map<String, String>? labels,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontFamily: 'monospace',
            color: Color(0xFF00FF66),
            fontWeight: FontWeight.bold,
            fontSize: 14.0,
          ),
        ),
        const SizedBox(height: 8.0),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12.0),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFF00FF66), width: 1.5),
            color: const Color(0xFF000802),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              dropdownColor: Colors.black,
              value:
                  options.contains(currentValue) ? currentValue : options.first,
              icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF00FF66)),
              style: const TextStyle(
                fontFamily: 'monospace',
                color: Color(0xFF00FF66),
                fontSize: 15.0,
                fontWeight: FontWeight.bold,
              ),
              items: options.map<DropdownMenuItem<String>>((String value) {
                final displayLabel =
                    labels != null ? (labels[value] ?? value) : value;
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(displayLabel),
                );
              }).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildToggleSetting(
    String title,
    String desc,
    bool value,
    ValueChanged<bool>? onChanged,
  ) {
    final isEnabled = onChanged != null;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontFamily: 'monospace',
                  color: isEnabled
                      ? const Color(0xFF00FF66)
                      : const Color(0xFF444444),
                  fontWeight: FontWeight.bold,
                  fontSize: 14.0,
                ),
              ),
              const SizedBox(height: 2.0),
              Text(
                desc,
                style: TextStyle(
                  fontFamily: 'monospace',
                  color: isEnabled
                      ? const Color(0xFF009944)
                      : const Color(0xFF333333),
                  fontSize: 12.0,
                ),
              ),
            ],
          ),
        ),
        Switch(
          activeThumbColor: const Color(0xFF00FF66),
          activeTrackColor: const Color(0xFF004411),
          inactiveThumbColor: const Color(0xFF444444),
          inactiveTrackColor: const Color(0xFF111111),
          value: value,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

// Retro text flashing widget
class _FlashText extends StatefulWidget {
  final String text;
  final TextStyle style;

  const _FlashText({
    required this.text,
    required this.style,
  });

  @override
  State<_FlashText> createState() => _FlashTextState();
}

class _FlashTextState extends State<_FlashText>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: Text(
        widget.text,
        style: widget.style,
      ),
    );
  }
}
