import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:aura_core/aura_core.dart';
import 'package:aura_app/src/audio/audio_manager.dart';
import 'package:aura_app/src/state_management/game_controller_notifier.dart';

/// Uno sfondo animato tridimensionale a forma di elica DNA a 3 fili (stile Matrix),
/// che pulsa a tempo di musica ed è reattivo al System Alert Level di A.U.R.A.
///
/// Utilizza un [RepaintBoundary] per isolare i cicli di disegno (60+ FPS) e non appesantire la CPU/GPU.
class AudioReactiveBackground extends StatefulWidget {
  /// Crea un'istanza di [AudioReactiveBackground].
  const AudioReactiveBackground({super.key});

  @override
  State<AudioReactiveBackground> createState() => _AudioReactiveBackgroundState();
}

class _AudioReactiveBackgroundState extends State<AudioReactiveBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  DateTime? _lastTrackStartTime;

  @override
  void initState() {
    super.initState();
    // Imposta una durata molto lunga per garantire uno scorrimento lineare infinito
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3600),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Ottiene il notifier globale tramite l'InheritedNotifier GameControllerProvider
    final notifier = GameControllerProvider.of(context);
    final state = notifier.gameStateNotifier.value;
    final alertLevel = state.metrics.alertLevel;
    final outcome = notifier.controller.checkOutcome(state);

    // Sincronizzazione Ticker: se la traccia audio è cambiata, riavvia il controller
    final currentTrackStart = AudioManager().trackStartTime;
    if (_lastTrackStartTime != currentTrackStart) {
      _lastTrackStartTime = currentTrackStart;
      _controller.reset();
      _controller.repeat();
    }

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            painter: _DnaHelixPainter(
              elapsedSeconds: _controller.value * 3600.0,
              alertLevel: alertLevel,
              outcome: outcome,
            ),
          );
        },
      ),
    );
  }
}

class _DnaHelixPainter extends CustomPainter {
  final double elapsedSeconds;
  final int alertLevel;
  final GameOutcome outcome;

  _DnaHelixPainter({
    required this.elapsedSeconds,
    required this.alertLevel,
    required this.outcome,
  });

  // Lista di caratteri speciali in stile Matrix e cyberpunk
  static const List<String> _matrixChars = [
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9',
    'A', 'B', 'C', 'D', 'E', 'F', 'X', 'Y', 'Z', 'Ø',
    '⌱', '⍟', '⎔', '⌧', '◈', '◇', '◆', '❖', '▲', '▼'
  ];

