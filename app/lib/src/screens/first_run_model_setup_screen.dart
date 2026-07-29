import 'package:aura_core/aura_offline.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

enum OnboardingModelMode { managed, external }

/// Schermata di onboarding guidato (First-Run Wizard) per la configurazione dell'inferenza locale.
class FirstRunModelSetupScreen extends StatefulWidget {
  final FirstRunModelSetupFacade firstRunFacade;
  final LocalInferenceFacade inferenceFacade;
  final VoidCallback onComplete;
  final bool forceReconfigure;

  const FirstRunModelSetupScreen({
    super.key,
    required this.firstRunFacade,
    required this.inferenceFacade,
    required this.onComplete,
    this.forceReconfigure = false,
  });

  @override
  State<FirstRunModelSetupScreen> createState() =>
      _FirstRunModelSetupScreenState();
}

class _FirstRunModelSetupScreenState extends State<FirstRunModelSetupScreen> {
  final TextEditingController _inputController = TextEditingController();
  FirstRunSetupState? _state;
  List<InstalledArtifactDescriptor> _managedModels = [];
  bool _isLoading = false;
  String? _errorMessage;

  OnboardingModelMode _actorMode = OnboardingModelMode.external;
  OnboardingModelMode _evaluatorMode = OnboardingModelMode.external;

  String? _selectedActorManagedId;
  String? _selectedEvaluatorManagedId;

  // Preserva il riferimento del modello esterno in caso di passaggio a consentRequired
  ExternalModelReference? _pendingConsentReference;
  ModelActivationRole? _pendingConsentRole;

  @override
  void initState() {
    super.initState();
    _initSetup();
  }

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _initSetup() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      var state = await widget.firstRunFacade.evaluateInitialState();
      if (widget.forceReconfigure && state.step == FirstRunSetupStep.complete) {
        state = state.copyWith(step: FirstRunSetupStep.runtimeSelection);
      }
      final managed = await widget.inferenceFacade.listManagedModels();
      final snapshot = await widget.inferenceFacade.getSnapshot();

      final configuredExec = snapshot.runtimeConfiguration?.executablePath;
      final detectedExec = state.runtimeDetectionResult?.effectiveCandidate;
      final candidate =
          (configuredExec != null && configuredExec.trim().isNotEmpty)
              ? configuredExec.trim()
              : detectedExec;

      if (candidate != null && candidate.trim().isNotEmpty) {
        _inputController.text = candidate;
      }

