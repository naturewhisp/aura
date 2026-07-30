import 'package:meta/meta.dart';

/// Rappresentazione immutabile della posizione e dimensione della finestra.
@immutable
final class WindowGeometry {
  final double x;
  final double y;
  final double width;
  final double height;
  final String? monitorId;
  final double? displayScale;

  const WindowGeometry({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.monitorId,
    this.displayScale,
  });

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'width': width,
        'height': height,
        if (monitorId != null) 'monitorId': monitorId,
        if (displayScale != null) 'displayScale': displayScale,
      };

  factory WindowGeometry.fromJson(Map<String, dynamic> json) {
    return WindowGeometry(
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      width: (json['width'] as num).toDouble(),
      height: (json['height'] as num).toDouble(),
      monitorId: json['monitorId'] as String?,
      displayScale: json['displayScale'] != null
          ? (json['displayScale'] as num).toDouble()
          : null,
    );
  }

  WindowGeometry copyWith({
    double? x,
    double? y,
    double? width,
    double? height,
    String? monitorId,
    double? displayScale,
  }) {
    return WindowGeometry(
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
      monitorId: monitorId ?? this.monitorId,
      displayScale: displayScale ?? this.displayScale,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WindowGeometry &&
          runtimeType == other.runtimeType &&
          x == other.x &&
          y == other.y &&
          width == other.width &&
          height == other.height &&
          monitorId == other.monitorId &&
          displayScale == other.displayScale;

  @override
  int get hashCode => Object.hash(x, y, width, height, monitorId, displayScale);

  @override
  String toString() =>
      'WindowGeometry(x: $x, y: $y, width: $width, height: $height, monitorId: $monitorId, scale: $displayScale)';
}
