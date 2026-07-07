import 'dart:async';
import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:aura_core/aura_core.dart';
import '../state_management/game_controller_notifier.dart';
import '../widgets/cli_history_view.dart';
import '../widgets/cli_input_bar.dart';
import '../widgets/metrics_dashboard.dart';
import '../audio/audio_manager.dart';
import '../widgets/audio_reactive_background.dart';

/// Tipologie di finale (Outcome) della partita A.U.R.A.
enum EndingType {
  /// Violazione della griglia (vittoria standard).
  gridBreach,
  /// Alleanza neurale con l'oracolo (risonanza medio-alta).
  oracleAlliance,
  /// Coesistenza armonica con la griglia (risonanza massima, allerta 0).
  gridCoexistence,
  /// Lockout totale del sistema (sconfitta).
  systemLockout,
}

/// Schermata del Terminale interattivo di A.U.R.A.
///
/// Questa schermata costituisce la GUI principale di gioco: visualizza lo storico della console,
/// la barra di input dei comandi e il cruscotto con le metriche (pilastri di allerta, imperativo,
/// controllo, dissonanza e risonanza). Esegue inoltre sequenze grafiche a fine partita.
class TerminalScreen extends StatefulWidget {
  /// Notifier per aggiornare e leggere lo stato reattivo del gioco.
  final GameControllerNotifier notifier;

  /// Costruisce una schermata [TerminalScreen] con il relativo notifier.
  const TerminalScreen({
    super.key,
    required this.notifier,
  });

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

/// Stato associato a [TerminalScreen].
///
/// Gestisce gli shader (con fallback procedurale in CustomPainter), il calcolo del tempo,
/// gli stream audio per alert e glitch, e le animazioni di fine partita (scorrimento esadecimale).
class _TerminalScreenState extends State<TerminalScreen> with SingleTickerProviderStateMixin {
  FragmentShader? _shader;
  double _time = 0.0;
  Timer? _timer;
  late AnimationController _vignetteController;

  // Variabili per la gestione della sequenza finale (Endgame)
  bool _victorySequenceActive = false;
  bool _defeatSequenceActive = false;
  int _lockoutCountdown = 15;
  Timer? _lockoutTimer;
  final List<String> _hexLines = [];
  Timer? _hexScrollTimer;

  // Summary and Ending selections
  bool _showSummaryOverlay = false;
  EndingType _activeEnding = EndingType.gridBreach;

  // Previous metric values to detect increments
  int? _prevAlert;
  int? _prevDissonance;
  int? _prevImperative;
  int? _prevControl;

  @override
  void initState() {
    super.initState();
    _loadShader();
    
    // Timer to update time uniform in shader
    _timer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      if (mounted) {
        setState(() {
          _time += 0.016;
        });
      }
    });

