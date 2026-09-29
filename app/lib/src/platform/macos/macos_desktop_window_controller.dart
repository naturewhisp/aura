import 'dart:async';
import 'package:flutter/material.dart';
import 'package:aura_core/aura_core.dart';
import 'package:window_manager/window_manager.dart' as wm;
import '../desktop_window_bindings.dart';

/// Implementazione per Apple macOS del [DesktopWindowController].
///
/// Utilizza l'astrazione [DesktopWindowBindings] per delegare a `window_manager`
/// e `screen_retriever`, consentendo l'adattamento delle specificità di windowing macOS
/// (AppKit native fullscreen, gestione preventiva della chiusura e testabilità con fake bindings).
final class MacOSDesktopWindowController
    with wm.WindowListener
    implements DesktopWindowController {
  final DesktopWindowBindings _bindings;
  final StreamController<DesktopWindowEvent> _eventController =
      StreamController<DesktopWindowEvent>.broadcast();

  bool _initialized = false;

  MacOSDesktopWindowController({DesktopWindowBindings? bindings})
      : _bindings = bindings ?? const WindowManagerDesktopWindowBindings();

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    await _bindings.ensureInitialized();
    _bindings.addListener(this);
    await _bindings.setPreventClose(true);
    await _bindings.setMinimumSize(const Size(
      WindowGeometryValidator.minLogicalWidth,
      WindowGeometryValidator.minLogicalHeight,
    ));
    _initialized = true;
  }

  @override
  Future<ActiveWindowMode> getActiveMode() async {
    final isFS = await _bindings.isFullScreen();
    if (isFS) return ActiveWindowMode.borderlessFullscreen;
    final isMax = await _bindings.isMaximized();
    if (isMax) return ActiveWindowMode.maximized;
    return ActiveWindowMode.windowed;
  }

  @override
  Future<WindowGeometry?> getGeometry() async {
    final pos = await _bindings.getPosition();
    final size = await _bindings.getSize();
    final displays = await getDisplays();
    final currentDisplay = displays.firstWhere(
      (d) =>
          d.intersectionAreaWith(pos.dx, pos.dy, size.width, size.height) > 0,
      orElse: () =>
          displays.firstWhere((d) => d.isPrimary, orElse: () => displays.first),
    );

    return WindowGeometry(
      x: pos.dx,
      y: pos.dy,
      width: size.width,
      height: size.height,
      monitorId: currentDisplay.id,
      displayScale: currentDisplay.scaleFactor,
    );
  }

  @override
  Future<void> setWindowed() async {
    final isFS = await _bindings.isFullScreen();
    if (isFS) {
      await _bindings.setFullScreen(false);
    }
    final isMax = await _bindings.isMaximized();
    if (isMax) {
      await _bindings.unmaximize();
    }
    _eventController
        .add(const DesktopWindowModeChanged(ActiveWindowMode.windowed));
  }

  @override
  Future<void> maximize() async {
    final isFS = await _bindings.isFullScreen();
    if (isFS) {
      await _bindings.setFullScreen(false);
    }
    await _bindings.maximize();
    _eventController
        .add(const DesktopWindowModeChanged(ActiveWindowMode.maximized));
  }

  @override
  Future<void> enterBorderlessFullscreen() async {
    // Su macOS, la semantica a pieno schermo mappa sul fullscreen nativo AppKit
    await _bindings.setFullScreen(true);
    _eventController.add(
        const DesktopWindowModeChanged(ActiveWindowMode.borderlessFullscreen));
  }

  @override
  Future<void> exitBorderlessFullscreen() async {
    await _bindings.setFullScreen(false);
    _eventController
        .add(const DesktopWindowModeChanged(ActiveWindowMode.windowed));
  }

  @override
  Future<void> setGeometry(WindowGeometry geometry) async {
    await _bindings.setBounds(Rect.fromLTWH(
      geometry.x,
      geometry.y,
      geometry.width,
      geometry.height,
    ));
    _eventController.add(DesktopWindowMovedResized(geometry));
  }

  @override
  Future<List<DisplayDescriptor>> getDisplays() async {
    try {
      final wmDisplays = await _bindings.getAllDisplays();
      final primary = await _bindings.getPrimaryDisplay();

      return wmDisplays.map((d) {
        final isPrim = d.id == primary.id ||
            (d.visiblePosition?.dx == 0 && d.visiblePosition?.dy == 0);
        final vx = d.visiblePosition?.dx ?? 0.0;
        final vy = d.visiblePosition?.dy ?? 0.0;
        final vw = d.visibleSize?.width ?? d.size.width;
        final vh = d.visibleSize?.height ?? d.size.height;
        final scale = d.scaleFactor?.toDouble() ?? 1.0;

        return DisplayDescriptor(
          id: d.id.toString(),
          name: d.name ?? 'Display ${d.id}',
          x: vx,
          y: vy,
          width: d.size.width,
          height: d.size.height,
          visibleX: vx,
          visibleY: vy,
          visibleWidth: vw,
          visibleHeight: vh,
          scaleFactor: scale,
          isPrimary: isPrim,
        );
      }).toList();
    } catch (_) {
      return const [
        DisplayDescriptor(
          id: 'primary-fallback',
          name: 'Primary Fallback',
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
        )
      ];
    }
  }

  @override
  Future<void> closeWindow() async {
    await _bindings.setPreventClose(false);
    await _bindings.destroy();
  }

  @override
  Stream<DesktopWindowEvent> get events => _eventController.stream;

  // Handlers di WindowListener
  @override
  void onWindowMove() async {
    final geom = await getGeometry();
    if (geom != null) {
      _eventController.add(DesktopWindowMovedResized(geom));
    }
  }

  @override
  void onWindowResize() async {
    final geom = await getGeometry();
    if (geom != null) {
      _eventController.add(DesktopWindowMovedResized(geom));
    }
  }

  @override
  void onWindowFocus() {
    _eventController.add(const DesktopWindowFocusChanged(true));
  }

  @override
  void onWindowBlur() {
    _eventController.add(const DesktopWindowFocusChanged(false));
  }

  @override
  void onWindowMaximize() {
    _eventController
        .add(const DesktopWindowModeChanged(ActiveWindowMode.maximized));
  }

  @override
  void onWindowUnmaximize() {
    _eventController
        .add(const DesktopWindowModeChanged(ActiveWindowMode.windowed));
  }

  @override
  void onWindowMinimize() {
    _eventController.add(const DesktopWindowMinimizeChanged(true));
  }

  @override
  void onWindowRestore() {
    _eventController.add(const DesktopWindowMinimizeChanged(false));
  }

  @override
  void onWindowEnterFullScreen() {
    _eventController.add(
        const DesktopWindowModeChanged(ActiveWindowMode.borderlessFullscreen));
  }

  @override
  void onWindowLeaveFullScreen() {
    _eventController
        .add(const DesktopWindowModeChanged(ActiveWindowMode.windowed));
  }

  @override
  void onWindowClose() {
    _eventController.add(const DesktopWindowCloseRequested());
  }

  @override
  Future<void> dispose() async {
    _bindings.removeListener(this);
    await _eventController.close();
  }
}
