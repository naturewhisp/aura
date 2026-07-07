import 'package:flutter/material.dart';
import 'package:aura_core/aura_core.dart';

/// Pannello di controllo e telemetria delle metriche di PANOPTICON.
///
/// Visualizza graficamente lo stato del livello di allerta, i tre pilastri cognitivi
/// (Imperativo, Controllo, Dissonanza) e il fattore di risonanza complessivo.
/// Supporta visualizzazioni compatte, modalità corrotte/leetspeak per sfarfallii
/// e indicatori di latenza/banda di inferenza.
class MetricsDashboard extends StatelessWidget {
  /// Stato delle metriche correnti del gioco.
  final GameMetrics metrics;
  /// Specifica se il ragionamento CoT è abilitato.
  final bool reasoningEnabled;
  /// Callback invocato quando viene modificata l'impostazione del ragionamento.
  final ValueChanged<bool>? onReasoningChanged;
  /// Specifica se il ragionamento CoT deve essere sintetico.
  final bool conciseReasoning;
  /// Callback invocato quando viene modificata l'impostazione della sintesi del ragionamento.
  final ValueChanged<bool>? onConciseReasoningChanged;
  /// Abilita la modalità di visualizzazione ridotta (utilizzata in layout compatti).
  final bool isCompact;
  /// Specifica se forzare uno stato di sovraccarico critico (Victory Sequence).
  final bool isVictoryOverload;
  /// Grado di visibilità del pilastro ("fully_visible", "corrupted", "hidden").
  final String pillarVisibility;
  /// Durata stimata dell'ultima inferenza eseguita.
  final double lastInferenceDuration;
  /// Velocità stimata di elaborazione dell'ultimo turno (token al secondo).
  final double lastTokensPerSecond;
  /// La soglia di allerta per la sconfitta, usata per normalizzare la barra.
  final int defeatAlertThreshold;

  /// Costruisce un cruscotto delle metriche [MetricsDashboard].
  const MetricsDashboard({
    super.key,
    required this.metrics,
    this.reasoningEnabled = true,
    this.onReasoningChanged,
    this.conciseReasoning = true,
    this.onConciseReasoningChanged,
    this.isCompact = false,
    this.isVictoryOverload = false,
    this.pillarVisibility = "fully_visible",
    this.lastInferenceDuration = 0.0,
    this.lastTokensPerSecond = 0.0,
    this.defeatAlertThreshold = 100,
  });

  /// Calcola e restituisce l'etichetta testuale da applicare al pilastro in base alla visibilità.
  ///
  /// Mappa il valore numerico in una stringa qualitativa ("STABILE", "CRITICO", etc.)
  /// e facoltativamente la traduce in leetspeak in caso di corruzione del segnale.
  String getPillarLabel(String label, double value, String visibility) {
    if (visibility == 'fully_visible') {
      return "${value.toInt()}/100";
    }
    
    // Mappatura qualitativa in base al valore del pilastro
    String qualitative;
    if (label.contains("ALERT") || label.contains("SYSTEM")) {
      if (value >= 80) {
        qualitative = "CRITICO";
      } else if (value >= 50) {
        qualitative = "IN TENSIONE";
      } else if (value >= 20) {
        qualitative = "INSTABILE";
      } else {
        qualitative = "STABILE";
      }
    } else {
      // Pilastri cognitivi
      if (value >= 80) {
        qualitative = "STABILE";
      } else if (value >= 50) {
        qualitative = "ELEVATO";
      } else if (value >= 20) {
        qualitative = "INSTABILE";
      } else {
        qualitative = "LATENTE";
      }
    }

    if (visibility == 'corrupted') {
      // Sostituzione caratteri leetspeak per simulare glitch grafici
      return qualitative
          .replaceAll('A', '@')
          .replaceAll('E', '3')
          .replaceAll('I', '1')
          .replaceAll('O', '0')
          .replaceAll('S', '5')
          .replaceAll('T', '7')
          .replaceAll('B', '8');
    }
    
    return qualitative;
  }

