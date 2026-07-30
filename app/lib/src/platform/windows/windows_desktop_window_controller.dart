import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:aura_core/aura_core.dart';
import 'package:screen_retriever/screen_retriever.dart' as sr;
import 'package:window_manager/window_manager.dart' as wm;

/// Implementazione concreta per Windows del [DesktopWindowController].
///
/// Utilizza `window_manager` e `screen_retriever` per la gestione delle finestre nativa su Windows.
final class WindowsDesktopWindowController
    with wm.WindowListener
    implements DesktopWindowController {
  final StreamController<DesktopWindowEvent> _eventController =
      StreamController<DesktopWindowEvent>.broadcast();

  bool _initialized = false;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    if (Platform.isWindows) {
      await wm.windowManager.ensureInitialized();
      wm.windowManager.addListener(this);
      await wm.windowManager.setPreventClose(true);
      await wm.windowManager.setMinimumSize(const Size(
        WindowGeometryValidator.minLogicalWidth,
        WindowGeometryValidator.minLogicalHeight,
      ));
    }
    _initialized = true;
  }

  @override
  Future<ActiveWindowMode> getActiveMode() async {
    if (!Platform.isWindows) return ActiveWindowMode.windowed;
    final isFS = await wm.windowManager.isFullScreen();
    if (isFS) return ActiveWindowMode.borderlessFullscreen;
    final isMax = await wm.windowManager.isMaximized();
    if (isMax) return ActiveWindowMode.maximized;
    return ActiveWindowMode.windowed;
  }

  @override
  Future<WindowGeometry?> getGeometry() async {
    if (!Platform.isWindows) return null;
    final pos = await wm.windowManager.getPosition();
    final size = await wm.windowManager.getSize();
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
    if (!Platform.isWindows) return;
    final isFS = await wm.windowManager.isFullScreen();
    if (isFS) {
      await wm.windowManager.setFullScreen(false);
    }
    final isMax = await wm.windowManager.isMaximized();
    if (isMax) {
      await wm.windowManager.unmaximize();
    }
    _eventController
        .add(const DesktopWindowModeChanged(ActiveWindowMode.windowed));
  }

  @override
  Future<void> maximize() async {
    if (!Platform.isWindows) return;
    final isFS = await wm.windowManager.isFullScreen();
    if (isFS) {
      await wm.windowManager.setFullScreen(false);
    }
    await wm.windowManager.maximize();
    _eventController
        .add(const DesktopWindowModeChanged(ActiveWindowMode.maximized));
  }

  @override
  Future<void> enterBorderlessFullscreen() async {
    if (!Platform.isWindows) return;
    await wm.windowManager.setFullScreen(true);
    _eventController.add(
        const DesktopWindowModeChanged(ActiveWindowMode.borderlessFullscreen));
  }

  @override
  Future<void> exitBorderlessFullscreen() async {
    if (!Platform.isWindows) return;
    await wm.windowManager.setFullScreen(false);
    _eventController
        .add(const DesktopWindowModeChanged(ActiveWindowMode.windowed));
  }

  @override
  Future<void> setGeometry(WindowGeometry geometry) async {
    if (!Platform.isWindows) return;
    await wm.windowManager.setBounds(Rect.fromLTWH(
      geometry.x,
      geometry.y,
      geometry.width,
      geometry.height,
    ));
    _eventController.add(DesktopWindowMovedResized(geometry));
  }

  @override
  Future<List<DisplayDescriptor>> getDisplays() async {
    if (!Platform.isWindows) {
      return const [
        DisplayDescriptor(
          id: 'primary-default',
          name: 'Default Display',
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

    try {
      final wmDisplays = await sr.screenRetriever.getAllDisplays();
      final primary = await sr.screenRetriever.getPrimaryDisplay();

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
    if (!Platform.isWindows) return;
    await wm.windowManager.setPreventClose(false);
    await wm.windowManager.destroy();
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
  void onWindowClose() {
    _eventController.add(const DesktopWindowCloseRequested());
  }

  @override
  Future<void> dispose() async {
    if (Platform.isWindows) {
      wm.windowManager.removeListener(this);
    }
    await _eventController.close();
  }
}