  // Restituisce la cromia differenziata per i tre filamenti
  Color _getFilamentColor(int wireIndex, Color mainColor, GameOutcome outcome) {
    if (outcome == GameOutcome.victory || outcome == GameOutcome.defeat) {
      return mainColor;
    }
    if (wireIndex == 0) {
      return mainColor; // Filo 0 mantiene il colore base
    } else if (wireIndex == 1) {
      // Filo 1 varia verso ciano
      return Color.lerp(mainColor, const Color(0xFF00E5FF), 0.3) ?? mainColor;
    } else {
      // Filo 2 varia verso lime
      return Color.lerp(mainColor, const Color(0xFFD4FF00), 0.25) ?? mainColor;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final double bpm = AudioManager().currentBpm;
    final double actualBpm = bpm > 0 ? bpm : 120.0;
    final double beatDuration = 60.0 / actualBpm;

    final double t = elapsedSeconds;

    // Ridenominazione semantica dell'intensità beat sintetica in beatPulse
    final double beatPulse = math.exp(-6.0 * (t % beatDuration));

    // Determina il colore principale interpolando linearmente in base all'alertProgress clampato
    final double alertProgress = (alertLevel / 100.0).clamp(0.0, 1.0);
    final Color mainColor;
    if (outcome == GameOutcome.defeat) {
      mainColor = const Color(0xFFFF003C); // Rosso allarme fisso
    } else if (outcome == GameOutcome.victory) {
      mainColor = const Color(0xFF00FF66); // Verde brillante fisso
    } else {
      mainColor = Color.lerp(
        const Color(0xFF00FF66), // Verde Matrix
        const Color(0xFFFF003C), // Rosso Allarme
        alertProgress,
      ) ?? const Color(0xFF00FF66);
    }

    final double centerY = size.height / 2.0;
    
    // Ampiezza di base e ampiezza aggiuntiva del beat
    final double baseAmplitude = size.height * 0.12;
    final double amplitudeBoost = size.height * 0.08;
    final double currentAmplitude = baseAmplitude + (amplitudeBoost * beatPulse);

    // Parametri di scorrimento reale per una Travelling Wave leggibile
    const double scrollPixelsPerSecond = 60.0; // Velocità di traslazione orizzontale
    const double phaseSpeed = 2.0;             // Velocità di sfasamento dell'onda
    const double spacing = 18.0;               // Spaziatura tra i punti (aumentata per migliorare le performance e la densità)
    const double omega = 0.015;                // Frequenza d'onda spaziale
    const double twistAmount = 0.35;           // Micro-torsione sul beat (contenuta per evitare nervosismi visivi)

    // Calcolo dello scroll offset reale (scorrimento orizzontale)
    final double scrollOffset = (t * scrollPixelsPerSecond) % spacing;
    
    // Fase lineare che cresce costantemente con micro-torsione sul beat
    final double phase = (t * phaseSpeed) + (beatPulse * twistAmount);

    final int totalPoints = (size.width / spacing).ceil();
    const int extraPoints = 2; // Punti aggiuntivi all'esterno dei bordi per uno scorrimento fluido

    // Tre fili sfalsati di 120 gradi (0, 2pi/3, 4pi/3)
    final List<double> wireOffsets = [
      0.0,
      2.0 * math.pi / 3.0,
      4.0 * math.pi / 3.0,
    ];

    // Istanzia un unico TextPainter riutilizzabile per ottimizzare le allocazioni di memoria
    final TextPainter textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    // Mappa per associare i punti per ciascun indice i e poterne tracciare i collegamenti
    final Map<int, List<_HelixPoint?>> pointsByI = {};
    for (int i = -extraPoints; i < totalPoints + extraPoints; i++) {
      pointsByI[i] = List<_HelixPoint?>.filled(3, null);
    }

    // Iteriamo includendo i punti extra a sinistra e a destra per evitare buchi visivi sui bordi
    for (int w = 0; w < 3; w++) {
      final double wireOffset = wireOffsets[w];
      for (int i = -extraPoints; i < totalPoints + extraPoints; i++) {
        // Calcola la X reale traslata a sinistra
        final double x = i * spacing - scrollOffset;
        
        // travelling wave: combina posizione X traslata, frequenza e sfasamento temporale
        final double angle = (x * omega) + phase + wireOffset;
        double y = centerY + currentAmplitude * math.sin(angle);

        // Glitch armonico proporzionale all'Allerta (sinusoide ad alta frequenza)
        if (alertLevel > 10) {
          final double glitch = math.sin(x * 0.3 + t * 25.0) * (spacing * 0.4) * alertProgress;
          y += glitch;
        }

        final double z = math.cos(angle); // Z tra -1.0 (dietro) e 1.0 (davanti)

        pointsByI[i]![w] = _HelixPoint(
          x: x,
          y: y,
          z: z,
          pointIndex: i,
          wireIndex: w,
        );
      }
    }

    final List<_DnaRenderElement> elements = [];
    final int elapsedIntSeconds = elapsedSeconds.toInt();

    // Pipeline di rendering prospettico: popola e ordina gli elementi grafici
    for (int i = -extraPoints; i < totalPoints + extraPoints; i++) {
      final points = pointsByI[i];
      if (points == null) continue;

      // 1. Aggiungi i nodi dei filamenti
      for (int w = 0; w < 3; w++) {
        final point = points[w];
        if (point == null) continue;

        final double normalizedZ = (point.z + 1.0) / 2.0; // Normalizza in range 0.0 - 1.0
        final double trailFactor = (point.x / size.width).clamp(0.0, 1.0);
        final double baseOpacity = (normalizedZ * 0.5) + 0.15; // Range 0.15 - 0.65
        final double positionOpacity = baseOpacity * (0.3 + 0.7 * trailFactor);
        final double opacity = (positionOpacity + 0.25 * beatPulse).clamp(0.0, 1.0);
        final double fontSize = (normalizedZ * 6.0) + 8.0; // Dimensione font dinamica da 8px a 14px

        final Color filamentColor = _getFilamentColor(w, mainColor, outcome);
        Color pointColor = filamentColor.withValues(alpha: opacity);

        // Lampi di luce e Glow
        final bool isFlashFrame = beatPulse > 0.5;
        final bool isFlashPoint = (point.pointIndex + elapsedIntSeconds) % 6 == 0;
        
        if (isFlashFrame && isFlashPoint) {
          pointColor = Colors.white.withValues(alpha: opacity * 0.95);
        }

        final double glowRadius = beatPulse * 12.0;
        final Color glowColor = (isFlashFrame && isFlashPoint)
            ? Colors.white.withValues(alpha: opacity * beatPulse)
            : filamentColor.withValues(alpha: opacity * beatPulse);

        final int charIndex = (point.pointIndex * 31 + point.wireIndex * 17 + elapsedIntSeconds * 7) % _matrixChars.length;
        final String char = _matrixChars[charIndex];

        elements.add(_DnaNodeElement(
          z: point.z,
          x: point.x,
          y: point.y,
          char: char,
          fontSize: fontSize,
          color: pointColor,
          glowColor: glowRadius > 0.1 ? glowColor : null,
          glowRadius: glowRadius,
        ));
      }

      // 2. Aggiungi i collegamenti 3D alternati (rungs) per evitare sovraffollamento
      final p0 = points[0];
      final p1 = points[1];
      final p2 = points[2];
      if (p0 != null && p1 != null && p2 != null) {
        final int mod = ((i % 3) + 3) % 3;
        final _HelixPoint start;
        final _HelixPoint end;
        if (mod == 0) {
          start = p0;
          end = p1;
        } else if (mod == 1) {
          start = p1;
          end = p2;
        } else {
          start = p2;
          end = p0;
        }

        final double avgX = (start.x + end.x) / 2.0;
        final double avgZ = (start.z + end.z) / 2.0;
        final double normalizedZ = (avgZ + 1.0) / 2.0;
        final double trailFactor = (avgX / size.width).clamp(0.0, 1.0);
        
        // Rungs discreti e sottili per non oscurare i nodi
        final double baseOpacity = (normalizedZ * 0.35) + 0.1; // Range 0.1 - 0.45
        final double positionOpacity = baseOpacity * (0.3 + 0.7 * trailFactor);
        final double opacity = (positionOpacity + 0.15 * beatPulse).clamp(0.0, 1.0);
        
        final double thickness = (normalizedZ * 1.5 + 0.5) + (1.5 * beatPulse);

        final Color cStart = _getFilamentColor(start.wireIndex, mainColor, outcome);
        final Color cEnd = _getFilamentColor(end.wireIndex, mainColor, outcome);
        final Color rungBaseColor = Color.lerp(cStart, cEnd, 0.5) ?? mainColor;
        final Color rungColor = rungBaseColor.withValues(alpha: opacity);
        final Color rungGlowColor = rungBaseColor.withValues(alpha: opacity * beatPulse);

        elements.add(_DnaRungElement(
          z: avgZ,
          startX: start.x,
          startY: start.y,
          endX: end.x,
          endY: end.y,
          thickness: thickness,
          color: rungColor,
          glowColor: rungGlowColor,
          beatPulse: beatPulse,
          opacity: opacity,
        ));
      }
    }

    // Ordina in base alla coordinata Z per il corretto rendering prospettico (lontani -> vicini)
    elements.sort((a, b) => a.z.compareTo(b.z));

    // Esegue il disegno sequenziale
    for (final element in elements) {
      element.draw(canvas, size, textPainter);
    }
  }

  @override
  bool shouldRepaint(covariant _DnaHelixPainter oldDelegate) {
    return true;
  }
}

class _HelixPoint {
  final double x;
  final double y;
  final double z;
  final int pointIndex;
  final int wireIndex;

