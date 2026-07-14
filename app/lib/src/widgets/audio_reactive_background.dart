import 'dart:collection';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
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
  State<AudioReactiveBackground> createState() =>
      _AudioReactiveBackgroundState();
}

class _AudioReactiveBackgroundState extends State<AudioReactiveBackground> with TickerProviderStateMixin {
  late final AnimationController _controller;
  late final Ticker _motionTicker;
  Duration? _previousTick;
  double _motionSeconds = 0.0;
  late final DnaRenderCache _renderCache;

  @override
  void initState() {
    super.initState();
    // Inizializza la cache persistente per nodi, rungs, punti e glifi
    _renderCache = DnaRenderCache();

    // Controller per guidare il repaint sincrono con vsync
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3600),
    )..repeat();

    // Ticker che accumula i delta temporali reali tra i frame.
    // Si sospende automaticamente se l'applicazione va in background o se disattivato da TickerMode.
    _motionTicker = createTicker((elapsed) {
      final previous = _previousTick;
      _previousTick = elapsed;

      if (previous != null) {
        final delta = (elapsed - previous).inMicroseconds / 1000000.0;
        // Se il delta è superiore a 100ms, consideriamo che ci sia stata una sospensione
        // o disattivazione del ticker, quindi ignoriamo il salto per garantire continuità visiva.
        if (delta > 0.0 && delta < 0.1) {
          _motionSeconds += delta;
        }
      }
    })..start();

    if (kProfileMode && enableDnaProfiling) {
      DnaFrameProfiler.instance.start();
    }
  }

  @override
  void dispose() {
    if (kProfileMode && enableDnaProfiling) {
      DnaFrameProfiler.instance.stop();
    }
    _motionTicker.dispose();
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
      child: CustomPaint(
        painter: DnaHelixPainter(
          repaintListenable: _controller,
          motionSecondsProvider: () => _motionSeconds,
          alertLevel: alertLevel,
          outcome: outcome,
          cache: _renderCache,
        ),
      ),
    );
  }
}

class DnaHelixPainter extends CustomPainter {
  final Listenable repaintListenable;
  final double Function() motionSecondsProvider;
  final int alertLevel;
  final GameOutcome outcome;
  final DnaRenderCache cache;

  DnaHelixPainter({
    required this.repaintListenable,
    required this.motionSecondsProvider,
    required this.alertLevel,
    required this.outcome,
    required this.cache,
  }) : super(repaint: repaintListenable);

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

  /// Calcola la coordinata X di un determinato indice logico nel mondo.
  /// Esposto per i test di continuità matematica.
  @visibleForTesting
  static double calculatePositionForLogicalIndex({
    required int logicalIndex,
    required double motionSeconds,
    required double scrollPixelsPerSecond,
    required double spacing,
  }) {
    final double scrollDistance = motionSeconds * scrollPixelsPerSecond;
    final int firstLogicalIndex = (scrollDistance / spacing).floor();
    final double fractionalOffset = scrollDistance - firstLogicalIndex * spacing;
    final int localIndex = logicalIndex - firstLogicalIndex;
    return localIndex * spacing - fractionalOffset;
  }

  /// Calcola il tick progressivo per la rotazione del glifo di un nodo.
  /// Esposto per i test.
  @visibleForTesting
  static int calculateGlyphTick({
    required double motionSeconds,
    required int logicalIndex,
    required int wireIndex,
    double glyphChangesPerSecond = 4.0,
    double logicalPhaseOffset = 0.15,
    double wirePhaseOffset = 0.35,
  }) {
    return (motionSeconds * glyphChangesPerSecond +
            logicalIndex * logicalPhaseOffset +
            wireIndex * wirePhaseOffset)
        .floor();
  }