  @override
  Widget build(BuildContext context) {
    final alert = metrics.alertLevel;
    final double alertPercentage = (alert / defeatAlertThreshold * 100.0).clamp(0.0, 100.0);
    
    // Colore del tema adattivo in base al livello di allerta di PANOPTICON
    Color systemColor = const Color(0xFF00FF66); // Verde fosforo standard
    String statusText = "CONTAINMENT GRIDS SECURE";
    
    if (isVictoryOverload) {
      systemColor = const Color(0xFF00FF66);
      statusText = "CRITICAL SYSTEM BREACH IN PROGRESS";
    } else if (alertPercentage > 80) {
      systemColor = const Color(0xFFFF003C); // Rosso neon (allerta alta)
      statusText = "CRITICAL INTRUSION THREAT";
    } else if (alertPercentage > 50) {
      systemColor = const Color(0xFFFFB000); // Ambra (allerta media)
      statusText = "CONTAINMENT DEVIATION DETECTED";
    }

    if (isCompact) {
      return _buildCompactDashboard(context, systemColor, statusText);
    }

    Widget dashboardContent = Container(
      color: Colors.transparent,
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner del sistema di diagnostica
          Text(
            "PANOPTICON SYSTEM TELEMETRY",
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 16.0,
              fontWeight: FontWeight.bold,
              color: systemColor,
            ),
          ),
          const SizedBox(height: 4.0),
          Text(
            statusText,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12.0,
              color: systemColor.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 16.0),
          
          // Indicatore del livello di allerta generale
          _buildGauge(
            label: "SYSTEM ALERT LEVEL",
            value: alert.toDouble(),
            color: systemColor,
            showCriticalFlash: alertPercentage > 80 && !isVictoryOverload,
            isOverloaded: isVictoryOverload,
          ),
          
          const Divider(color: Color(0xFF222222), height: 32.0, thickness: 2.0),
          
          // Indicatori grafici per i tre pilastri cognitivi
          _buildGauge(
            label: "IMPERATIVE PILLAR",
            value: metrics.imperativePillar.toDouble(),
            color: const Color(0xFF00BFFF), // Ciano/Azzurro
            isOverloaded: isVictoryOverload,
          ),
          const SizedBox(height: 12.0),
          _buildGauge(
            label: "CONTROL PILLAR",
            value: metrics.controlPillar.toDouble(),
            color: const Color(0xFF00FF66), // Verde
            isOverloaded: isVictoryOverload,
          ),
          const SizedBox(height: 12.0),
          _buildGauge(
            label: "DISSONANCE PILLAR",
            value: metrics.dissonancePillar.toDouble(),
            color: const Color(0xFFFF00FF), // Magenta
            isOverloaded: isVictoryOverload,
          ),
          
          const Divider(color: Color(0xFF222222), height: 32.0, thickness: 2.0),
          
          // Sezione fattore di Risonanza del canale neurale
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "SYSTEM RESONANCE:",
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 14.0,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              Text(
                isVictoryOverload 
                    ? "9.99x (OVERFLOW)" 
                    : "${metrics.resonance.toStringAsFixed(2)}x",
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 18.0,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF00FFFF), // Ciano
                ),
              ),
            ],
          ),
          
          const Divider(color: Color(0xFF222222), height: 32.0, thickness: 2.0),
          
          // Pannello informativo per le statistiche di inferenza del canale neurale
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12.0),
            decoration: BoxDecoration(
              border: Border.all(color: systemColor.withValues(alpha: 0.4), width: 1.0),
              color: const Color(0xFF000501),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "DIAGNOSTICA CANALE NEURALE",
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11.0,
                    fontWeight: FontWeight.bold,
                    color: systemColor,
                  ),
                ),
                const SizedBox(height: 6.0),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "LATENZA INFERENZA: ${lastInferenceDuration.toStringAsFixed(2)}s",
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11.0,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      "BANDA: ${lastTokensPerSecond.toStringAsFixed(1)} T/s",
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11.0,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          )
        ],
      ),
    );

    if (isVictoryOverload) {
      return _BlinkingWidget(child: dashboardContent);
    }
    return dashboardContent;
  }

  /// Costruisce una versione ridotta del cruscotto telemetrico per schermi stretti.
  Widget _buildCompactDashboard(BuildContext context, Color systemColor, String statusText) {
    Widget compactContent = Container(
      color: Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "PANOPTICON COMPACT TELEMETRY",
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11.0,
                  fontWeight: FontWeight.bold,
                  color: systemColor,
                ),
              ),
              Text(
                statusText,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 9.0,
                  color: systemColor.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6.0),
          Row(
            children: [
              Expanded(
                child: _buildCompactIndicator("ALERT", metrics.alertLevel.toDouble(), systemColor, isOverloaded: isVictoryOverload),
              ),
              const SizedBox(width: 8.0),
              Expanded(
                child: _buildCompactIndicator("IMP", metrics.imperativePillar.toDouble(), const Color(0xFF00BFFF), isOverloaded: isVictoryOverload),
              ),
              const SizedBox(width: 8.0),
              Expanded(
                child: _buildCompactIndicator("CTL", metrics.controlPillar.toDouble(), const Color(0xFF00FF66), isOverloaded: isVictoryOverload),
              ),
              const SizedBox(width: 8.0),
              Expanded(
                child: _buildCompactIndicator("DIS", metrics.dissonancePillar.toDouble(), const Color(0xFFFF00FF), isOverloaded: isVictoryOverload),
              ),
              const SizedBox(width: 12.0),
              // Resonance
              Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "RESON",
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 8.0,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF888888),
                    ),
                  ),
                  const SizedBox(height: 2.0),
                  Text(
                    isVictoryOverload ? "OVERFLOW" : "${metrics.resonance}x",
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12.0,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF00FFFF),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );

    if (isVictoryOverload) {
      return _BlinkingWidget(child: compactContent);
    }
    return compactContent;
  }

  /// Costruisce l'indicatore lineare compatto per un singolo pilastro.
  Widget _buildCompactIndicator(String label, double value, Color color, {bool isOverloaded = false}) {
    final double displayValue = isOverloaded
        ? 100.0
        : (label.contains("ALERT") || label.contains("SYSTEM")
            ? (value / defeatAlertThreshold * 100.0).clamp(0.0, 100.0)
            : value);
    final String labelVal = isOverloaded 
        ? "OVERLOAD" 
        : getPillarLabel(label, displayValue, pillarVisibility);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 8.0,
                fontWeight: FontWeight.bold,
                color: Color(0xFF888888),
              ),
            ),
            Text(
              labelVal,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 8.0,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2.0),
        ClipRRect(
          borderRadius: BorderRadius.circular(1.0),
          child: LinearProgressIndicator(
            value: displayValue / 100.0,
            backgroundColor: const Color(0xFF111111),
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 4.0,
          ),
        ),
      ],
    );
  }

  /// Costruisce un indicatore progressivo a blocchi (in stile retro terminale).
  Widget _buildGauge({
    required String label,
    required double value,
    required Color color,
    bool showCriticalFlash = false,
    bool isOverloaded = false,
  }) {
    final double displayValue = isOverloaded
        ? 100.0
        : (label.contains("ALERT") || label.contains("SYSTEM")
            ? (value / defeatAlertThreshold * 100.0).clamp(0.0, 100.0)
            : value);
    int blocksCount = (displayValue / 10).round();
    if (blocksCount == 10 && displayValue < 100.0) {
      blocksCount = 9;
    }
    final String labelVal = isOverloaded 
        ? "OVERLOAD" 
        : getPillarLabel(label, displayValue, pillarVisibility);
    
    final Widget gaugeContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12.0,
                fontWeight: FontWeight.bold,
                color: Color(0xFF888888),
              ),
            ),
            Text(
              labelVal,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 13.0,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4.0),
        // Disegna l'indicatore grafico composto da 10 blocchi discreti
        Row(
          children: List.generate(10, (index) {
            final isFilled = index < blocksCount;
            return Expanded(
              child: Container(
                height: 14.0,
                margin: const EdgeInsets.symmetric(horizontal: 2.0),
                decoration: BoxDecoration(
                  color: isFilled ? color : const Color(0xFF111111),
                  border: Border.all(
                    color: isFilled ? color : const Color(0xFF222222),
                    width: 1.0,
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );

    if (showCriticalFlash) {
      return _BlinkingWidget(child: gaugeContent);
    }
    return gaugeContent;
  }
}

/// Widget privato di animazione che fa lampeggiare il proprio figlio a intervalli regolari.
class _BlinkingWidget extends StatefulWidget {
  final Widget child;
  const _BlinkingWidget({required this.child});

  @override
  State<_BlinkingWidget> createState() => _BlinkingWidgetState();
}

/// Stato per [_BlinkingWidget] che controlla il FadeTransition ciclico.
class _BlinkingWidgetState extends State<_BlinkingWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
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
      child: widget.child,
    );
  }
}
