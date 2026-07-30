import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'package:aura_app/src/platform/desktop_shell_provider.dart';

/// Un widget che renderizza una griglia CRT con scanline e flicker opzionale.
///
/// Quando [flicker] è `true`, l'opacità delle scanline oscilla in modo
/// pseudo-casuale simulando instabilità del segnale. L'animazione interna
/// si ripete ogni 100 ms per mantenersi sincrona con i frame tipici di un
/// CRT monitor emulato.
///
/// Il widget è sempre non interattivo ([IgnorePointer]).
class CrtGridOverlay extends StatefulWidget {
  /// Se `true`, l'opacità della griglia fluttua per simulare instabilità.
  final bool flicker;

  /// Costruisce un [CrtGridOverlay] con il parametro di flicker fornito.
  const CrtGridOverlay({
    super.key,
    required this.flicker,
  });

  @override
  State<CrtGridOverlay> createState() => _CrtGridOverlayState();
}

class _CrtGridOverlayState extends State<CrtGridOverlay>
    with SingleTickerProviderStateMixin {
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
    final shellController = DesktopShellProvider.maybeOf(context);

    Widget buildInner() {
      final bool reduceGraphics =
          shellController != null && shellController.state.reduceGraphicEffects;
      final bool unfocusedReduce = shellController != null &&
          shellController.state.reduceAnimationsOnUnfocus &&
          (!shellController.state.focused || shellController.state.minimized);

      if (reduceGraphics) {
        return const SizedBox.shrink();
      }

      final bool isFlickering = widget.flicker && !unfocusedReduce;

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

    if (shellController != null) {
      return ListenableBuilder(
        listenable: shellController,
        builder: (context, _) => buildInner(),
      );
    }

    return buildInner();
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