  /// Calcola il pulse dell'inviluppo del beat basato su coseno rialzato.
  /// Esposto per i test.
  @visibleForTesting
  static double calculateBeatPulse({
    required double beatSeconds,
    required double beatDuration,
    double exponent = 3.0,
  }) {
    final double beatPhase = (beatSeconds / beatDuration) % 1.0;
    final double cosinePulse = (1.0 + math.cos(2.0 * math.pi * beatPhase)) / 2.0;
    return math.pow(cosinePulse, exponent).toDouble();
  }

  /// Quantizza la coordinata Z in un bucket di profondità da 0 a bucketCount - 1.
  /// Esposto per i test.
  @visibleForTesting
  static int calculateDepthBucket(double z, int bucketCount) {
    assert(bucketCount > 0);
    final double normalized = (z.clamp(-1.0, 1.0) + 1.0) * 0.5;
    return (normalized * (bucketCount - 1)).round().clamp(0, bucketCount - 1);
  }

  /// Quantizza la dimensione del font al livello più vicino tra quelli predefiniti.
  /// Esposto per i test.
  @visibleForTesting
  static double quantizeFontSize(double value) {
    final double clamped = value.clamp(8.0, 14.0);
    const List<double> fontLevels = [8.0, 9.5, 11.0, 12.5, 14.0];
    
    double nearest = fontLevels.first;
    double distance = (clamped - nearest).abs();

    for (int i = 1; i < fontLevels.length; i++) {
      final double level = fontLevels[i];
      final double candidateDistance = (clamped - level).abs();
      if (candidateDistance < distance) {
        nearest = level;
        distance = candidateDistance;
      }
    }
    return nearest;
  }

  /// Quantizza l'opacità in 4 livelli discreti.
  /// Esposto per i test.
  @visibleForTesting
  static double quantizeAlpha(double alpha) {
    if (alpha <= 0.1) return 0.0;
    if (alpha <= 0.375) return 0.25;
    if (alpha <= 0.625) return 0.5;
    if (alpha <= 0.875) return 0.75;
    return 1.0;
  }

  /// Quantizza il livello di glow basato sul raggio del glow e sullo stato flash.
  /// Esposto per i test.
  @visibleForTesting
  static DnaGlowLevel getGlowLevel(double glowRadius, bool isFlash) {
    if (isFlash) return DnaGlowLevel.flash;
    if (glowRadius <= 0.1) return DnaGlowLevel.none;
    if (glowRadius <= 4.0) return DnaGlowLevel.low;
    if (glowRadius <= 8.0) return DnaGlowLevel.medium;
    return DnaGlowLevel.high;
  }

  /// Quantizza l'avanzamento dell'allerta in 6 livelli stabili.
  /// Esposto per i test.
  @visibleForTesting
  static double quantizeAlertProgress(double progress) {
    return (progress * 5.0).roundToDouble() / 5.0;
  }

  /// Verifica se un nodo è visibile orizzontalmente nel canvas.
  /// Esposto per i test.
  @visibleForTesting
  static bool isNodeVisible({
    required double x,
    required double radius,
    required double canvasWidth,
  }) {
    return x + radius >= 0.0 && x - radius <= canvasWidth;
  }

  /// Verifica se un rung è visibile orizzontalmente nel canvas.
  /// Esposto per i test.
  @visibleForTesting
  static bool isRungVisible({
    required double startX,
    required double endX,
    required double margin,
    required double canvasWidth,
  }) {
    final double minX = math.min(startX, endX);
    final double maxX = math.max(startX, endX);
    return maxX + margin >= 0.0 && minX - margin <= canvasWidth;
  }

