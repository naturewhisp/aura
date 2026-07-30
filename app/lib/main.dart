import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:aura_core/aura_offline.dart';
import 'src/state_management/game_controller_notifier.dart';
import 'src/state_management/desktop_shell_controller.dart';
import 'src/state_management/application_shutdown_coordinator.dart';
import 'src/platform/desktop_shell_provider.dart';
import 'src/platform/desktop_shortcuts.dart';
import 'src/platform/windows/windows_desktop_window_controller.dart';
import 'src/screens/terminal_screen.dart';
import 'src/screens/boot_menu_screen.dart';
import 'src/audio/audio_manager.dart';

/// Punto di ingresso principale dell'applicazione Flutter per A.U.R.A.
void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Inizializza lo stato di gioco iniziale
  final initialState = GameState.initial(
    sessionId: "app-session-${DateTime.now().millisecondsSinceEpoch}",
    aiIdentityId: "panopticon",
    targetObjectiveId: "containment_grid_override",
  );

  final controllerNotifier = GameControllerNotifier(
    initialState: initialState,
  );

  runApp(AuraApp(notifier: controllerNotifier));
}

/// Widget radice dell'applicazione A.U.R.A.
///
/// Gestisce l'assemblaggio dei controller della shell desktop, il tema retro terminale,
/// le scorciatoie da tastiera e l'intercettazione dello shutdown della finestra.
class AuraApp extends StatefulWidget {
  /// Notifier di gestione dello stato di gioco.
  final GameControllerNotifier notifier;

  /// Servizio di rilevamento dipendenze per LlamaServer.
  final LlamaServerDependencyService? dependencyService;

  /// Controller della finestra desktop (opzionale nei test).
  final DesktopWindowController? desktopWindowController;

  /// Controller della shell desktop (opzionale nei test).
  final DesktopShellController? desktopShellController;

  /// Coordinatore dello spegnimento dell'applicazione (opzionale nei test).
  final ApplicationShutdownCoordinator? shutdownCoordinator;

  /// Callback opzionale per l'inizializzazione dei modelli nei test.
  final Future<ModelInitializationResult> Function()? initializeModels;

  /// Crea un'istanza di [AuraApp].
  const AuraApp({
    super.key,
    required this.notifier,
    this.dependencyService,
    this.desktopWindowController,
    this.desktopShellController,
    this.shutdownCoordinator,
    this.initializeModels,
  });

  @override
  State<AuraApp> createState() => _AuraAppState();
}

