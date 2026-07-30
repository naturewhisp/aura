import 'package:flutter/material.dart';
import 'package:aura_core/aura_core.dart';
import '../state_management/desktop_shell_controller.dart';

/// Intent per il toggle dello schermo intero senza bordi.
class ToggleFullscreenIntent extends Intent {
  const ToggleFullscreenIntent();
}

/// Intent per l'uscita dallo schermo intero tramite tasto ESC.
class ExitFullscreenIntent extends Intent {
  const ExitFullscreenIntent();
}

/// Azione che attiva o disattiva la modalità borderless fullscreen.
class ToggleFullscreenAction extends Action<ToggleFullscreenIntent> {
  final DesktopShellController shellController;

  ToggleFullscreenAction(this.shellController);

  @override
  Object? invoke(ToggleFullscreenIntent intent) {
    shellController.toggleBorderlessFullscreen();
    return null;
  }
}

/// Azione per il tasto ESC: se in fullscreen esce dalla modalità, altrimenti propaga l'evento alla UI.
class ExitFullscreenAction extends Action<ExitFullscreenIntent> {
  final DesktopShellController shellController;

  ExitFullscreenAction(this.shellController);

  @override
  Object? invoke(ExitFullscreenIntent intent) {
    if (shellController.state.activeMode ==
        ActiveWindowMode.borderlessFullscreen) {
      shellController.exitBorderlessFullscreen();
      return null;
    }
    // Se non si trova in fullscreen, restituisce null senza consumare l'evento per consentire la propagazione.
    return null;
  }

  @override
  bool isEnabled(ExitFullscreenIntent intent) {
    // Abilitato solo se la finestra è in modalità borderless fullscreen per evitare di bloccare l'Escape nei dialoghi
    return shellController.state.activeMode ==
        ActiveWindowMode.borderlessFullscreen;
  }
}