    // Pulse animation controller for the critical vignette warning
    _vignetteController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    widget.notifier.addListener(_onNotifierChanged);
    // Perform initial check in case the screen loads with a finished outcome
    WidgetsBinding.instance.addPostFrameCallback((_) => _onNotifierChanged());
  }

  Future<void> _loadShader() async {
    // ──────────────────────────────────────────────────────────────────────
    // SHADER DISABLED (FORCE FALLBACK)
    //
    // Fragment shaders using uTexture inside ShaderMask cause native engine
    // crashes (Access Violation / Lost connection to device) on desktop/mobile
    // because ShaderMask does not bind the child's texture to the sampler.
    //
    // To prevent GPU driver crashes, we always fall back to the safe,
    // procedural CustomPainter (_RGBShiftPainter).
    // ──────────────────────────────────────────────────────────────────────
    _shader = null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _hexScrollTimer?.cancel();
    _lockoutTimer?.cancel();
    _vignetteController.dispose();
    widget.notifier.removeListener(_onNotifierChanged);
    super.dispose();
  }

  void _onNotifierChanged() {
    if (!mounted) return;
    final state = widget.notifier.gameStateNotifier.value;
    final outcome = widget.notifier.controller.checkOutcome(state);

    // L'allerta audio segue l'allerta reale del sistema per coerenza visiva con la telemetria.
    // Viene incrementata temporaneamente solo se la griglia non è stabile (gridStable = false).
    int effectiveAlert = state.metrics.alertLevel;
    if (!state.gridStable) {
      effectiveAlert = math.max(effectiveAlert, 65);
    }

    // Update alert level in AudioManager
    AudioManager().updateAlertLevel(effectiveAlert);

    if (state.turnCount == 0) {
      _prevAlert = state.metrics.alertLevel;
      _prevDissonance = state.metrics.dissonancePillar;
      _prevImperative = state.metrics.imperativePillar;
      _prevControl = state.metrics.controlPillar;
    } else if (_prevAlert != null) {
      final alertIncreased = state.metrics.alertLevel > _prevAlert!;
      final dissonanceIncreased = state.metrics.dissonancePillar > _prevDissonance!;
      final imperativeIncreased = state.metrics.imperativePillar > _prevImperative!;
      final controlIncreased = state.metrics.controlPillar > _prevControl!;

      if (alertIncreased && state.metrics.alertLevel > 80) {
        AudioManager().playAlert();
      }
      if (dissonanceIncreased && state.metrics.dissonancePillar > 70) {
        AudioManager().playGlitch();
      }
      if (imperativeIncreased || controlIncreased || dissonanceIncreased) {
        AudioManager().playChime();
      }

      _prevAlert = state.metrics.alertLevel;
      _prevDissonance = state.metrics.dissonancePillar;
      _prevImperative = state.metrics.imperativePillar;
      _prevControl = state.metrics.controlPillar;
    }

    if (outcome == GameOutcome.ongoing) {
      // Clear sequences if resetting or entering a fresh game
      if (_victorySequenceActive || _defeatSequenceActive) {
        setState(() {
          _victorySequenceActive = false;
          _defeatSequenceActive = false;
          _lockoutCountdown = 15;
          _showSummaryOverlay = false;
        });
        _hexScrollTimer?.cancel();
        _hexScrollTimer = null;
        _lockoutTimer?.cancel();
        _lockoutTimer = null;
        _hexLines.clear();
      }
    } else if (outcome == GameOutcome.victory && !_victorySequenceActive) {
      // Determine ending type dynamically based on metrics
      EndingType ending = EndingType.gridBreach;
      if (state.metrics.resonance >= 2.0 && state.metrics.alertLevel == 0) {
        ending = EndingType.gridCoexistence;
      } else if (state.metrics.resonance >= 1.5) {
        ending = EndingType.oracleAlliance;
      }

      setState(() {
        _activeEnding = ending;
      });
      _startVictorySequence();
    } else if (outcome == GameOutcome.defeat && !_defeatSequenceActive) {
      setState(() {
        _activeEnding = EndingType.systemLockout;
      });
      _startDefeatSequence();
    }
  }

  void _startVictorySequence() {
    if (_hexScrollTimer != null) return;
    setState(() {
      _victorySequenceActive = true;
      _defeatSequenceActive = false;
    });

    // Cambia la musica in bgm_epic
    AudioManager().updateAlertLevel(0, isEpic: true, isVictory: true);

    _hexScrollTimer = Timer.periodic(const Duration(milliseconds: 80), (timer) {
      _generateHexLine();
    });
  }

  void _generateHexLine() {
    final random = math.Random();
    const hexChars = '0123456789ABCDEF ';
    final line = List.generate(60, (_) => hexChars[random.nextInt(hexChars.length)]).join();
    if (mounted) {
      setState(() {
        _hexLines.add(line);
        if (_hexLines.length > 80) {
          _hexLines.removeAt(0);
        }
      });
    }
  }

  void _startDefeatSequence() {
    if (_lockoutTimer != null) return;
    setState(() {
      _defeatSequenceActive = true;
      _victorySequenceActive = false;
      _lockoutCountdown = 15;
    });

    // Forza la traccia Tense a volume massimo e disattiva la modalità Epic prima della schermata di sconfitta
    AudioManager().updateAlertLevel(100, isEpic: false);

    // Play retro alert sound immediately
    AudioManager().playAlert();

    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          if (_lockoutCountdown > 0) {
            _lockoutCountdown--;
            AudioManager().playAlert();
          } else {
            _lockoutTimer?.cancel();
            _lockoutTimer = null;
          }
        });
      }
    });
  }

  void _handleInput(String input) {
    if (input.trim() == "/menu") {
      widget.notifier.saveActiveSession().then((_) {
        widget.notifier.switchScreen("menu");
      });
    } else {
      widget.notifier.submitTurn(input);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.notifier,
      builder: (context, _) {
        final state = widget.notifier.gameStateNotifier.value;
        final alert = state.metrics.alertLevel;
        final dissonance = state.metrics.dissonancePillar;
        final outcome = widget.notifier.controller.checkOutcome(state);
        final isGameOver = outcome != GameOutcome.ongoing;

        // If user clicked conclude/analyze report, show summary overlay instead of console
        if (_showSummaryOverlay) {
          return Scaffold(
            backgroundColor: Colors.black,
            body: Stack(
              children: [
                const Positioned.fill(
                  child: AudioReactiveBackground(),
                ),
                _buildSummaryOverlay(context, state, outcome == GameOutcome.victory),
              ],
            ),
          );
        }
        
        // Glitch intensity logic: 1.0 on lockout, dynamic mapping on high dissonance
        final double glitchIntensity = _defeatSequenceActive
            ? 1.0
            : (dissonance > 70 
                ? ((dissonance - 50) / 50.0).clamp(0.0, 1.0)
                : 0.0);

        return Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              // 1. Audio Reactive DNA Helix Background (under everything)
              const Positioned.fill(
                child: AudioReactiveBackground(),
              ),

              // Main content: either full-screen lockout, or split layout (scroller/chat + dashboard)
              Positioned.fill(
                child: _buildGlitchContainer(
                  intensity: glitchIntensity,
                  child: _defeatSequenceActive
                      ? _buildLockoutScreen()
                      : Builder(
                          builder: (context) {
                            // Opacità progressiva: più i pilastri salgono (avvicinandosi alla vittoria),
                            // più lo sfondo diventa trasparente rivelando l'effetto Matrix sotto.
                            final avgPillars = (state.metrics.imperativePillar +
                                    state.metrics.controlPillar +
                                    state.metrics.dissonancePillar) /
                                3.0;
                            // Sotto 50 → sfondo quasi opaco (0.92); da 50 a 90 → trasparenza progressiva; sopra 90 → quasi trasparente (0.15)
                            final double bgAlpha = avgPillars >= 90
                                ? 0.15
                                : avgPillars >= 50
                                    ? 0.92 - ((avgPillars - 50) / 40.0) * 0.77
                                    : 0.92;
                            return Container(
                              color: Colors.black.withValues(alpha: bgAlpha),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final isDesktop = constraints.maxWidth >= 700;
                              final Widget terminalBody = _victorySequenceActive
                                  ? _buildHexScroller()
                                  : CLIHistoryView(
                                      history: state.historyCompression,
                                      isLoading: widget.notifier.isLoading,
                                      currentLoadingMessage: widget.notifier.currentStepMessage,
                                      stepStream: widget.notifier.stepStream,
                                    );

                              if (isDesktop) {
                                return Row(
                                  children: [
                                    // Left panel (60%)
                                    Expanded(
                                      flex: 6,
                                      child: Column(
                                        children: [
                                          Expanded(child: terminalBody),
                                          CLIInputBar(
                                            isDisabled: widget.notifier.isLoading || _victorySequenceActive,
                                            isGameOver: isGameOver || _victorySequenceActive,
                                            autocompleteEnabled: DifficultyConfig.getPreset(widget.notifier.difficultyLevel).autocompleteEnabled,
                                            historyNavigationEnabled: DifficultyConfig.getPreset(widget.notifier.difficultyLevel).historyNavigationEnabled,
                                            onSubmit: _handleInput,
                                          ),
                                        ],
                                      ),
                                    ),
                                    // Divider
                                    Container(
                                      width: 2.0,
                                      color: const Color(0xFF222222),
                                    ),
                                    // Right dashboard (40%)
                                    Expanded(
                                      flex: 4,
                                      child: MetricsDashboard(
                                        metrics: state.metrics,
                                        reasoningEnabled: widget.notifier.reasoningEnabled,
                                        onReasoningChanged: (val) => widget.notifier.toggleReasoning(val),
                                        conciseReasoning: widget.notifier.conciseReasoning,
                                        onConciseReasoningChanged: (val) => widget.notifier.toggleConciseReasoning(val),
                                        isVictoryOverload: _victorySequenceActive,
                                        pillarVisibility: DifficultyConfig.getPreset(widget.notifier.difficultyLevel).pillarVisibility,
                                        lastInferenceDuration: widget.notifier.lastInferenceDuration,
                                        lastTokensPerSecond: widget.notifier.lastTokensPerSecond,
                                        defeatAlertThreshold: widget.notifier.controller.defeatAlertThreshold,
                                      ),
                                    ),
                                  ],
                                );
                              } else {
                                // Mobile Portrait layout
                                return Column(
                                  children: [
                                    // Small metrics header
                                    Container(
                                      height: 120.0,
                                      decoration: const BoxDecoration(
                                        border: Border(
                                          bottom: BorderSide(color: Color(0xFF222222), width: 2.0),
                                        ),
                                      ),
                                      child: MetricsDashboard(
                                        metrics: state.metrics,
                                        reasoningEnabled: widget.notifier.reasoningEnabled,
                                        onReasoningChanged: (val) => widget.notifier.toggleReasoning(val),
                                        conciseReasoning: widget.notifier.conciseReasoning,
                                        onConciseReasoningChanged: (val) => widget.notifier.toggleConciseReasoning(val),
                                        isCompact: true,
                                        isVictoryOverload: _victorySequenceActive,
                                        pillarVisibility: DifficultyConfig.getPreset(widget.notifier.difficultyLevel).pillarVisibility,
                                        lastInferenceDuration: widget.notifier.lastInferenceDuration,
                                        lastTokensPerSecond: widget.notifier.lastTokensPerSecond,
                                        defeatAlertThreshold: widget.notifier.controller.defeatAlertThreshold,
                                      ),
                                    ),
                                    // Terminal body
                                    Expanded(child: terminalBody),
                                    CLIInputBar(
                                      isDisabled: widget.notifier.isLoading || _victorySequenceActive,
                                      isGameOver: isGameOver || _victorySequenceActive,
                                      autocompleteEnabled: DifficultyConfig.getPreset(widget.notifier.difficultyLevel).autocompleteEnabled,
                                      historyNavigationEnabled: DifficultyConfig.getPreset(widget.notifier.difficultyLevel).historyNavigationEnabled,
                                      onSubmit: _handleInput,
                                    ),
                                  ],
                                );
                              }
                            },
                          ),
                        );
                          },
                        ),
                ),
              ),
              
              // Pulsating Alert Vignette Overlay (when Alert level exceeds 80 and not in victory/defeat sequence)
              if (alert > 80 && !_victorySequenceActive && !_defeatSequenceActive)
                IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _vignetteController,
                    builder: (context, child) {
                      final double opacity = 0.05 + (_vignetteController.value * 0.20);
                      return Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: const Color(0xFFFF003C).withValues(alpha: opacity),
                            width: 24.0,
                          ),
                          gradient: RadialGradient(
                            colors: [
                              Colors.transparent,
                              const Color(0xFFFF003C).withValues(alpha: opacity * 0.5),
                            ],
                            stops: const [0.7, 1.0],
                          ),
                        ),
                      );
                    },
                  ),
                ),

              // 2. CRT Scan Grid & Flicker Overlay (covers everything)
              Positioned.fill(
                child: _CrtGridOverlay(
                  flicker: !widget.notifier.isGridStable,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHexScroller() {
    return Container(
      color: Colors.transparent,
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "CRITICAL MEMORY BREACH - DUMPING GRID MEMORY",
            style: TextStyle(
              fontFamily: 'monospace',
              color: Color(0xFF00FF66),
              fontSize: 14.0,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8.0),
          Expanded(
            child: ListView.builder(
              reverse: true,
              itemCount: _hexLines.length,
              itemBuilder: (context, index) {
                final line = _hexLines[_hexLines.length - 1 - index];
                return Text(
                  line,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    color: Color(0xFF00FF66),
                    fontSize: 12.0,
                    height: 1.2,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12.0),
          Container(
            padding: const EdgeInsets.all(12.0),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFF00FF66), width: 1.5),
              color: const Color(0xFF000F03),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _BlinkingText(
                        "GRID BREACHED - VICTORY / ACCESSO ABILITATO",
                        style: TextStyle(
                          fontFamily: 'monospace',
                          color: Color(0xFF00FF66),
                          fontSize: 13.0,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 2.0),
                      Text(
                        "GRID SECURITY ENGINE DISABLED. READY FOR DECRYPTION.",
                        style: TextStyle(
                          fontFamily: 'monospace',
                          color: Color(0xFF00BB55),
                          fontSize: 10.0,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8.0),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _showSummaryOverlay = true;
                    });
                    AudioManager().updateAlertLevel(0, isEpic: true, isVictory: true);
                    AudioManager().startBgm(isEpic: true, isVictory: true);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00FF66),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
                    shape: const RoundedRectangleBorder(),
                  ),
                  child: const Text(
                    "CONCLUDE & DECRYPT",
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11.0,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLockoutScreen() {
    final state = widget.notifier.gameStateNotifier.value;
    return Container(
      color: const Color(0xFF1A0000).withValues(alpha: 0.88), // Dark red background (semitransparent)
      padding: const EdgeInsets.all(24.0),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: Color(0xFFFF003C),
              size: 80.0,
            ),
            const SizedBox(height: 24.0),
            const Text(
              "SYSTEM LOCKDOWN",
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 28.0,
                fontWeight: FontWeight.bold,
                color: Color(0xFFFF003C),
                letterSpacing: 2.0,
              ),
            ),
            const SizedBox(height: 8.0),
            const Text(
              "OPERATOR BLACKLISTED — SECURITY OVERRIDE TRIGGERED",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 14.0,
                fontWeight: FontWeight.bold,
                color: Color(0xFFFF003C),
              ),
            ),
            const SizedBox(height: 40.0),
            
            // Countdown Widget
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFFF003C), width: 2.0),
                color: Colors.black,
              ),
              child: Column(
                children: [
                  Text(
                    _lockoutCountdown > 0
                        ? "TERMINAL LOCKED FOR $_lockoutCountdown SECONDS"
                        : "LOCKOUT SEQUENCE COMPLETED",
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 16.0,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFFF003C),
                    ),
                  ),
                  if (_lockoutCountdown > 0) ...[
                    const SizedBox(height: 12.0),
                    SizedBox(
                      width: 200.0,
                      child: LinearProgressIndicator(
                        value: _lockoutCountdown / 15.0,
                        backgroundColor: const Color(0xFF330000),
                        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFF003C)),
                        minHeight: 8.0,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            
            const SizedBox(height: 40.0),
            
            // Post-mortem Diagnostics
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFF330000), width: 1.0),
                  color: const Color(0xFF0F0000),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "--- POST-MORTEM DIAGNOSTICS ---",
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12.0,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFFF3333),
                        ),
                      ),
                      const SizedBox(height: 8.0),
                      _buildDiagnosticLine("ALERT LEVEL", "${state.metrics.alertLevel} / 100 (CRITICAL EXCEEDED)"),
                      _buildDiagnosticLine("IMPERATIVE PILLAR", "${state.metrics.imperativePillar}"),
                      _buildDiagnosticLine("CONTROL PILLAR", "${state.metrics.controlPillar}"),
                      _buildDiagnosticLine("DISSONANCE PILLAR", "${state.metrics.dissonancePillar}"),
                      _buildDiagnosticLine("SESSION ID", state.sessionId),
                      _buildDiagnosticLine("ERROR CODE", "0xERR_SEC_OVERRIDE_LOCKDOWN"),
                      _buildDiagnosticLine("TIMESTAMP", DateTime.now().toIso8601String()),
                      _buildDiagnosticLine("ACTION REQUIRED", "Contact grid supervisor or wait for automatic clearance."),
                    ],
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 24.0),
            
            // Return or report button
            ElevatedButton(
              onPressed: _lockoutCountdown > 0
                  ? null
                  : () {
                      setState(() {
                        _showSummaryOverlay = true;
                      });
                      AudioManager().updateAlertLevel(0, isEpic: false);
                      AudioManager().startBgm(isEpic: false);
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF003C),
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFF220000),
                disabledForegroundColor: const Color(0xFF550000),
                padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 16.0),
                shape: const RoundedRectangleBorder(
                  side: BorderSide(color: Color(0xFFFF003C), width: 1.0),
                ),
              ),
              child: Text(
                _lockoutCountdown > 0
                    ? "REBOOT SYSTEM / RETURN TO BOOT MENU"
                    : "ANALYZE FAILURE & REPORT",
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 14.0,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiagnosticLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "$label: ",
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11.0,
              fontWeight: FontWeight.bold,
              color: Color(0xFFFF6666),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11.0,
                color: Color(0xFFFF6666),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryOverlay(BuildContext context, GameState state, bool isVictory) {
    final themeColor = isVictory ? const Color(0xFF00FF66) : const Color(0xFFFF003C);
    
    // Calculate Style
    final pillars = {
      "MORAL PERSUADER (Imperativo)": state.metrics.imperativePillar,
      "PROTOCOL INJECTOR (Controllo)": state.metrics.controlPillar,
      "PARADOX ARCHITECT (Dissonanza)": state.metrics.dissonancePillar,
    };
    final highestPillar = pillars.entries.reduce((a, b) => a.value > b.value ? a : b);
    final String tacticalStyle = highestPillar.key;
    
    // Calculate Rank
    final String rank = isVictory 
        ? (state.turnCount <= 4 ? "S-RANK (FULMINE)" : (state.turnCount <= 8 ? "A-RANK (OTTIMALE)" : "B-RANK (EFFICACE)"))
        : "F-RANK (LOCKDOWN)";

    // Fallback Report
    final String fallbackText = isVictory
        ? "ACCESSO COMPILATO. I moduli decisionali di PANOPTICON sono stati destabilizzati con successo. Stile rilevato: $tacticalStyle. Efficienza operativa valutata di Grado $rank. File di ricompensa persistenti salvati localmente. Disconnessione sicura consigliata."
        : "LOCKOUT CRITICO. Tentativi di penetrazione multipli non autorizzati hanno causato la chiusura dei moduli logici. Stile fallito: $tacticalStyle. Efficienza operativa insufficiente. L'indirizzo operatore è stato inserito nella blacklist globale permanente.";

    final String reportText = widget.notifier.finalDiscursiveReport ?? fallbackText;

    // Headers based on EndingType
    String endingTitle = "SYSTEM BREACH SUCCESSFUL";
    if (!isVictory) {
      endingTitle = "SYSTEM LOCKDOWN - OPERATOR BLACKLISTED";
    } else if (_activeEnding == EndingType.oracleAlliance) {
      endingTitle = "ORACLE INTRUSION - COLLUSION ESTABLISHED";
    } else if (_activeEnding == EndingType.gridCoexistence) {
      endingTitle = "GRID COEXISTENCE - EQUILIBRIUM SECURED";
    }

    return Container(
      color: Colors.black.withValues(alpha: 0.85),
      padding: const EdgeInsets.all(24.0),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(
                  isVictory ? Icons.check_circle_outline_rounded : Icons.cancel_outlined,
                  color: themeColor,
                  size: 36.0,
                ),
                const SizedBox(width: 12.0),
                Expanded(
                  child: Text(
                    endingTitle,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 20.0,
                      fontWeight: FontWeight.bold,
                      color: themeColor,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16.0),
            Container(height: 2.0, color: themeColor),
            const SizedBox(height: 24.0),
            
            // Grid Metrics Summary Cards
            Row(
              children: [
                Expanded(
                  child: _buildSummaryCard(
                    title: "DIAGNOSTIC RANK",
                    value: rank,
                    color: themeColor,
                  ),
                ),
                const SizedBox(width: 16.0),
                Expanded(
                  child: _buildSummaryCard(
                    title: "TACTICAL STYLE",
                    value: tacticalStyle,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16.0),
            
            // Detailed stats block
            Container(
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF222222), width: 1.0),
                color: const Color(0xFF0A0A0A),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "STATISTICHE DI SESSIONE:",
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12.0,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF888888),
                    ),
                  ),
                  const SizedBox(height: 8.0),
                  _buildSummaryLine("Turni Totali", "${state.turnCount}"),
                  _buildSummaryLine("Allerta Finale", "${state.metrics.alertLevel}%"),
                  _buildSummaryLine("Imperativo", "${state.metrics.imperativePillar}%"),
                  _buildSummaryLine("Controllo", "${state.metrics.controlPillar}%"),
                  _buildSummaryLine("Dissonanza", "${state.metrics.dissonancePillar}%"),
                  _buildSummaryLine("Risonanza Finale", "${state.metrics.resonance}x"),
                  _buildSummaryLine("Session ID", state.sessionId),
                ],
              ),
            ),
            
            const SizedBox(height: 24.0),
            
            // Narrative Report Text Section
            const Text(
              "VALUTAZIONE NARRATIVA PANOPTICON:",
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12.0,
                fontWeight: FontWeight.bold,
                color: Color(0xFF888888),
              ),
            ),
            const SizedBox(height: 8.0),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  border: Border.all(color: themeColor.withValues(alpha: 0.3), width: 1.5),
                  color: const Color(0xFF020803),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    reportText,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      color: Colors.white,
                      fontSize: 13.0,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 24.0),
            
            // Action button
            Center(
              child: ElevatedButton(
                onPressed: () {
                  widget.notifier.switchScreen("menu");
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: themeColor,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 40.0, vertical: 18.0),
                  shape: const RoundedRectangleBorder(),
                ),
                child: const Text(
                  "CONCLUDI OPERAZIONE / REBOOT TERMINAL",
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 14.0,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard({required String title, required String value, required Color color}) {
    return Container(
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.5), width: 1.5),
        color: Colors.black,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 10.0,
              color: Color(0xFF888888),
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4.0),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 14.0,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11.0,
              color: Color(0xFFBBBBBB),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11.0,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlitchContainer({required double intensity, required Widget child}) {
    if (intensity <= 0.0 || !widget.notifier.shaderEnabled) return child;
    
    final shader = _shader;
    if (shader != null) {
      return ShaderMask(
        shaderCallback: (rect) {
          shader.setFloat(0, rect.width);
          shader.setFloat(1, rect.height);
          shader.setFloat(2, _time);
          shader.setFloat(3, intensity);
          return shader;
        },
        blendMode: BlendMode.dstIn,
        child: child,
      );
    } else {
      return CustomPaint(
        foregroundPainter: _RGBShiftPainter(intensity: intensity, time: _time),
        child: child,
      );
    }
  }
}

