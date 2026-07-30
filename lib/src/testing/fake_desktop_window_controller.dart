import 'dart:async';
import '../desktop_shell/desktop_window_controller.dart';
import '../desktop_shell/desktop_window_event.dart';
import '../desktop_shell/display_descriptor.dart';
import '../desktop_shell/window_geometry.dart';
import '../desktop_shell/window_mode.dart';

/// Fake in-memory del [DesktopWindowController] per widget test e unit test.
final class FakeDesktopWindowController implements DesktopWindowController {
  ActiveWindowMode activeMode;
  WindowGeometry currentGeometry;
  List<DisplayDescriptor> availableDisplays;

  final StreamController<DesktopWindowEvent> _eventController =
      StreamController<DesktopWindowEvent>.broadcast();

  bool isInitialized = false;
  bool isDisposed = false;

  FakeDesktopWindowController({
    this.activeMode = ActiveWindowMode.windowed,
    this.currentGeometry = const WindowGeometry(
      x: 100,
      y: 100,
      width: 1280,
      height: 800,
      monitorId: 'fake-display-1',
      displayScale: 1.0,
    ),
    List<DisplayDescriptor>? displays,
  }) : availableDisplays = displays ??
            const [
              DisplayDescriptor(
                id: 'fake-display-1',
                name: 'Fake Primary Display',
                x: 0,
                y: 0,
                width: 1920,
                height: 1080,
                visibleX: 0,
                visibleY: 0,
                visibleWidth: 1920,
                visibleHeight: 1040,
                scaleFactor: 1.0,
                isPrimary: true,
              ),
            ];

  @override
  Future<void> initialize() async {
    isInitialized = true;
  }

  @override
  Future<ActiveWindowMode> getActiveMode() async => activeMode;

  @override
  Future<WindowGeometry?> getGeometry() async => currentGeometry;

  @override
  Future<void> setWindowed() async {
    activeMode = ActiveWindowMode.windowed;
    _eventController.add(DesktopWindowModeChanged(activeMode));
  }

  @override
  Future<void> maximize() async {
    activeMode = ActiveWindowMode.maximized;
    _eventController.add(DesktopWindowModeChanged(activeMode));
  }

  @override
  Future<void> enterBorderlessFullscreen() async {
    activeMode = ActiveWindowMode.borderlessFullscreen;
    _eventController.add(DesktopWindowModeChanged(activeMode));
  }

  @override
  Future<void> exitBorderlessFullscreen() async {
    activeMode = ActiveWindowMode.windowed;
    _eventController.add(DesktopWindowModeChanged(activeMode));
  }

  @override
  Future<void> setGeometry(WindowGeometry geometry) async {
    currentGeometry = geometry;
    _eventController.add(DesktopWindowMovedResized(geometry));
  }

  bool isWindowClosed = false;

  @override
  Future<void> closeWindow() async {
    isWindowClosed = true;
  }

  @override
  Future<List<DisplayDescriptor>> getDisplays() async => availableDisplays;

  @override
  Stream<DesktopWindowEvent> get events => _eventController.stream;

  void emitEvent(DesktopWindowEvent event) {
    if (!_eventController.isClosed) {
      _eventController.add(event);
    }
  }

  @override
  Future<void> dispose() async {
    isDisposed = true;
    await _eventController.close();
  }
}
