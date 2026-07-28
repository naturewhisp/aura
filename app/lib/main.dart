import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:aura_core/aura_offline.dart';
import 'src/state_management/game_controller_notifier.dart';
import 'src/screens/terminal_screen.dart';
import 'src/screens/boot_menu_screen.dart';

/// Punto di ingresso principale dell'applicazione Flutter per A.U.R.A.
///
/// Inizializza lo stato di gioco e delega la selezione ed assemblaggio delle dipendenze
/// al composition root esplicito [ApplicationBootstrap].
void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Inizializza lo stato di gioco iniziale
  final initialState = GameState.initial(
    sessionId: "app-session-${DateTime.now().millisecondsSinceEpoch}",
    aiIdentityId: "panopticon",
    targetObjectiveId: "containment_grid_override",
  );

  // Avvia immediatamente l'applicazione con il notifier iniziale.
  // Il bootstrap managed dual-process dei modelli viene eseguito in modo
  // asincrono nello schermo di Boot di BootMenuScreen, fornendo log in tempo reale.
  final controllerNotifier = GameControllerNotifier(
    initialState: initialState,
  );

  runApp(AuraApp(notifier: controllerNotifier));
}

/// Widget radice dell'applicazione A.U.R.A.
///
/// Configura il tema grafico in stile terminale retro (verde fosforo e ambra su nero)
/// e possiede il ciclo di vita dell'applicazione intercettando le richieste di uscita del sistema (didRequestAppExit).
class AuraApp extends StatefulWidget {
  /// Notifier di gestione dello stato di gioco.
  final GameControllerNotifier notifier;

  /// Crea un'istanza di [AuraApp] a partire da un [notifier].
  const AuraApp({
    super.key,
    required this.notifier,
  });

  @override
  State<AuraApp> createState() => _AuraAppState();
}

class _AuraAppState extends State<AuraApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.notifier.dispose();
    super.dispose();
  }

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    try {
      await widget.notifier.shutdown();
    } on ApplicationBootstrapException catch (e) {
      debugPrint('[APP] Shutdown delle risorse fallito: ${e.failure.message}');
    } catch (_) {
      debugPrint(
          '[APP] Shutdown delle risorse fallito per un errore inatteso.');
    }
    return AppExitResponse.exit;
  }

  @override
  Widget build(BuildContext context) {
    return GameControllerProvider(
      notifier: widget.notifier,
      child: MaterialApp(
        title: 'A.U.R.A.',
        debugShowCheckedModeBanner: false,
        // Configurazione del tema grafico retro terminale
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: Colors.black,
          primaryColor: const Color(0xFF00FF66), // Verde fosforo
          fontFamily:
              'monospace', // Enfatizza il font a spaziatura fissa di sistema
          textTheme: const TextTheme(
            bodyLarge:
                TextStyle(color: Color(0xFF00FF66), fontFamily: 'monospace'),
            bodyMedium:
                TextStyle(color: Color(0xFF00FF66), fontFamily: 'monospace'),
          ),
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF00FF66),
            secondary: Color(0xFFFFB000), // Ambra
            surface: Colors.black,
          ),
        ),
        home: ListenableBuilder(
          listenable: widget.notifier,
          builder: (context, _) {
            // Switch dinamico della schermata in base allo stato attuale del notifier
            if (widget.notifier.currentScreen == "terminal") {
              return TerminalScreen(notifier: widget.notifier);
            } else {
              return BootMenuScreen(notifier: widget.notifier);
            }
          },
        ),
      ),
    );
  }
}
