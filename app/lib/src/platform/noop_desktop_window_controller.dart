import 'dart:async';
import 'package:aura_core/aura_core.dart';

/// Implementazione no-op di [DesktopWindowController] per piattaforme non-desktop
/// o ambienti di fallback privi di windowing manager nativo.
final class NoOpDesktopWindowController implements DesktopWindowController {
  const NoOpDesktopWindowController();

  static const List<DisplayDescriptor> _defaultDisplays = [
    DisplayDescriptor(
      id: 'noop-default',
      name: 'Default Display',
      x: 0,
      y: 0,
      width: 1920,
      height: 1080,
      visibleX: 0,
      visibleY: 0,
      visibleWidth: 1920,
      visibleHeight: 1080,
      scaleFactor: 1.0,
      isPrimary: true,
    ),
  ];

  @override
  Future<void> initialize() async {}

  @override
  Future<ActiveWindowMode> getActiveMode() async => ActiveWindowMode.windowed;

  @override
  Future<WindowGeometry?> getGeometry() async => null;

  @override
  Future<void> setWindowed() async {}

  @override
  Future<void> maximize() async {}

  @override
  Future<void> enterBorderlessFullscreen() async {}

  @override
  Future<void> exitBorderlessFullscreen() async {}

  @override
  Future<void> setGeometry(WindowGeometry geometry) async {}

  @override
  Future<List<DisplayDescriptor>> getDisplays() async => _defaultDisplays;

  @override
  Future<void> closeWindow() async {}

  @override
  Stream<DesktopWindowEvent> get events =>
      const Stream<DesktopWindowEvent>.empty();

  @override
  Future<void> dispose() async {}
}
