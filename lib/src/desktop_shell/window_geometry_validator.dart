import 'display_descriptor.dart';
import 'window_geometry.dart';

/// Validatore e ricompositore di geometria multi-monitor e DPI safe.
final class WindowGeometryValidator {
  static const double minLogicalWidth = 420.0;
  static const double minLogicalHeight = 500.0;
  static const double defaultLogicalWidth = 1280.0;
  static const double defaultLogicalHeight = 800.0;
  static const double minVisibleArea = 100.0;

  const WindowGeometryValidator();

  /// Valida e ripristina la geometria [saved] rispetto ai display disponibili [displays].
  ///
  /// Restituisce una [WindowGeometry] garantita visibile ed entro i limiti del desktop.
  WindowGeometry validateAndAdjust({
    required WindowGeometry? saved,
    required List<DisplayDescriptor> displays,
  }) {
    if (displays.isEmpty) {
      // Fallback assoluto se nessun display viene restituito dal sistema
      final width =
          saved?.width.clamp(minLogicalWidth, 1920.0) ?? defaultLogicalWidth;
      final height =
          saved?.height.clamp(minLogicalHeight, 1080.0) ?? defaultLogicalHeight;
      return WindowGeometry(
        x: 100.0,
        y: 100.0,
        width: width,
        height: height,
        displayScale: saved?.displayScale,
      );
    }

    final primaryDisplay = displays.firstWhere(
      (d) => d.isPrimary,
      orElse: () => displays.first,
    );

    if (saved == null) {
      return _centerOnDisplay(
        primaryDisplay,
        defaultLogicalWidth,
        defaultLogicalHeight,
      );
    }

    // 1. Clamp dimensioni minime
    final clampedWidth = saved.width.clamp(minLogicalWidth, double.infinity);
    final clampedHeight = saved.height.clamp(minLogicalHeight, double.infinity);

    // 2. Trova il miglior display di destinazione
    DisplayDescriptor targetDisplay = primaryDisplay;

    // Strategia 1: Cerca corrispondenza esatta di monitorId se interseca significativamente
    if (saved.monitorId != null && saved.monitorId!.isNotEmpty) {
      final matching = displays.where((d) => d.id == saved.monitorId);
      if (matching.isNotEmpty) {
        final candidate = matching.first;
        final interArea = candidate.intersectionAreaWith(
          saved.x,
          saved.y,
          clampedWidth,
          clampedHeight,
        );
        if (interArea >= (minVisibleArea * minVisibleArea)) {
          targetDisplay = candidate;
        }
      }
    }

    // Strategia 2: Se non trovato per monitorId, cerca il display con la massima intersezione
    if (targetDisplay == primaryDisplay) {
      double maxArea = 0.0;
      DisplayDescriptor? bestMatch;
      for (final d in displays) {
        final area = d.intersectionAreaWith(
          saved.x,
          saved.y,
          clampedWidth,
          clampedHeight,
        );
        if (area > maxArea) {
          maxArea = area;
          bestMatch = d;
        }
      }
      if (bestMatch != null && maxArea >= (minVisibleArea * minVisibleArea)) {
        targetDisplay = bestMatch;
      }
    }

    // 3. Verifica se la finestra ha una visibilità sufficiente sul targetDisplay
    final currentInter = targetDisplay.intersectionAreaWith(
      saved.x,
      saved.y,
      clampedWidth,
      clampedHeight,
    );

    if (currentInter < (minVisibleArea * minVisibleArea)) {
      // Finestra fuori schermo o visibilità insufficiente -> Centra sul target/primary
      return _centerOnDisplay(targetDisplay, clampedWidth, clampedHeight);
    }

    // 4. Se la finestra è visibile (inclusi monitor a sinistra con coordinate negative),
    // assicura soltanto che la larghezza e l'altezza non superino la work area e che la barra del titolo rimanga raggiungibile.
    final finalWidth = clampedWidth.clamp(
      minLogicalWidth,
      targetDisplay.visibleWidth > minLogicalWidth
          ? targetDisplay.visibleWidth
          : minLogicalWidth,
    );
    final finalHeight = clampedHeight.clamp(
      minLogicalHeight,
      targetDisplay.visibleHeight > minLogicalHeight
          ? targetDisplay.visibleHeight
          : minLogicalHeight,
    );

    // Garantisci che il bordo superiore (y) sia contenuto nell'area visibile del monitor
    double finalX = saved.x;
    double finalY = saved.y;

    if (finalY < targetDisplay.visibleY) {
      finalY = targetDisplay.visibleY;
    } else if (finalY >
        (targetDisplay.visibleY +
            targetDisplay.visibleHeight -
            minVisibleArea)) {
      finalY =
          targetDisplay.visibleY + targetDisplay.visibleHeight - minVisibleArea;
    }

    if ((finalX + finalWidth) < (targetDisplay.visibleX + minVisibleArea)) {
      finalX = targetDisplay.visibleX - finalWidth + minVisibleArea;
    } else if (finalX >
        (targetDisplay.visibleX +
            targetDisplay.visibleWidth -
            minVisibleArea)) {
      finalX =
          targetDisplay.visibleX + targetDisplay.visibleWidth - minVisibleArea;
    }

    return WindowGeometry(
      x: finalX,
      y: finalY,
      width: finalWidth,
      height: finalHeight,
      monitorId: targetDisplay.id,
      displayScale: targetDisplay.scaleFactor,
    );
  }

  WindowGeometry _centerOnDisplay(
    DisplayDescriptor display,
    double desiredWidth,
    double desiredHeight,
  ) {
    final width = desiredWidth.clamp(
      minLogicalWidth,
      display.visibleWidth > minLogicalWidth
          ? display.visibleWidth
          : minLogicalWidth,
    );
    final height = desiredHeight.clamp(
      minLogicalHeight,
      display.visibleHeight > minLogicalHeight
          ? display.visibleHeight
          : minLogicalHeight,
    );

    final x = display.visibleX + ((display.visibleWidth - width) / 2.0);
    final y = display.visibleY + ((display.visibleHeight - height) / 2.0);

    return WindowGeometry(
      x: x,
      y: y,
      width: width,
      height: height,
      monitorId: display.id,
      displayScale: display.scaleFactor,
    );
  }
}
