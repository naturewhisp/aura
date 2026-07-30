import 'package:flutter/material.dart';
import '../state_management/desktop_shell_controller.dart';

/// InheritedWidget per fornire il [DesktopShellController] nell'albero dei widget.
class DesktopShellProvider extends InheritedWidget {
  final DesktopShellController controller;

  const DesktopShellProvider({
    super.key,
    required this.controller,
    required super.child,
  });

  static DesktopShellController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<DesktopShellProvider>()
        ?.controller;
  }

  static DesktopShellController of(BuildContext context) {
    final result = maybeOf(context);
    assert(result != null, 'Nessun DesktopShellProvider trovato nel contesto.');
    return result!;
  }

  @override
  bool updateShouldNotify(DesktopShellProvider oldWidget) {
    return controller != oldWidget.controller;
  }
}