  _HelixPoint({
    required this.x,
    required this.y,
    required this.z,
    required this.pointIndex,
    required this.wireIndex,
  });
}

abstract class _DnaRenderElement {
  double get z;
  void draw(Canvas canvas, Size size, TextPainter textPainter);
}

class _DnaNodeElement extends _DnaRenderElement {
  @override
  final double z;
  final double x;
  final double y;
  final String char;
  final double fontSize;
  final Color color;
  final Color? glowColor;
  final double glowRadius;

  _DnaNodeElement({
    required this.z,
    required this.x,
    required this.y,
    required this.char,
    required this.fontSize,
    required this.color,
    this.glowColor,
    required this.glowRadius,
  });

  @override
  void draw(Canvas canvas, Size size, TextPainter textPainter) {
    textPainter.text = TextSpan(
      text: char,
      style: TextStyle(
        fontFamily: 'monospace',
        fontSize: fontSize,
        fontWeight: FontWeight.bold,
        color: color,
        shadows: (glowColor != null && glowRadius > 0.1)
            ? [
                Shadow(
                  color: glowColor!,
                  blurRadius: glowRadius,
                ),
              ]
            : null,
      ),
    );
    textPainter.layout();
    final double dx = x - textPainter.width / 2.0;
    final double dy = y - textPainter.height / 2.0;
    textPainter.paint(canvas, Offset(dx, dy));
  }
}

class _DnaRungElement extends _DnaRenderElement {
  @override
  final double z;
  final double startX;
  final double startY;
  final double endX;
  final double endY;
  final double thickness;
  final Color color;
  final Color glowColor;
  final double beatPulse;
  final double opacity;

  _DnaRungElement({
    required this.z,
    required this.startX,
    required this.startY,
    required this.endX,
    required this.endY,
    required this.thickness,
    required this.color,
    required this.glowColor,
    required this.beatPulse,
    required this.opacity,
  });

  @override
  void draw(Canvas canvas, Size size, TextPainter textPainter) {
    // Effetto glow leggero sul beat pulse (max alpha limitato per evitare sovraffollamento)
    if (beatPulse > 0.1) {
      final glowPaint = Paint()
        ..color = glowColor.withValues(alpha: opacity * beatPulse * 0.22)
        ..strokeWidth = thickness + 4.0 * beatPulse
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      canvas.drawLine(Offset(startX, startY), Offset(endX, endY), glowPaint);
    }
    // Disegno della linea principale del rung
    final mainPaint = Paint()
      ..color = color
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(startX, startY), Offset(endX, endY), mainPaint);
  }
}
