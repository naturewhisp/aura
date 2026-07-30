import 'package:meta/meta.dart';
import 'window_geometry.dart';
import 'window_mode.dart';

/// Gerarchia sealed di eventi prodotti dal controller della finestra desktop.
@immutable
sealed class DesktopWindowEvent {
  const DesktopWindowEvent();
}

final class DesktopWindowModeChanged extends DesktopWindowEvent {
  final ActiveWindowMode mode;
  const DesktopWindowModeChanged(this.mode);
}

final class DesktopWindowMovedResized extends DesktopWindowEvent {
  final WindowGeometry geometry;
  const DesktopWindowMovedResized(this.geometry);
}

final class DesktopWindowFocusChanged extends DesktopWindowEvent {
  final bool focused;
  const DesktopWindowFocusChanged(this.focused);
}

final class DesktopWindowMinimizeChanged extends DesktopWindowEvent {
  final bool minimized;
  const DesktopWindowMinimizeChanged(this.minimized);
}

final class DesktopWindowCloseRequested extends DesktopWindowEvent {
  const DesktopWindowCloseRequested();
}