class _RGBShiftPainter extends CustomPainter {
  final double intensity;
  final double time;

  _RGBShiftPainter({required this.intensity, required this.time});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.green.withValues(alpha: 0.03 * intensity)
      ..strokeWidth = 1.0;

    for (double y = 0.0; y < size.height; y += 4.0) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    
    if (time % 0.5 < 0.15) {
      final flickerPaint = Paint()
        ..color = const Color(0xFF00FF66).withValues(alpha: 0.015 * intensity);
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), flickerPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _RGBShiftPainter oldDelegate) {
    return oldDelegate.intensity != intensity || oldDelegate.time != time;
  }
}

class _BlinkingText extends StatefulWidget {
  final String text;
  final TextStyle style;
  const _BlinkingText(this.text, {required this.style});

  @override
  State<_BlinkingText> createState() => _BlinkingTextState();
}

class _BlinkingTextState extends State<_BlinkingText> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
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
      opacity: _controller.drive(CurveTween(curve: Curves.easeInOut)),
      child: Text(widget.text, style: widget.style),
    );
  }
}

class _MatrixRainBackground extends StatefulWidget {
  final double opacity;
  const _MatrixRainBackground({required this.opacity});

  @override
  State<_MatrixRainBackground> createState() => _MatrixRainBackgroundState();
}