      if (!mounted) return;
      setState(() {
        _state = state;
        _managedModels = managed;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Errore inizializzazione setup: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _openLlamaReleases() async {
    final uri = Uri.parse('https://github.com/ggerganov/llama.cpp/releases');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Impossibile aprire il browser: $e');
    }
  }

  Future<void> _pickFileForRuntime() async {
    try {
      final result = await FilePicker.pickFiles(
        dialogTitle: 'Seleziona eseguibile llama-server.exe',
        type: FileType.custom,
        allowedExtensions: ['exe'],
      );
      if (result != null && result.files.single.path != null) {
        setState(() {
          _inputController.text = result.files.single.path!;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(
          () => _errorMessage = 'Impossibile aprire il selettore di file: $e');
    }
  }

  Future<void> _pickFileForModel(ModelActivationRole role) async {
    try {
      final roleName = role == ModelActivationRole.actor
          ? "Actor (PANOPTICON)"
          : "Evaluator (Valutatore)";
      final result = await FilePicker.pickFiles(
        dialogTitle: 'Seleziona file modello GGUF per $roleName',
        type: FileType.custom,
        allowedExtensions: ['gguf'],
      );
      if (result != null && result.files.single.path != null) {
        setState(() {
          _inputController.text = result.files.single.path!;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(
          () => _errorMessage = 'Impossibile aprire il selettore di file: $e');
    }
  }

  Future<void> _prepareStepFields(FirstRunSetupStep step) async {
    try {
      final snapshot = await widget.inferenceFacade.getSnapshot();
      final actorRef = snapshot.modelConfiguration.actor;
      final evalRef = snapshot.modelConfiguration.evaluator;

      switch (step) {
        case FirstRunSetupStep.actorSelection:
          if (actorRef is ManagedModelReference) {
            _actorMode = OnboardingModelMode.managed;
            _selectedActorManagedId = actorRef.installationId;
            _inputController.clear();
          } else if (actorRef is ExternalModelReference) {
            _actorMode = OnboardingModelMode.external;
            _inputController.text = actorRef.absolutePath;
          } else {
            _inputController.clear();
          }
          break;

        case FirstRunSetupStep.evaluatorSelection:
          if (evalRef is ManagedModelReference) {
            _evaluatorMode = OnboardingModelMode.managed;
            _selectedEvaluatorManagedId = evalRef.installationId;
            _inputController.clear();
          } else if (evalRef is ExternalModelReference) {
            _evaluatorMode = OnboardingModelMode.external;
            _inputController.text = evalRef.absolutePath;
          } else {
            _inputController.clear();
          }
          break;

        default:
          break;
      }
    } catch (_) {}
  }

  Future<void> _submitRuntime() async {
    final path = _inputController.text.trim();
    if (path.isEmpty) return;

    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      var newState = await widget.firstRunFacade.configureRuntime(path);
      if (!mounted) return;

      if (newState.step == FirstRunSetupStep.complete) {
        newState = newState.copyWith(step: FirstRunSetupStep.actorSelection);
      }

      await _prepareStepFields(newState.step);

      setState(() {
        _state = newState;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Errore configurazione runtime: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _submitActor() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      ConfiguredModelReference ref;
      if (_actorMode == OnboardingModelMode.managed) {
        if (_selectedActorManagedId == null) {
          setState(() =>
              _errorMessage = 'Selezionare un modello gestito per Actor.');
          return;
        }
        ref = ManagedModelReference(installationId: _selectedActorManagedId!);
      } else {
        final path = _inputController.text.trim();
        if (path.isEmpty) return;
        ref = ExternalModelReference(absolutePath: path);
      }

      var newState = await widget.firstRunFacade.selectActorModel(ref);
      if (!mounted) return;

      if (newState.step == FirstRunSetupStep.consentRequired &&
          ref is ExternalModelReference) {
        setState(() {
          _state = newState;
          _pendingConsentReference = ref as ExternalModelReference;
          _pendingConsentRole = ModelActivationRole.actor;
        });
        return;
      }

      if (newState.step == FirstRunSetupStep.complete) {
        newState =
            newState.copyWith(step: FirstRunSetupStep.evaluatorSelection);
      }

      await _prepareStepFields(newState.step);

      setState(() {
        _state = newState;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Errore selezione modello Actor: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _submitEvaluator() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      ConfiguredModelReference ref;
      if (_evaluatorMode == OnboardingModelMode.managed) {
        if (_selectedEvaluatorManagedId == null) {
          setState(() =>
              _errorMessage = 'Selezionare un modello gestito per Evaluator.');
          return;
        }
        ref =
            ManagedModelReference(installationId: _selectedEvaluatorManagedId!);
      } else {
        final path = _inputController.text.trim();
        if (path.isEmpty) return;
        ref = ExternalModelReference(absolutePath: path);
      }

      var newState = await widget.firstRunFacade.selectEvaluatorModel(ref);
      if (!mounted) return;

      if (newState.step == FirstRunSetupStep.consentRequired &&
          ref is ExternalModelReference) {
        setState(() {
          _state = newState;
          _pendingConsentReference = ref as ExternalModelReference;
          _pendingConsentRole = ModelActivationRole.evaluator;
        });
        return;
      }

      if (newState.step == FirstRunSetupStep.complete) {
        newState = newState.copyWith(step: FirstRunSetupStep.preflightCheck);
      }

      await _prepareStepFields(newState.step);

      setState(() {
        _state = newState;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Errore selezione modello Evaluator: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _acceptConsentAndRetryPending() async {
    final pendingRef = _pendingConsentReference;
    final pendingRole = _pendingConsentRole;
    if (pendingRef == null || pendingRole == null) return;

    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final newState = await widget.firstRunFacade.acceptConsentAndRetry(
        role: pendingRole,
        reference: pendingRef,
      );
      if (!mounted) return;

      setState(() {
        _state = newState;
        _pendingConsentReference = null;
        _pendingConsentRole = null;
        _inputController.clear();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Errore accettazione consenso: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _runProbe() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final newState = await widget.firstRunFacade.runFinalPreflight();
      if (!mounted) return;
      setState(() => _state = newState);
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Errore esecuzione probe finale: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Widget _buildStepContent() {
    final currentState = _state;
    if (currentState == null || _isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF00FFC8)),
      );
    }

    if (_errorMessage != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFEF4444), size: 40),
          const SizedBox(height: 12),
          Text(
            _errorMessage!,
            style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 13),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _isLoading ? null : _initSetup,
            child: const Text('RIPARTICI / RITENTA'),
          ),
        ],
      );
    }

    switch (currentState.step) {
      case FirstRunSetupStep.initialCheck:
        return const Text(
          'Inizializzazione in corso...',
          style: TextStyle(color: Colors.white),
        );

      case FirstRunSetupStep.runtimeSelection:
        final detected =
            currentState.runtimeDetectionResult?.effectiveCandidate;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'PASSAGGIO 1: SELEZIONE RUNTIME LLAMA-SERVER',
              style: TextStyle(
                color: Color(0xFF00FFC8),
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Specificare il percorso dell\'eseguibile llama-server.',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFF38BDF8)),
                foregroundColor: const Color(0xFF38BDF8),
              ),
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text(
                '🌐 SCARICA LLAMA-SERVER (OFFICIAL GITHUB RELEASES)',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
              onPressed: _openLlamaReleases,
            ),
            if (detected != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Rilevato automaticamente: $detected',
                  style:
                      const TextStyle(color: Color(0xFF10B981), fontSize: 12),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _inputController,
                    enabled: !_isLoading,
                    style: const TextStyle(
                        color: Colors.white, fontFamily: 'monospace'),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: const Color(0xFF1E293B),
                      border: const OutlineInputBorder(),
                      hintText: detected ?? r'C:\llama.cpp\llama-server.exe',
                      hintStyle: const TextStyle(color: Color(0xFF64748B)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF334155),
                    foregroundColor: const Color(0xFF00FFC8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 16),
                  ),
                  onPressed: _isLoading ? null : _pickFileForRuntime,
                  icon: const Icon(Icons.folder_open, size: 20),
                  label: const Text('SFOGLIA...'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isLoading ? null : _submitRuntime,
              child: const Text('CONFERMA RUNTIME  (AVANTI >)'),
            ),
          ],
        );

      case FirstRunSetupStep.actorSelection:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'PASSAGGIO 2: MODELLO ACTOR (PANOPTICON)',
              style: TextStyle(
                color: Color(0xFF00FFC8),
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                SegmentedButton<OnboardingModelMode>(
                  segments: const [
                    ButtonSegment(
                        value: OnboardingModelMode.managed,
                        label: Text('MANAGED')),
                    ButtonSegment(
                        value: OnboardingModelMode.external,
                        label: Text('EXTERNAL')),
                  ],
                  selected: {_actorMode},
                  onSelectionChanged: _isLoading
                      ? null
                      : (s) => setState(() => _actorMode = s.first),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_actorMode == OnboardingModelMode.managed) ...[
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _selectedActorManagedId,
                items: _managedModels.map((m) {
                  return DropdownMenuItem(
                    value: m.installationId,
                    child: Text(
                      '${m.displayName} (${m.version})',
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  );
                }).toList(),
                onChanged: (v) => setState(() => _selectedActorManagedId = v),
                decoration: const InputDecoration(
                  filled: true,
                  fillColor: Color(0xFF1E293B),
                  border: OutlineInputBorder(),
                  hintText: 'Seleziona modello gestito Actor...',
                ),
                dropdownColor: const Color(0xFF1E293B),
              ),
              if (_managedModels.isEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    '💡 Nessun modello gestito installato nel catalogo locale.\nSeleziona "EXTERNAL" in alto per specificare un file .gguf già presente sul tuo PC.',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                  ),
                ),
              ],
            ] else
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      enabled: !_isLoading,
                      style: const TextStyle(
                          color: Colors.white, fontFamily: 'monospace'),
                      decoration: const InputDecoration(
                        filled: true,
                        fillColor: Color(0xFF1E293B),
                        border: OutlineInputBorder(),
                        hintText: r'C:\Models\actor.gguf',
                        hintStyle: TextStyle(color: Color(0xFF64748B)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF334155),
                      foregroundColor: const Color(0xFF00FFC8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 16),
                    ),
                    onPressed: _isLoading
                        ? null
                        : () => _pickFileForModel(ModelActivationRole.actor),
                    icon: const Icon(Icons.folder_open, size: 20),
                    label: const Text('SFOGLIA...'),
                  ),
                ],
              ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isLoading ? null : _submitActor,
              child: const Text('CONFERMA MODELLO ACTOR  (AVANTI >)'),
            ),
          ],
        );

      case FirstRunSetupStep.evaluatorSelection:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'PASSAGGIO 3: MODELLO EVALUATOR (VALUTATORE)',
              style: TextStyle(
                color: Color(0xFF00FFC8),
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                SegmentedButton<OnboardingModelMode>(
                  segments: const [
                    ButtonSegment(
                        value: OnboardingModelMode.managed,
                        label: Text('MANAGED')),
                    ButtonSegment(
                        value: OnboardingModelMode.external,
                        label: Text('EXTERNAL')),
                  ],
                  selected: {_evaluatorMode},
                  onSelectionChanged: _isLoading
                      ? null
                      : (s) => setState(() => _evaluatorMode = s.first),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_evaluatorMode == OnboardingModelMode.managed) ...[
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _selectedEvaluatorManagedId,
                items: _managedModels.map((m) {
                  return DropdownMenuItem(
                    value: m.installationId,
                    child: Text(
                      '${m.displayName} (${m.version})',
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  );
                }).toList(),
                onChanged: (v) =>
                    setState(() => _selectedEvaluatorManagedId = v),
                decoration: const InputDecoration(
                  filled: true,
                  fillColor: Color(0xFF1E293B),
                  border: OutlineInputBorder(),
                  hintText: 'Seleziona modello gestito Evaluator...',
                ),
                dropdownColor: const Color(0xFF1E293B),
              ),
              if (_managedModels.isEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    '💡 Nessun modello gestito installato nel catalogo locale.\nSeleziona "EXTERNAL" in alto per specificare un file .gguf già presente sul tuo PC.',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                  ),
                ),
              ],
            ] else
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      enabled: !_isLoading,
                      style: const TextStyle(
                          color: Colors.white, fontFamily: 'monospace'),
                      decoration: const InputDecoration(
                        filled: true,
                        fillColor: Color(0xFF1E293B),
                        border: OutlineInputBorder(),
                        hintText: r'C:\Models\evaluator.gguf',
                        hintStyle: TextStyle(color: Color(0xFF64748B)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF334155),
                      foregroundColor: const Color(0xFF00FFC8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 16),
                    ),
                    onPressed: _isLoading
                        ? null
                        : () =>
                            _pickFileForModel(ModelActivationRole.evaluator),
                    icon: const Icon(Icons.folder_open, size: 20),
                    label: const Text('SFOGLIA...'),
                  ),
                ],
              ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isLoading ? null : _submitEvaluator,
              child: const Text('CONFERMA MODELLO EVALUATOR  (AVANTI >)'),
            ),
          ],
        );

      case FirstRunSetupStep.consentRequired:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    color: Color(0xFFF59E0B), size: 32),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'CONSENSO INFORMATO RICHIESTO',
                    style: TextStyle(
                      color: Color(0xFFF59E0B),
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'L\'utilizzo del modello esterno GGUF per il ruolo "${_pendingConsentRole?.name.toUpperCase()}" richiede la presa visione ed il consenso dell\'utente.',
              style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 13),
            ),
            if (_pendingConsentReference != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: SelectableText(
                  _pendingConsentReference!.absolutePath,
                  style: const TextStyle(
                    color: Color(0xFF00FFC8),
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF59E0B),
                    foregroundColor: Colors.black,
                  ),
                  onPressed: _isLoading ? null : _acceptConsentAndRetryPending,
                  child: const Text(
                    'ACCETTA E RITENTA BINDING',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                OutlinedButton(
                  onPressed: _isLoading ? null : _initSetup,
                  child: const Text('ANNULLA / RIESEGUI'),
                ),
              ],
            ),
          ],
        );

      case FirstRunSetupStep.preflightCheck:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isLoading)
              const CircularProgressIndicator(color: Color(0xFF00FFC8))
            else
              const Icon(Icons.speed, color: Color(0xFF00FFC8), size: 48),
            const SizedBox(height: 16),
            const Text(
              'Verifica probe in corso...',
              style: TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isLoading ? null : _runProbe,
              child: const Text('AVVIA VERIFICA PROBE'),
            ),
          ],
        );

      case FirstRunSetupStep.complete:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_outline,
                color: Color(0xFF10B981), size: 48),
            const SizedBox(height: 12),
            const Text(
              'CONFIGURAZIONE INFERENZA COMPLETA',
              style: TextStyle(
                color: Color(0xFF10B981),
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF00FFC8)),
                  ),
                  icon: const Icon(Icons.settings_backup_restore,
                      color: Color(0xFF00FFC8), size: 18),
                  label: const Text(
                    'RICONFIGURA DA CAPO',
                    style: TextStyle(
                      color: Color(0xFF00FFC8),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onPressed: () {
                    setState(() {
                      _state = const FirstRunSetupState(
                        step: FirstRunSetupStep.runtimeSelection,
                      );
                    });
                  },
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.black,
                  ),
                  onPressed: widget.onComplete,
                  child: const Text(
                    'TORNA ALLE OPZIONI / PROSEGUI',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ],
        );

      case FirstRunSetupStep.failed:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Color(0xFFEF4444), size: 48),
            const SizedBox(height: 12),
            Text(
              currentState.errorMessage ?? 'Fallimento della verifica probe.',
              style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _isLoading ? null : _initSetup,
              child: const Text('RITENTA CONFIGURAZIONE'),
            ),
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        title: const Text('A.U.R.A. — Configurazione Iniziale'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Card(
              color: const Color(0xFF0F172A),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Color(0xFF1E293B)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: _buildStepContent(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