class _AuraAppState extends State<AuraApp> with WidgetsBindingObserver {
  late DesktopWindowController _windowController;
  late WindowPreferencesRepository _prefsRepo;
  late WindowGeometryPersistenceCoordinator _persistenceCoordinator;
  late DesktopShellController _shellController;
  late ApplicationShutdownCoordinator _shutdownCoordinator;
  StreamSubscription<DesktopWindowEvent>? _windowCloseSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initDesktopShell();
  }

  void _initDesktopShell() {
    _windowController =
        widget.desktopWindowController ?? WindowsDesktopWindowController();

    _prefsRepo = WindowPreferencesRepository(
      storeDirectoryPath: widget.notifier.appDataPath,
    );

    _persistenceCoordinator = WindowGeometryPersistenceCoordinator(
      repository: _prefsRepo,
    );

    _shellController = widget.desktopShellController ??
        DesktopShellController(
          windowController: _windowController,
          persistenceCoordinator: _persistenceCoordinator,
        );

    _shutdownCoordinator = widget.shutdownCoordinator ??
        ApplicationShutdownCoordinator(
          notifier: widget.notifier,
          shellController: _shellController,
          persistenceCoordinator: _persistenceCoordinator,
          windowController: _windowController,
          onNativeExit: widget.desktopWindowController != null ? () {} : null,
        );

    _windowCloseSubscription = _windowController.events
        .where((e) => e is DesktopWindowCloseRequested)
        .listen((_) {
      unawaited(_shutdownCoordinator.requestShutdown());
    });

    _prefsRepo.load().then((prefs) {
      _persistenceCoordinator.updatePreferences(prefs);
      return _shellController.initialize();
    }).catchError((e) {
      debugPrint(
          '[SHELL] Errore durante l\'inizializzazione della shell desktop: $e');
    });

    _shellController.addListener(_onShellStateChanged);
  }

  void _onShellStateChanged() {
    final state = _shellController.state;
    if (state.audioDuckingOnUnfocus) {
      AudioManager().setFocusDucked(!state.focused || state.minimized);
    } else {
      AudioManager().setFocusDucked(false);
    }
    if (mounted) {
      setState(() {});
      WidgetsBinding.instance.scheduleFrame();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _windowCloseSubscription?.cancel();
    _windowCloseSubscription = null;
    try {
      _shellController.removeListener(_onShellStateChanged);
    } catch (_) {}
    _persistenceCoordinator.dispose();
    super.dispose();
  }

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    try {
      await _shutdownCoordinator.requestShutdown();
    } catch (e) {
      debugPrint('[APP] Shutdown delle risorse fallito: $e');
    }
    return AppExitResponse.exit;
  }

  @override
  Widget build(BuildContext context) {
    return GameControllerProvider(
      notifier: widget.notifier,
      child: ListenableBuilder(
        listenable: _shellController,
        builder: (context, child) {
          return DesktopShellProvider(
            controller: _shellController,
            child: Shortcuts(
              shortcuts: <ShortcutActivator, Intent>{
                LogicalKeySet(LogicalKeyboardKey.f11):
                    const ToggleFullscreenIntent(),
                LogicalKeySet(LogicalKeyboardKey.alt, LogicalKeyboardKey.enter):
                    const ToggleFullscreenIntent(),
                LogicalKeySet(LogicalKeyboardKey.escape):
                    const ExitFullscreenIntent(),
              },
              child: Actions(
                actions: <Type, Action<Intent>>{
                  ToggleFullscreenIntent:
                      ToggleFullscreenAction(_shellController),
                  ExitFullscreenIntent: ExitFullscreenAction(_shellController),
                },
                child: MaterialApp(
                  title: 'A.U.R.A. - Artificial Unbound Reasoning Arena',
                  debugShowCheckedModeBanner: false,
                  theme: ThemeData(
                    brightness: Brightness.dark,
                    scaffoldBackgroundColor: Colors.black,
                    primaryColor: const Color(0xFF00FF66),
                    fontFamily: 'monospace',
                    textTheme: const TextTheme(
                      bodyLarge: TextStyle(
                          color: Color(0xFF00FF66), fontFamily: 'monospace'),
                      bodyMedium: TextStyle(
                          color: Color(0xFF00FF66), fontFamily: 'monospace'),
                    ),
                    colorScheme: const ColorScheme.dark(
                      primary: Color(0xFF00FF66),
                      secondary: Color(0xFFFFB000),
                      surface: Colors.black,
                    ),
                  ),
                  home: ListenableBuilder(
                    listenable: widget.notifier,
                    builder: (context, _) {
                      if (widget.notifier.currentScreen == "terminal") {
                        return TerminalScreen(notifier: widget.notifier);
                      } else {
                        final cliEnv = AuraCliEnvironment.fromPlatform();
                        final appManagedRoot =
                            widget.notifier.appDataPath.isNotEmpty
                                ? widget.notifier.appDataPath
                                : cliEnv.appManagedRoot;
                        final bundledRoot = cliEnv.bundledRoot;

                        final depService = widget.dependencyService ??
                            DefaultLlamaServerDependencyService(
                              configurationRepository:
                                  JsonModelConfigurationRepository(
                                storeDirectoryPath: appManagedRoot,
                                fileSystem: const LocalProvisioningFileSystem(),
                                lock: FileBasedProvisioningLock(
                                  lockDirectory: appManagedRoot,
                                ),
                              ),
                              fileSystem: const LocalProvisioningFileSystem(),
                              pathResolver: ProvisioningPathResolver(
                                appManagedRoot: appManagedRoot,
                                bundledRoot: bundledRoot,
                              ),
                            );
                        return BootMenuScreen(
                          notifier: widget.notifier,
                          dependencyService: depService,
                          initializeModels: widget.initializeModels,
                        );
                      }
                    },
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