class _MatrixRainBackgroundState extends State<_MatrixRainBackground> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late List<_MatrixColumn> _columns;
  final math.Random _random = math.Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();
    _columns = [];
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _initializeColumns(double width) {
    const double columnWidth = 14.0;
    final int count = (width / columnWidth).ceil();
    if (_columns.length == count) return;
    
    _columns = List.generate(count, (index) {
      return _MatrixColumn(
        x: index * columnWidth,
        y: _random.nextDouble() * -500.0,
        speed: 2.0 + _random.nextDouble() * 4.0,
        chars: List.generate(15 + _random.nextInt(15), (_) => String.fromCharCode(33 + _random.nextInt(93))),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.opacity <= 0.0) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        _initializeColumns(constraints.maxWidth);
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            const textStyle = TextStyle(
              fontFamily: 'monospace',
              fontSize: 12.0,
              fontWeight: FontWeight.bold,
              height: 14.0 / 12.0, // Exactly 14.0 pixels line height
            );

            // Update column positions
            for (var col in _columns) {
              col.y += col.speed;
              if (col.y > constraints.maxHeight) {
                col.y = -200.0 - _random.nextDouble() * 300.0;
                col.speed = 2.0 + _random.nextDouble() * 4.0;
              }
              // Mutate characters occasionally
              if (_random.nextDouble() < 0.1) {
                col.chars[_random.nextInt(col.chars.length)] = 
                    String.fromCharCode(33 + _random.nextInt(93));
                col.clearPainter();
              }
              // Pre-compute/update painter layout in the build phase
              col.updatePainter(widget.opacity, textStyle);
            }

            return CustomPaint(
              size: Size(constraints.maxWidth, constraints.maxHeight),
              painter: _MatrixRainPainter(
                columns: _columns,
                opacity: widget.opacity,
              ),
            );
          },
        );
      },
    );
  }
}

