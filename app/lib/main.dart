import 'package:flutter/material.dart';
import 'package:aura_core/aura_core.dart';
import 'src/state_management/game_controller_notifier.dart';
import 'src/screens/terminal_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize core game state
  final initialState = GameState.initial(
    sessionId: "app-session-${DateTime.now().millisecondsSinceEpoch}",
    aiIdentityId: "panopticon",
    targetObjectiveId: "tabula_rasa",
  );

  // Initialize inference bridge (defaulting to local LM Studio endpoint)
  final apiBridge = LocalApiInferenceBridge(
    baseUrl: "http://127.0.0.1:1234",
  );

  // Initialize state management wrapper
  final controllerNotifier = GameControllerNotifier(
    bridge: apiBridge,
    initialState: initialState,
  );

  // Discover and route models dynamically
  await controllerNotifier.initializeModels();

  runApp(AuraApp(notifier: controllerNotifier));
}

class AuraApp extends StatelessWidget {
  final GameControllerNotifier notifier;

  const AuraApp({
    Key key,
    required this.notifier,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'A.U.R.A.',
      debugShowCheckedModeBanner: false,
      // Retro Terminal Theme Config
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        primaryColor: const Color(0xFF00FF66), // Phosphor green
        fontFamily: 'monospace', // Enforce monospace system font fallback
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Color(0xFF00FF66), fontFamily: 'monospace'),
          bodyMedium: TextStyle(color: Color(0xFF00FF66), fontFamily: 'monospace'),
        ),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00FF66),
          secondary: Color(0xFFFFB000), // Amber
          background: Colors.black,
        ),
      ),
      home: TerminalScreen(notifier: notifier),
    );
  }
}
