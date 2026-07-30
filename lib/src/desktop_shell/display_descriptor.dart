import 'package:meta/meta.dart';

/// Descrittore immutabile di un monitor/display connesso al sistema.
@immutable
final class DisplayDescriptor {
  final String id;
  final String name;
  final double x;
  final double y;
  final double width;
  final double height;
  final double visibleX;
  final double visibleY;
  final double visibleWidth;
  final double visibleHeight;
  final double scaleFactor;
  final bool isPrimary;

  const DisplayDescriptor({
    required this.id,
    required this.name,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.visibleX,
    required this.visibleY,
    required this.visibleWidth,
    required this.visibleHeight,
    required this.scaleFactor,
    required this.isPrimary,
  });

  /// Calcola l'area di intersezione in pixel logici tra questo display ed una geometria.
  double intersectionAreaWith(
    double wx,
    double wy,
    double wwidth,
    double wheight,
  ) {
    final interLeft = x > wx ? x : wx;
    final interTop = y > wy ? y : wy;
    final interRight =
        (x + width) < (wx + wwidth) ? (x + width) : (wx + wwidth);
    final interBottom =
        (y + height) < (wy + wheight) ? (y + height) : (wy + wheight);

    final interWidth = interRight - interLeft;
    final interHeight = interBottom - interTop;

    if (interWidth <= 0 || interHeight <= 0) return 0.0;
    return interWidth * interHeight;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DisplayDescriptor &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          x == other.x &&
          y == other.y &&
          width == other.width &&
          height == other.height &&
          visibleX == other.visibleX &&
          visibleY == other.visibleY &&
          visibleWidth == other.visibleWidth &&
          visibleHeight == other.visibleHeight &&
          scaleFactor == other.scaleFactor &&
          isPrimary == other.isPrimary;

  @override
  int get hashCode => Object.hash(
        id,
        x,
        y,
        width,
        height,
        visibleX,
        visibleY,
        visibleWidth,
        visibleHeight,
        scaleFactor,
        isPrimary,
      );
}
