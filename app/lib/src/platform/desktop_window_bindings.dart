import 'dart:ui';
import 'package:screen_retriever/screen_retriever.dart' as sr;
import 'package:window_manager/window_manager.dart' as wm;

/// Facciata a basso livello verso i binding nativi della finestra desktop.
///
/// Disaccoppia i controller di finestra concreti (`MacOSDesktopWindowController`,
/// `WindowsDesktopWindowController`) dalle istanze globali di plugin (`windowManager`,
/// `screenRetriever`), abilitando l'iniezione di fake completi nei test.
abstract interface class DesktopWindowBindings {
  Future<void> ensureInitialized();
  void addListener(wm.WindowListener listener);
  void removeListener(wm.WindowListener listener);
  Future<void> setPreventClose(bool isPreventClose);
  Future<void> setMinimumSize(Size size);
  Future<bool> isFullScreen();
  Future<bool> isMaximized();
  Future<Offset> getPosition();
  Future<Size> getSize();
  Future<void> setFullScreen(bool isFullScreen);
  Future<void> maximize();
  Future<void> unmaximize();
  Future<void> setBounds(Rect bounds);
  Future<void> destroy();

  Future<List<sr.Display>> getAllDisplays();
  Future<sr.Display> getPrimaryDisplay();
}

/// Implementazione predefinita di produzione che delega ai plugin nativi
/// `window_manager` e `screen_retriever`.
class WindowManagerDesktopWindowBindings implements DesktopWindowBindings {
  const WindowManagerDesktopWindowBindings();

  @override
  Future<void> ensureInitialized() => wm.windowManager.ensureInitialized();

  @override
  void addListener(wm.WindowListener listener) =>
      wm.windowManager.addListener(listener);

  @override
  void removeListener(wm.WindowListener listener) =>
      wm.windowManager.removeListener(listener);

  @override
  Future<void> setPreventClose(bool isPreventClose) =>
      wm.windowManager.setPreventClose(isPreventClose);

  @override
  Future<void> setMinimumSize(Size size) =>
      wm.windowManager.setMinimumSize(size);

  @override
  Future<bool> isFullScreen() => wm.windowManager.isFullScreen();

  @override
  Future<bool> isMaximized() => wm.windowManager.isMaximized();

  @override
  Future<Offset> getPosition() => wm.windowManager.getPosition();

  @override
  Future<Size> getSize() => wm.windowManager.getSize();

  @override
  Future<void> setFullScreen(bool isFullScreen) =>
      wm.windowManager.setFullScreen(isFullScreen);

  @override
  Future<void> maximize() => wm.windowManager.maximize();

  @override
  Future<void> unmaximize() => wm.windowManager.unmaximize();

  @override
  Future<void> setBounds(Rect bounds) => wm.windowManager.setBounds(bounds);

  @override
  Future<void> destroy() => wm.windowManager.destroy();

  @override
  Future<List<sr.Display>> getAllDisplays() =>
      sr.screenRetriever.getAllDisplays();

  @override
  Future<sr.Display> getPrimaryDisplay() =>
      sr.screenRetriever.getPrimaryDisplay();
}