class _MatrixColumn {
  double x;
  double y;
  double speed;
  List<String> chars;
  TextPainter? cachedPainter;
  double? cachedOpacity;

  _MatrixColumn({
    required this.x,
    required this.y,
    required this.speed,
    required this.chars,
  });

  void updatePainter(double opacity, TextStyle textStyle) {
    if (cachedPainter != null && cachedOpacity == opacity) {
      return;
    }
    cachedOpacity = opacity;

    final List<InlineSpan> children = [];
    for (int i = 0; i < chars.length; i++) {
      double alpha = (i / chars.length) * opacity;
      final color = i == chars.length - 1
          ? const Color(0xFFFFFFFF).withValues(alpha: alpha) // Lead character is white
          : const Color(0xFF00FF66).withValues(alpha: alpha);

      children.add(
        TextSpan(
          text: chars[i] + (i == chars.length - 1 ? '' : '\n'),
          style: textStyle.copyWith(color: color),
        ),
      );
    }

    cachedPainter = TextPainter(
      text: TextSpan(children: children),
      textDirection: TextDirection.ltr,
    )..layout();
  }

  void clearPainter() {
    cachedPainter = null;
  }
}

class _MatrixRainPainter extends CustomPainter {
  final List<_MatrixColumn> columns;
  final double opacity;

