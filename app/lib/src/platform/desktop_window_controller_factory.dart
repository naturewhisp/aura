import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:aura_core/aura_core.dart';
import 'desktop_host_platform.dart';
import 'desktop_window_bindings.dart';
import 'noop_desktop_window_controller.dart';
import 'windows/windows_desktop_window_controller.dart';
import 'macos/macos_desktop_window_controller.dart';

/// Factory per l'istanziazione del [DesktopWindowController] appropriato in base
/// alla piattaforma host runtime, disaccoppiando il composition root dai dettagli Win32/Darwin.
abstract final class DesktopWindowControllerFactory {
  /// Rileva la piattaforma host corrente.
  @visibleForTesting
  static DesktopHostPlatform detectHostPlatform() {
    if (kIsWeb) return DesktopHostPlatform.other;
    if (Platform.isWindows) return DesktopHostPlatform.windows;
    if (Platform.isMacOS) return DesktopHostPlatform.macos;
    return DesktopHostPlatform.other;
  }

  /// Crea il controller della finestra desktop per la piattaforma runtime attiva.
  static DesktopWindowController create({
    DesktopWindowBindings? customBindings,
  }) {
    return createFor(
      detectHostPlatform(),
      customBindings: customBindings,
    );
  }

  /// Crea il controller per una specifica piattaforma host, con supporto per
  /// binding iniettabili nei test unitari o di integrazione.
  @visibleForTesting
  static DesktopWindowController createFor(
    DesktopHostPlatform platform, {
    DesktopWindowBindings? customBindings,
  }) {
    switch (platform) {
      case DesktopHostPlatform.windows:
        return WindowsDesktopWindowController();
      case DesktopHostPlatform.macos:
        return MacOSDesktopWindowController(
          bindings:
              customBindings ?? const WindowManagerDesktopWindowBindings(),
        );
      case DesktopHostPlatform.other:
        return const NoOpDesktopWindowController();
    }
  }
}
