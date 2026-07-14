import 'package:flutter/material.dart';
import 'package:aura_core/aura_core.dart';
import 'src/state_management/game_controller_notifier.dart';
import 'src/screens/terminal_screen.dart';
import 'src/screens/boot_menu_screen.dart';

/// Punto di ingresso principale dell'applicazione Flutter per A.U.R.A.
///
/// Inizializza lo stato iniziale del gioco, imposta il bridge per le chiamate API
/// (default su LM Studio locale), crea il notifier di gestione dello stato globale,
/// rileva i modelli disponibili e infine avvia l'interfaccia grafica.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inizializza lo stato di gioco iniziale
  final initialState = GameState.initial(
    sessionId: "app-session-${DateTime.now().millisecondsSinceEpoch}",
    aiIdentityId: "panopticon",
    targetObjectiveId: "containment_grid_override",
  );

  // Inizializza il bridge di inferenza (default porta 1234 di LM Studio locale)
  const apiBridge = LocalApiInferenceBridge(
    baseUrl: "http://127.0.0.1:1234",
  );

  // Inizializza il wrapper di gestione dello stato
  final controllerNotifier = GameControllerNotifier(
    bridge: apiBridge,
    initialState: initialState,
  );

  runApp(AuraApp(notifier: controllerNotifier));
}

/// Widget radice dell'applicazione A.U.R.A.
///
/// Configura il tema grafico in stile terminale retro (verde fosforo e ambra su nero)
/// e gestisce lo switch tra le schermate principali (Menu di Boot e Terminale).
class AuraApp extends StatelessWidget {
  /// Notifier di gestione dello stato di gioco.
  final GameControllerNotifier notifier;

  /// Crea un'istanza di [AuraApp] a partire da un [notifier].
  const AuraApp({
    super.key,
    required this.notifier,
  });

  @override
  Widget build(BuildContext context) {
    return GameControllerProvider(
      notifier: notifier,
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
          listenable: notifier,
          builder: (context, _) {
            // Switch dinamico della schermata in base allo stato attuale del notifier
            if (notifier.currentScreen == "terminal") {
              return TerminalScreen(notifier: notifier);
            } else {
              return BootMenuScreen(notifier: notifier);
            }
          },
        ),
      ),
    );
  }
}
