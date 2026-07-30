import 'desktop_window_event.dart';
import 'display_descriptor.dart';
import 'window_geometry.dart';
import 'window_mode.dart';

/// Interfaccia astratta di controllo della finestra desktop platform-neutral.
abstract interface class DesktopWindowController {
  Future<void> initialize();
  Future<ActiveWindowMode> getActiveMode();
  Future<WindowGeometry?> getGeometry();

  Future<void> setWindowed();
  Future<void> maximize();
  Future<void> enterBorderlessFullscreen();
  Future<void> exitBorderlessFullscreen();

  Future<void> setGeometry(WindowGeometry geometry);
  Future<List<DisplayDescriptor>> getDisplays();

  /// Chiude e distrugge la finestra nativa disabilitando preventClose se attivo.
  Future<void> closeWindow();

  Stream<DesktopWindowEvent> get events;
  Future<void> dispose();
}