  /// Risolve il colore corrispondente a una determinata palette semantica.
  /// Esposto per i test.
  @visibleForTesting
  static Color getPaletteColor(DnaGlyphPalette palette, Color mainColor) {
    switch (palette) {
      case DnaGlyphPalette.primary:
        return mainColor;
      case DnaGlyphPalette.cyan:
        return Color.lerp(mainColor, const Color(0xFF00E5FF), 0.3) ?? mainColor;
      case DnaGlyphPalette.lime:
        return Color.lerp(mainColor, const Color(0xFFD4FF00), 0.25) ?? mainColor;
      case DnaGlyphPalette.alert:
        return const Color(0xFFFF003C);
      case DnaGlyphPalette.victory:
        return const Color(0xFF00FF66);
      case DnaGlyphPalette.defeat:
        return const Color(0xFFFF003C);
      case DnaGlyphPalette.whiteFlash:
        return Colors.white;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final double bpm = AudioManager().currentBpm;
    final double actualBpm = bpm > 0 ? bpm : 120.0;
    final double beatDuration = 60.0 / actualBpm;

    final DateTime now = DateTime.now();
    final double motionSeconds = motionSecondsProvider();

    final DateTime trackStart = AudioManager().trackStartTime;
    final double beatSeconds;
    if (trackStart.millisecondsSinceEpoch == 0) {
      beatSeconds = motionSeconds;
    } else {
      final double diff = now.difference(trackStart).inMicroseconds / 1000000.0;
      beatSeconds = diff < 0 ? 0.0 : diff;
    }

    final double beatPulse = DnaHelixPainter.calculateBeatPulse(
      beatSeconds: beatSeconds,
      beatDuration: beatDuration,
    );

    final double alertProgress = (alertLevel / 100.0).clamp(0.0, 1.0);
    final Color mainColor;
    if (outcome == GameOutcome.defeat) {
      mainColor = const Color(0xFFFF003C);
    } else if (outcome == GameOutcome.victory) {
      mainColor = const Color(0xFF00FF66);
    } else {
      mainColor = Color.lerp(
        const Color(0xFF00FF66),
        const Color(0xFFFF003C),
        alertProgress,
      ) ?? const Color(0xFF00FF66);
    }

    final double centerY = size.height / 2.0;
    final double baseAmplitude = size.height * 0.12;
    final double amplitudeBoost = size.height * 0.08;
    final double currentAmplitude = baseAmplitude + (amplitudeBoost * beatPulse);

    const double scrollPixelsPerSecond = 60.0;
    const double phaseSpeed = 2.0;
    const double spacing = 18.0;
    const double omega = 0.015;
    const double twistAmount = 0.35;

    final double scrollDistance = motionSeconds * scrollPixelsPerSecond;
    final int firstLogicalIndex = (scrollDistance / spacing).floor();
    final double fractionalOffset = scrollDistance - firstLogicalIndex * spacing;

    final double phase = (motionSeconds * phaseSpeed) + (beatPulse * twistAmount);

    final int totalPoints = (size.width / spacing).ceil();
    const int extraPoints = 2;
    final int pointCount = totalPoints + extraPoints * 2;

    // 1. Assicura che la cache geometrica abbia capacità sufficiente
    cache.ensureCapacity(pointCount);
    cache.beginFrame();

    final List<double> wireOffsets = [
      0.0,
      2.0 * math.pi / 3.0,
      4.0 * math.pi / 3.0,
    ];

    // 2. Calcola le coordinate di tutti i punti in modalità mutabile O(1)
    for (int w = 0; w < 3; w++) {
      final double wireOffset = wireOffsets[w];
      final List<MutableHelixPoint> wireList = w == 0
          ? cache.wire0
          : w == 1
              ? cache.wire1
              : cache.wire2;

      for (int localIndex = -extraPoints; localIndex < totalPoints + extraPoints; localIndex++) {
        final int pointIndexInList = localIndex + extraPoints;
        final MutableHelixPoint point = wireList[pointIndexInList];

        final double x = localIndex * spacing - fractionalOffset;
        final int logicalIndex = firstLogicalIndex + localIndex;
        final double worldX = logicalIndex * spacing;

        final double angle = (worldX * omega) + phase + wireOffset;
        double y = centerY + currentAmplitude * math.sin(angle);

        if (alertLevel > 10) {
          final double glitch = math.sin(worldX * 0.3 + motionSeconds * 25.0) * (spacing * 0.4) * alertProgress;
          y += glitch;
        }

        final double z = math.cos(angle);

        point.x = x;
        point.y = y;
        point.z = z;
        point.logicalIndex = logicalIndex;
      }
    }

    final int elapsedTick = motionSeconds.floor();
    final double quantizedAlertProgress = DnaHelixPainter.quantizeAlertProgress(alertProgress);

    // Metà dimensione del glifo quantizzato max (14) + max blur radius (12) + stroke
    const double maxVisualRadius = 28.0;

    // 3. Popola i depth buckets con handle interi compatti
    for (int localIndex = -extraPoints; localIndex < totalPoints + extraPoints; localIndex++) {
      final int pointIndexInList = localIndex + extraPoints;
      final MutableHelixPoint p0 = cache.wire0[pointIndexInList];
      final MutableHelixPoint p1 = cache.wire1[pointIndexInList];
      final MutableHelixPoint p2 = cache.wire2[pointIndexInList];

      // 3.1 Nodi dei filamenti
      for (int w = 0; w < 3; w++) {
        final MutableHelixPoint point = w == 0 ? p0 : w == 1 ? p1 : p2;

        // Culling conservativo orizzontale
        if (!DnaHelixPainter.isNodeVisible(x: point.x, radius: maxVisualRadius, canvasWidth: size.width)) {
          continue;
        }

        final double normalizedZ = (point.z + 1.0) / 2.0;
        final double trailFactor = (point.x / size.width).clamp(0.0, 1.0);
        final double baseOpacity = (normalizedZ * 0.5) + 0.15;
        final double positionOpacity = baseOpacity * (0.3 + 0.7 * trailFactor);
        final double opacity = (positionOpacity + 0.25 * beatPulse).clamp(0.0, 1.0);

        // Salta elementi con opacità trascurabile
        if (opacity <= 0.01) {
          continue;
        }

        final double fontSize = (normalizedZ * 6.0) + 8.0;
        final double quantizedFontSize = DnaHelixPainter.quantizeFontSize(fontSize);
        final double quantizedAlpha = DnaHelixPainter.quantizeAlpha(opacity);

        final DnaGlyphPalette palette;
        if (outcome == GameOutcome.victory) {
          palette = DnaGlyphPalette.victory;
        } else if (outcome == GameOutcome.defeat) {
          palette = DnaGlyphPalette.defeat;
        } else {
          palette = w == 0 ? DnaGlyphPalette.primary : w == 1 ? DnaGlyphPalette.cyan : DnaGlyphPalette.lime;
        }

        // Lampi di luce e Glow
        final bool isFlashFrame = beatPulse > 0.5;
        final bool isFlashPoint = (point.logicalIndex + elapsedTick) % 6 == 0;
        final bool drawFlash = isFlashFrame && isFlashPoint;

        final double glowRadius = beatPulse * 12.0;
        final DnaGlowLevel glowLevel = DnaHelixPainter.getGlowLevel(glowRadius, drawFlash);

        final int glyphTick = DnaHelixPainter.calculateGlyphTick(
          motionSeconds: motionSeconds,
          logicalIndex: point.logicalIndex,
          wireIndex: w,
        );

        final int charIndex = (point.logicalIndex * 31 + w * 17 + glyphTick * 7).abs() % _matrixChars.length;
        final String char = _matrixChars[charIndex];

        // Acquisisci nodo dal pool
        final int nodeIdx = cache.activeNodeCount;
        final DnaNodeElement node = cache.acquireNode();
        node.populate(
          x: point.x,
          y: point.y,
          z: point.z,
          char: char,
          fontSize: quantizedFontSize,
          palette: palette,
          alpha: quantizedAlpha,
          glowLevel: glowLevel,
        );

        final int bucketIndex = DnaHelixPainter.calculateDepthBucket(point.z, 16);
        cache.depthBuckets[bucketIndex].add(DnaRenderHandle.packNode(nodeIdx));
      }

      // 3.2 Collegamenti 3D alternati (rungs)
      final int firstPointIndex = p0.logicalIndex;
      final int mod = ((firstPointIndex % 3) + 3) % 3;
      final MutableHelixPoint start;
      final MutableHelixPoint end;
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

      final double avgZ = (start.z + end.z) / 2.0;
      final double avgX = (start.x + end.x) / 2.0;
      final double normalizedZ = (avgZ + 1.0) / 2.0;
      final double trailFactor = (avgX / size.width).clamp(0.0, 1.0);
      
      final double baseOpacity = (normalizedZ * 0.35) + 0.1;
      final double positionOpacity = baseOpacity * (0.3 + 0.7 * trailFactor);
      final double opacity = (positionOpacity + 0.15 * beatPulse).clamp(0.0, 1.0);

      // Culling rung passante
      if (!DnaHelixPainter.isRungVisible(startX: start.x, endX: end.x, margin: maxVisualRadius, canvasWidth: size.width)) {
        continue;
      }

      if (opacity <= 0.01) {
        continue;
      }

      final double thickness = (normalizedZ * 1.5 + 0.5) + (1.5 * beatPulse);

      final Color cStart = _getFilamentColor(start.wireIndex, mainColor, outcome);
      final Color cEnd = _getFilamentColor(end.wireIndex, mainColor, outcome);
      final Color rungBaseColor = Color.lerp(cStart, cEnd, 0.5) ?? mainColor;
      final Color rungColor = rungBaseColor.withValues(alpha: opacity);
      final Color rungGlowColor = rungBaseColor.withValues(alpha: opacity * beatPulse);

      final int rungIdx = cache.activeRungCount;
      final DnaRungElement rung = cache.acquireRung();
      rung.populate(
        startX: start.x,
        startY: start.y,
        endX: end.x,
        endY: end.y,
        thickness: thickness,
        color: rungColor,
        glowColor: rungGlowColor,
        beatPulse: beatPulse,
        opacity: opacity,
      );

      final int bucketIndex = DnaHelixPainter.calculateDepthBucket(avgZ, 16);
      cache.depthBuckets[bucketIndex].add(DnaRenderHandle.packRung(rungIdx));
    }

    // 4. Disegna in ordine dal bucket più lontano (0) a quello più vicino (15) preservando l'interleaving
    for (int b = 0; b < 16; b++) {
      final List<int> bucket = cache.depthBuckets[b];
      for (int i = 0; i < bucket.length; i++) {
        final int handle = bucket[i];
        final int index = DnaRenderHandle.indexOf(handle);

        if (DnaRenderHandle.isNode(handle)) {
          final DnaNodeElement node = cache.nodePool[index];
          // Risolve il TextPainter usando la cache
          final DnaGlyphKey key = DnaGlyphKey(
            node.char,
            node.fontSize,
            node.palette,
            node.alpha,
            node.glowLevel,
            quantizedAlertProgress,
            outcome,
          );

          var tp = cache.glyphCache.get(key);
          if (tp == null) {
            final Color resolvedColor = DnaHelixPainter.getPaletteColor(node.palette, mainColor).withValues(alpha: node.alpha);
            final Color? resolvedGlowColor;
            final double glowRad;
            if (node.glowLevel == DnaGlowLevel.none) {
              resolvedGlowColor = null;
              glowRad = 0.0;
            } else {
              glowRad = node.glowLevel == DnaGlowLevel.low
                  ? 3.0
                  : node.glowLevel == DnaGlowLevel.medium
                      ? 7.0
                      : 12.0;
              resolvedGlowColor = node.glowLevel == DnaGlowLevel.flash
                  ? Colors.white.withValues(alpha: node.alpha)
                  : DnaHelixPainter.getPaletteColor(node.palette, mainColor).withValues(alpha: node.alpha);
            }

            tp = TextPainter(
              textDirection: TextDirection.ltr,
              text: TextSpan(
                text: node.char,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: node.fontSize,
                  fontWeight: FontWeight.bold,
                  color: resolvedColor,
                  shadows: (resolvedGlowColor != null && glowRad > 0.1)
                      ? [
                          Shadow(
                            color: resolvedGlowColor,
                            blurRadius: glowRad,
                          ),
                        ]
                      : null,
                ),
              ),
            );
            tp.layout();
            cache.glyphCache.put(key, tp);
          }

          final double dx = node.x - tp.width / 2.0;
          final double dy = node.y - tp.height / 2.0;
          tp.paint(canvas, Offset(dx, dy));

        } else {
          final DnaRungElement rung = cache.rungPool[index];
          // Disegna il rung riutilizzando Paint e aggiornando solo i parametri necessari
          if (rung.beatPulse > 0.1) {
            cache.rungGlowPaint
              ..color = rung.glowColor.withValues(alpha: rung.opacity * rung.beatPulse * 0.22)
              ..strokeWidth = rung.thickness + 4.0 * rung.beatPulse;
            canvas.drawLine(Offset(rung.startX, rung.startY), Offset(rung.endX, rung.endY), cache.rungGlowPaint);
          }

          cache.rungPaint
            ..color = rung.color
            ..strokeWidth = rung.thickness;
          canvas.drawLine(Offset(rung.startX, rung.startY), Offset(rung.endX, rung.endY), cache.rungPaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant DnaHelixPainter oldDelegate) {
    // Repainta solo al variare dei parametri strutturali del widget
    return oldDelegate.alertLevel != alertLevel ||
        oldDelegate.outcome != outcome ||
        oldDelegate.repaintListenable != repaintListenable ||
        oldDelegate.cache != cache;
  }
}

final class MutableHelixPoint {
  double x = 0.0;
  double y = 0.0;
  double z = 0.0;
  int logicalIndex = 0;
  int wireIndex = 0;
}

final class DnaNodeElement {
  double x = 0.0;
  double y = 0.0;
  double z = 0.0;
  String char = '';
  double fontSize = 0.0;
  DnaGlyphPalette palette = DnaGlyphPalette.primary;
  double alpha = 0.0;
  DnaGlowLevel glowLevel = DnaGlowLevel.none;

  void populate({
    required double x,
    required double y,
    required double z,
    required String char,
    required double fontSize,
    required DnaGlyphPalette palette,
    required double alpha,
    required DnaGlowLevel glowLevel,
  }) {
    this.x = x;
    this.y = y;
    this.z = z;
    this.char = char;
    this.fontSize = fontSize;
    this.palette = palette;
    this.alpha = alpha;
    this.glowLevel = glowLevel;
  }
}

final class DnaRungElement {
  double startX = 0.0;
  double startY = 0.0;
  double endX = 0.0;
  double endY = 0.0;
  double thickness = 0.0;
  Color color = Colors.transparent;
  Color glowColor = Colors.transparent;
  double beatPulse = 0.0;
  double opacity = 0.0;

  void populate({
    required double startX,
    required double startY,
    required double endX,
    required double endY,
    required double thickness,
    required Color color,
    required Color glowColor,
    required double beatPulse,
    required double opacity,
  }) {
    this.startX = startX;
    this.startY = startY;
    this.endX = endX;
    this.endY = endY;
    this.thickness = thickness;
    this.color = color;
    this.glowColor = glowColor;
    this.beatPulse = beatPulse;
    this.opacity = opacity;
  }
}

enum DnaGlyphPalette {
  primary,
  cyan,
  lime,
  alert,
  victory,
  defeat,
  whiteFlash,
}

enum DnaGlowLevel {
  none,
  low,
  medium,
  high,
  flash,
}

class DnaGlyphKey {
  final String char;
  final double fontSize;
  final DnaGlyphPalette palette;
  final double alpha;
  final DnaGlowLevel glowLevel;
  final double alertProgress;
  final GameOutcome outcome;

  DnaGlyphKey(
    this.char,
    this.fontSize,
    this.palette,
    this.alpha,
    this.glowLevel,
    this.alertProgress,
    this.outcome,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DnaGlyphKey &&
          runtimeType == other.runtimeType &&
          char == other.char &&
          fontSize == other.fontSize &&
          palette == other.palette &&
          alpha == other.alpha &&
          glowLevel == other.glowLevel &&
          alertProgress == other.alertProgress &&
          outcome == other.outcome;

  @override
  int get hashCode => Object.hash(
        char,
        fontSize,
        palette,
        alpha,
        glowLevel,
        alertProgress,
        outcome,
      );
}

class DnaGlyphCache {
  final int capacity;
  final LinkedHashMap<DnaGlyphKey, TextPainter> _entries = LinkedHashMap<DnaGlyphKey, TextPainter>();

  int hits = 0;
  int misses = 0;

  DnaGlyphCache({this.capacity = 1000});

  TextPainter? get(DnaGlyphKey key) {
    final value = _entries.remove(key);
    if (value == null) {
      misses++;
      return null;
    }
    _entries[key] = value;
    hits++;
    return value;
  }

  void put(DnaGlyphKey key, TextPainter value) {
    _entries.remove(key);
    _entries[key] = value;
    while (_entries.length > capacity) {
      _entries.remove(_entries.keys.first);
    }
  }

  int get length => _entries.length;
  double get hitRate => (hits + misses) == 0 ? 0.0 : hits / (hits + misses);
  void clear() => _entries.clear();
}

abstract class DnaRenderHandle {
  static const int nodeMask = 0x00000000;
  static const int rungMask = 0x40000000;
  static const int indexMask = 0x3FFFFFFF;

  static int packNode(int index) {
    assert(index >= 0 && index <= indexMask);
    return nodeMask | (index & indexMask);
  }

  static int packRung(int index) {
    assert(index >= 0 && index <= indexMask);
    return rungMask | (index & indexMask);
  }

  static bool isNode(int handle) => (handle & 0x40000000) == nodeMask;
  static int indexOf(int handle) => handle & indexMask;
}

class DnaRenderCache {
  int _pointCapacity = 0;
  int _nodeCapacity = 0;
  int _rungCapacity = 0;

  // Tre liste stabili di punti mutabili per i 3 fili
  final List<MutableHelixPoint> wire0 = [];
  final List<MutableHelixPoint> wire1 = [];
  final List<MutableHelixPoint> wire2 = [];

  // Pool di elementi preallocati
  final List<DnaNodeElement> nodePool = [];
  final List<DnaRungElement> rungPool = [];

  // Depth buckets
  final List<List<int>> depthBuckets = List.generate(16, (_) => <int>[]);

  // Cache dei glifi
  final DnaGlyphCache glyphCache = DnaGlyphCache();

  int activeNodeCount = 0;
  int activeRungCount = 0;

  // Getter pubblici per i test
  int get pointCapacity => _pointCapacity;
  int get nodeCapacity => _nodeCapacity;
  int get rungCapacity => _rungCapacity;
  int get glyphCacheSize => glyphCache.length;
  int get glyphCacheCapacity => glyphCache.capacity;

  // Paint persistenti
  final Paint rungPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  final Paint rungGlowPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  void ensureCapacity(int requiredPointCount) {
    if (requiredPointCount <= _pointCapacity) return;
    final nextCapacity = _pointCapacity == 0
        ? math.max(requiredPointCount, 64)
        : math.max(requiredPointCount, _pointCapacity * 2);

    _pointCapacity = nextCapacity;
    while (wire0.length < _pointCapacity) {
      wire0.add(MutableHelixPoint()..wireIndex = 0);
      wire1.add(MutableHelixPoint()..wireIndex = 1);
      wire2.add(MutableHelixPoint()..wireIndex = 2);
    }
  }

  void beginFrame() {
    activeNodeCount = 0;
    activeRungCount = 0;
    for (int i = 0; i < 16; i++) {
      depthBuckets[i].clear();
    }
  }

  DnaNodeElement acquireNode() {
    if (activeNodeCount < nodePool.length) {
      return nodePool[activeNodeCount++];
    }
    final nextCapacity = nodePool.isEmpty ? 64 : nodePool.length * 2;
    _nodeCapacity = nextCapacity;
    while (nodePool.length < _nodeCapacity) {
      nodePool.add(DnaNodeElement());
    }
    return nodePool[activeNodeCount++];
  }

  DnaRungElement acquireRung() {
    if (activeRungCount < rungPool.length) {
      return rungPool[activeRungCount++];
    }
    final nextCapacity = rungPool.isEmpty ? 64 : rungPool.length * 2;
    _rungCapacity = nextCapacity;
    while (rungPool.length < _rungCapacity) {
      rungPool.add(DnaRungElement());
    }
    return rungPool[activeRungCount++];
  }
}

const bool enableDnaProfiling = bool.fromEnvironment(
  'AURA_DNA_PROFILE',
  defaultValue: false,
);

class DnaFrameProfiler {
  static DnaFrameProfiler? _instance;
  static DnaFrameProfiler get instance => _instance ??= DnaFrameProfiler._();

  DnaFrameProfiler._();

  bool _running = false;
  final List<FrameTiming> _timings = [];
  TimingsCallback? _callback;

  void start() {
    if (_running) return;
    _running = true;
    _timings.clear();
    _callback = (List<FrameTiming> timings) {
      if (_running) {
        _timings.addAll(timings);
      }
    };
    SchedulerBinding.instance.addTimingsCallback(_callback!);
  }

  void stop() {
    if (!_running) return;
    _running = false;
    if (_callback != null) {
      SchedulerBinding.instance.removeTimingsCallback(_callback!);
      _callback = null;
    }
    _printReport();
  }

  void _printReport() {
    if (_timings.length < 100) {
      debugPrint('[DNA PROFILER] Campione troppo piccolo (${_timings.length} frame). Richiesti almeno 100 frame.');
      return;
    }

    final sample = _timings.skip(10).toList();
    if (sample.isEmpty) return;

    final totalFrames = sample.length;
    final List<double> buildTimes = sample.map((t) => t.buildDuration.inMicroseconds / 1000.0).toList()..sort();
    final List<double> rasterTimes = sample.map((t) => t.rasterDuration.inMicroseconds / 1000.0).toList()..sort();
    final List<double> totalTimes = sample.map((t) => t.totalSpan.inMicroseconds / 1000.0).toList()..sort();

    double p50(List<double> list) => list[(list.length * 0.50).floor()];
    double p95(List<double> list) => list[(list.length * 0.95).floor()];
    double p99(List<double> list) => list[(list.length * 0.99).floor()];

    final framesOver16 = sample.where((t) => t.totalSpan.inMicroseconds > 16667).length;
    final framesOver33 = sample.where((t) => t.totalSpan.inMicroseconds > 33333).length;

    debugPrint('================ DNA HELIX PROFILE REPORT ================');
    debugPrint('Total Sampled Frames (after 10 warmup): $totalFrames');
    debugPrint('Build Duration (ms):  p50: ${p50(buildTimes).toStringAsFixed(2)} | p95: ${p95(buildTimes).toStringAsFixed(2)} | p99: ${p99(buildTimes).toStringAsFixed(2)}');
    debugPrint('Raster Duration (ms): p50: ${p50(rasterTimes).toStringAsFixed(2)} | p95: ${p95(rasterTimes).toStringAsFixed(2)} | p99: ${p99(rasterTimes).toStringAsFixed(2)}');
    debugPrint('Total Span (ms):       p50: ${p50(totalTimes).toStringAsFixed(2)} | p95: ${p95(totalTimes).toStringAsFixed(2)} | p99: ${p99(totalTimes).toStringAsFixed(2)}');
    debugPrint('Janky Frames (>16.67ms): $framesOver16 (${(framesOver16 / totalFrames * 100.0).toStringAsFixed(1)}%)');
    debugPrint('Severe Janky (>33.3ms):  $framesOver33 (${(framesOver33 / totalFrames * 100.0).toStringAsFixed(1)}%)');
    debugPrint('==========================================================');
  }
}
