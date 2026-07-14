import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Un widget che renderizza un effetto pioggia in stile Matrix (Matrix Rain).
///
/// Questo widget è animato costantemente e si adatta responsive alle dimensioni
/// del box contenitore. Preserva l'istanza pseudo-casuale delle gocce per l'intero
/// ciclo di vita del widget.
class MatrixRainBackground extends StatefulWidget {
  /// L'opacità complessiva dell'animazione.
  final double opacity;

  /// Costruisce un [MatrixRainBackground] a partire dall'opacità fornita.
  const MatrixRainBackground({
    super.key,
    required this.opacity,
  });

  @override
  State<MatrixRainBackground> createState() => _MatrixRainBackgroundState();
}

class _MatrixRainBackgroundState extends State<MatrixRainBackground>
    with SingleTickerProviderStateMixin {
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
        chars: List.generate(
          15 + _random.nextInt(15),
          (_) => String.fromCharCode(33 + _random.nextInt(93)),
        ),
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
          ? const Color(0xFFFFFFFF)
              .withValues(alpha: alpha) // Lead character is white
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