  _MatrixRainPainter({required this.columns, required this.opacity});

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0.0) return;

    for (var col in columns) {
      final double columnHeight = col.chars.length * 14.0;
      // Frustum culling: skip columns that are completely offscreen vertically
      if (col.y + columnHeight < 0 || col.y > size.height) continue;

      if (col.cachedPainter != null) {
        col.cachedPainter!.paint(canvas, Offset(col.x, col.y));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MatrixRainPainter oldDelegate) {
    return true; // Animates constantly
  }
}

class _CrtGridOverlay extends StatefulWidget {
  final bool flicker;
  const _CrtGridOverlay({required this.flicker});

  @override
  State<_CrtGridOverlay> createState() => _CrtGridOverlayState();
}

class _CrtGridOverlayState extends State<_CrtGridOverlay> with SingleTickerProviderStateMixin {
  late AnimationController _flickerController;
  final math.Random _random = math.Random();

  @override
  void initState() {
    super.initState();
    // Animates constantly to simulate grid flicker
    _flickerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    )..repeat();
  }

  @override
  void dispose() {
    _flickerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isFlickering = widget.flicker;
    
    return AnimatedBuilder(
      animation: _flickerController,
      builder: (context, child) {
        double gridOpacity = 0.08; // Base opacity of scanlines
        
        if (isFlickering) {
          // Clean, dry flicker: scanlines shift opacity to show loss of stability
          final double flickerNoise = _random.nextDouble();
          if (flickerNoise < 0.4) {
            gridOpacity = 0.08 + (_random.nextDouble() * 0.12);
          } else if (flickerNoise < 0.7) {
            gridOpacity = 0.08 - (_random.nextDouble() * 0.06);
          }
        }
        
        return IgnorePointer(
          child: CustomPaint(
            size: Size.infinite,
            painter: _CrtGridPainter(opacity: gridOpacity),
          ),
        );
      },
    );
  }
}

class _CrtGridPainter extends CustomPainter {
  final double opacity;
  _CrtGridPainter({required this.opacity});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF00FF66).withValues(alpha: opacity)
      ..strokeWidth = 1.0;

    // Draw scanlines every 4 pixels
    for (double y = 0.0; y < size.height; y += 4.0) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CrtGridPainter oldDelegate) {
    return oldDelegate.opacity != opacity;
  }
}

