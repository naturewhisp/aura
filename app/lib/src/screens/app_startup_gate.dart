import 'dart:async';
import 'package:flutter/material.dart';
import 'package:aura_core/aura_offline.dart';
import '../state_management/game_controller_notifier.dart';
import 'boot_menu_screen.dart';
import 'first_run_model_setup_screen.dart';

/// Destinazione iniziale calcolata dal gate di avvio dell'applicazione.
enum StartupDestination {
  loading,
  onboarding,
  boot,
  error,
}

/// Gate di avvio dell'applicazione che valuta l'ambiente, il preflight ed i file di configurazione
/// prima di indirizzare l'utente verso la procedura guidata di onboarding o verso il BootMenuScreen.
class AppStartupGate extends StatefulWidget {
  final GameControllerNotifier notifier;
  final LocalInferenceServices? services;
  final FirstRunModelSetupFacade? firstRunFacade;
  final LlamaServerDependencyService? dependencyService;
  final Future<ModelInitializationResult> Function()? initializeModels;

  /// Destinazione forzata per i test unit/widget (opzionale).
  @visibleForTesting
  final StartupDestination? initialStartupDestination;

  const AppStartupGate({
    super.key,
    required this.notifier,
    this.services,
    this.firstRunFacade,
    this.dependencyService,
    this.initializeModels,
    this.initialStartupDestination,
  });

  @override
  State<AppStartupGate> createState() => _AppStartupGateState();
}

class _AppStartupGateState extends State<AppStartupGate> {
  StartupDestination _destination = StartupDestination.loading;
  LocalInferenceServices? _services;
  Object? _startupError;
  bool _showErrorDetails = false;
  int _startupGeneration = 0;

  @override
  void initState() {
    super.initState();
    _initServicesAndResolve();
  }

  void _initServicesAndResolve() {
    if (widget.initialStartupDestination != null) {
      _destination = widget.initialStartupDestination!;
      return;
    }

    if (widget.services != null) {
      _services = widget.services;
    } else {
      final env = AuraCliEnvironment.fromPlatform();
      final appManagedRoot = widget.notifier.appDataPath.isNotEmpty
          ? widget.notifier.appDataPath
          : env.appManagedRoot;
      _services = LocalInferenceServiceProvider.create(
        environment: env,
        customLock: widget.notifier.appDataPath.isNotEmpty
            ? FileBasedProvisioningLock(lockDirectory: appManagedRoot)
            : null,
      );
    }

    _resolveStartup();
  }

  Future<void> _resolveStartup() async {
    final generation = ++_startupGeneration;
    if (!mounted) return;

    setState(() {
      _destination = StartupDestination.loading;
      _startupError = null;
    });

    try {
      final facade = widget.firstRunFacade ?? _services!.firstRunFacade;
      final setupState = await facade.evaluateInitialState();

      if (!mounted || generation != _startupGeneration) return;

      if (setupState.isReadyForBoot) {
        setState(() {
          _destination = StartupDestination.boot;
        });
      } else {
        setState(() {
          _destination = StartupDestination.onboarding;
        });
      }
    } catch (e) {
      if (!mounted || generation != _startupGeneration) return;
      setState(() {
        _startupError = e;
        _destination = StartupDestination.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_destination) {
      case StartupDestination.loading:
        return const Scaffold(
          backgroundColor: Colors.black,
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: Color(0xFF00FF66)),
                SizedBox(height: 16),
                Text(
                  'AURA_INIT> CHECKING SYSTEM CONFIGURATION...',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    color: Color(0xFF00FF66),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        );

      case StartupDestination.onboarding:
        final services = _services ??
            LocalInferenceServiceProvider.create(
              environment: AuraCliEnvironment.fromPlatform(),
            );
        final facade = widget.firstRunFacade ?? services.firstRunFacade;
        return FirstRunModelSetupScreen(
          firstRunFacade: facade,
          inferenceFacade: services.inferenceFacade,
          forceReconfigure: false,
          onComplete: () {
            _resolveStartup();
          },
        );

      case StartupDestination.boot:
        final services = _services ??
            LocalInferenceServiceProvider.create(
              environment: AuraCliEnvironment.fromPlatform(),
            );
        final depService =
            widget.dependencyService ?? services.dependencyService;
        return BootMenuScreen(
          notifier: widget.notifier,
          dependencyService: depService,
          initializeModels: widget.initializeModels,
          firstRunFacade: widget.firstRunFacade ?? services.firstRunFacade,
          inferenceFacade: services.inferenceFacade,
        );

      case StartupDestination.error:
        return Scaffold(
          backgroundColor: Colors.black,
          body: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: Color(0xFFFFB000), size: 48),
                  const SizedBox(height: 16),
                  const Text(
                    'IMPOSSIBILE VERIFICARE LA CONFIGURAZIONE LOCALE',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      color: Color(0xFFFFB000),
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Si è verificato un errore durante l\'ispezione del runtime. È possibile riprovare la diagnosi o avviare la procedura guidata.',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      color: Color(0xFF94A3B8),
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (_showErrorDetails && _startupError != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFF334155)),
                      ),
                      child: Text(
                        'Dettagli Tecnici: $_startupError',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          color: Color(0xFFEF4444),
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00FF66),
                          foregroundColor: Colors.black,
                        ),
                        onPressed: _resolveStartup,
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('RIPROVA'),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF00FF66),
                          side: const BorderSide(color: Color(0xFF00FF66)),
                        ),
                        onPressed: () {
                          setState(() {
                            _destination = StartupDestination.onboarding;
                          });
                        },
                        icon: const Icon(Icons.build, size: 18),
                        label: const Text('AVVIA CONFIGURAZIONE GUIDATA'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _showErrorDetails = !_showErrorDetails;
                      });
                    },
                    child: Text(
                      _showErrorDetails
                          ? 'NASCONDI DETTAGLI'
                          : 'MOSTRA DETTAGLI TECNICI',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        color: Color(0xFF64748B),
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
    }
  }
}
