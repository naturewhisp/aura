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
    '⌱', '⍟', '⚙', '⚡', '◈', '◇', '◆', '❖', '▲', '▼'
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final double bpm = AudioManager().currentBpm;
    final double actualBpm = bpm > 0 ? bpm : 120.0;
    final double beatDuration = 60.0 / actualBpm;

    // Calcola il tempo reale dall'avvio della traccia audio corrente
    final DateTime trackStartTime = AudioManager().trackStartTime;
    final double t = DateTime.now().difference(trackStartTime).inMilliseconds / 1000.0;

    // Calcola l'intensità del battito con un decadimento esponenziale (simulazione del kick)
    final double beatIntensity = math.exp(-6.0 * (t % beatDuration));

    // Determina il colore principale interpolando linearmente in base al livello di allerta
    final double alertProgress = alertLevel / 100.0;
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
    final double currentAmplitude = baseAmplitude + (amplitudeBoost * beatIntensity);

    // Parametri di scorrimento reale per una Travelling Wave leggibile
    const double scrollPixelsPerSecond = 60.0; // Velocità di traslazione orizzontale
    const double phaseSpeed = 2.0;             // Velocità di sfasamento dell'onda
    const double spacing = 16.0;               // Spaziatura tra i punti
    const double omega = 0.015;                // Frequenza d'onda spaziale

    // Calcolo dello scroll offset reale (scorrimento orizzontale)
    final double scrollOffset = (t * scrollPixelsPerSecond) % spacing;
    
    // Fase lineare che cresce costantemente
    final double phase = t * phaseSpeed;

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

    // Algoritmo del Pittore: ordina i punti da Z più lontana a Z più vicina per gestire correttamente la sovrapposizione 3D
    final List<_HelixPoint> pointsToDraw = [];

    // Iteriamo includendo i punti extra a sinistra e a destra per evitare buchi visivi sui bordi
    for (int w = 0; w < 3; w++) {
      final double wireOffset = wireOffsets[w];
      for (int i = -extraPoints; i < totalPoints + extraPoints; i++) {
        // Calcola la X reale traslata a sinistra
        final double x = i * spacing - scrollOffset;
        
        // travelling wave: combina posizione X traslata, frequenza e sfasamento temporale
        final double angle = (x * omega) + phase + wireOffset;
        final double y = centerY + currentAmplitude * math.sin(angle);
        final double z = math.cos(angle); // Z tra -1.0 (dietro) e 1.0 (davanti)

        pointsToDraw.add(_HelixPoint(
          x: x,
          y: y,
          z: z,
          pointIndex: i,
          wireIndex: w,
        ));
      }
    }

    // Ordina in base alla coordinata Z per il corretto rendering prospettico
    pointsToDraw.sort((a, b) => a.z.compareTo(b.z));

    final int elapsedIntSeconds = elapsedSeconds.toInt();

    for (final point in pointsToDraw) {
      final double normalizedZ = (point.z + 1.0) / 2.0; // Normalizza in range 0.0 - 1.0
      
      // Calcola l'opacità basata sia sulla profondità Z sia sul fade direzionale (trailFactor)
      // I nuovi punti entrano più luminosi da destra (x = width) e sfumano verso sinistra (x = 0)
      final double trailFactor = (point.x / size.width).clamp(0.0, 1.0);
      final double baseOpacity = (normalizedZ * 0.5) + 0.15; // Range 0.15 - 0.65
      final double positionOpacity = baseOpacity * (0.3 + 0.7 * trailFactor);
      
      // L'opacità globale e la luminosità aumentano sui kick
      final double opacity = (positionOpacity + 0.25 * beatIntensity).clamp(0.0, 1.0);
      final double fontSize = (normalizedZ * 6.0) + 8.0; // Dimensione font dinamica da 8px a 14px

      Color pointColor = mainColor.withValues(alpha: opacity);

      // Lampi di luce e Glow
      final bool isFlashFrame = beatIntensity > 0.5;
      final bool isFlashPoint = (point.pointIndex + elapsedIntSeconds) % 6 == 0;
      
      if (isFlashFrame && isFlashPoint) {
        pointColor = Colors.white.withValues(alpha: opacity * 0.95);
      }

      // Il raggio del bagliore fluorescente si espande fino a 12px sul kick
      final double glowRadius = beatIntensity * 12.0;
      final Color glowColor = (isFlashFrame && isFlashPoint)
          ? Colors.white.withValues(alpha: opacity * beatIntensity)
          : mainColor.withValues(alpha: opacity * beatIntensity);

      // Scelta deterministica anti-flicker basata sulle coordinate e sui secondi passati
      final int charIndex = (point.pointIndex * 31 + point.wireIndex * 17 + elapsedIntSeconds * 7) % _matrixChars.length;
      final String char = _matrixChars[charIndex];

      textPainter.text = TextSpan(
        text: char,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          color: pointColor,
          shadows: glowRadius > 0.1
              ? [
                  Shadow(
                    color: glowColor,
                    blurRadius: glowRadius,
                  ),
                ]
              : null,
        ),
      );

      textPainter.layout();
      final double dx = point.x - textPainter.width / 2.0;
      final double dy = point.y - textPainter.height / 2.0;
      textPainter.paint(canvas, Offset(dx, dy));
    }
  }

  @override
  bool shouldRepaint(covariant _DnaHelixPainter oldDelegate) {
    // Ritorna sempre true per consentire l'avanzamento fluido dell'animazione
    // basata sul tempo reale di sistema ed evitare scatti.
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
