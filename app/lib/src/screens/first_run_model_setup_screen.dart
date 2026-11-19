import 'dart:ui';
import 'package:aura_core/aura_offline.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../state_management/ui_failure_message.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/audio_reactive_background.dart';

enum OnboardingModelMode { managed, external }

/// Schermata di onboarding guidato (First-Run Wizard) per la configurazione dell'inferenza locale.
class FirstRunModelSetupScreen extends StatefulWidget {
  final FirstRunModelSetupFacade firstRunFacade;
  final LocalInferenceFacade inferenceFacade;
  final VoidCallback onComplete;
  final bool forceReconfigure;
  final bool disableBackgroundAnimation;

  const FirstRunModelSetupScreen({
    super.key,
    required this.firstRunFacade,
    required this.inferenceFacade,
    required this.onComplete,
    this.forceReconfigure = false,
    this.disableBackgroundAnimation = false,
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

  bool _isDownloading = false;

  /// Mostra il form manuale anche quando è disponibile il runtime incluso.
  bool _showAdvancedRuntime = false;
  DownloadProgress? _downloadProgress;
  String? _downloadingArtifactId;
  DefaultProvisioningCancellationToken? _downloadCancellationToken;

  @override
  void initState() {
    super.initState();
    _initSetup();
  }

  @override
  void dispose() {
    _downloadCancellationToken?.cancel();
    _inputController.dispose();
    super.dispose();
  }

  void _cancelCatalogDownload() {
    _downloadCancellationToken?.cancel();
    if (mounted) {
      setState(() {
        _isDownloading = false;
        _downloadingArtifactId = null;
        _downloadProgress = null;
        _downloadCancellationToken = null;
      });
    }
  }

  Future<void> _startCatalogDownload(
      CatalogArtifact artifact, ModelActivationRole role) async {
    if (_isDownloading) return;
    final cancellationToken = DefaultProvisioningCancellationToken();
    _downloadCancellationToken = cancellationToken;

    setState(() {
      _isDownloading = true;
      _downloadingArtifactId = artifact.artifactId;
      _downloadProgress = null;
      _errorMessage = null;
    });

    try {
      var newState =
          await widget.firstRunFacade.downloadAndProvisionCatalogArtifact(
        artifact: artifact,
        role: role,
        cancellationToken: cancellationToken,
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              _downloadProgress = progress;
            });
          }
        },
      );

      if (!mounted) return;

      final managed = await widget.inferenceFacade.listManagedModels();

      setState(() {
        _state = newState;
        _managedModels = managed;
        if (role == ModelActivationRole.actor) {
          _actorMode = OnboardingModelMode.managed;
          final match = managed.cast<InstalledArtifactDescriptor?>().firstWhere(
                (m) =>
                    m?.artifactId == artifact.artifactId ||
                    m?.displayName == artifact.displayName,
                orElse: () => null,
              );
          _selectedActorManagedId =
              match?.installationId ?? artifact.artifactId;
        } else {
          _evaluatorMode = OnboardingModelMode.managed;
          final match = managed.cast<InstalledArtifactDescriptor?>().firstWhere(
                (m) =>
                    m?.artifactId == artifact.artifactId ||
                    m?.displayName == artifact.displayName,
                orElse: () => null,
              );
          _selectedEvaluatorManagedId =
              match?.installationId ?? artifact.artifactId;
        }
      });
      await _prepareStepFields(newState.step);
    } catch (e) {
      if (!mounted) return;
      final isCancelled = cancellationToken.isCancellationRequested ||
          (e is ProvisioningException &&
              e.reason == ProvisioningFailureReason.operationCancelled) ||
          e.toString().toLowerCase().contains('annulla');

      if (!isCancelled) {
        setState(() => _errorMessage =
            'Errore durante il download del modello: ${uiFailureMessage(e)}');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _downloadingArtifactId = null;
          _downloadProgress = null;
          _downloadCancellationToken = null;
        });
      }
    }
  }

  Widget _buildOfficialCatalogCard(
      CatalogArtifact artifact, ModelActivationRole role) {
    String formatEta(Duration remaining) {
      if (remaining.inHours > 0) {
        final mins = remaining.inMinutes % 60;
        return '${remaining.inHours}h ${mins}m rimanenti';
      }
      if (remaining.inMinutes > 0) {
        final secs = remaining.inSeconds % 60;
        return '${remaining.inMinutes}m ${secs}s rimanenti';
      }
      return '${remaining.inSeconds}s rimanenti';
    }

    final matchingModel =
        _managedModels.cast<InstalledArtifactDescriptor?>().firstWhere(
              (m) =>
                  m?.artifactId == artifact.artifactId ||
                  m?.displayName == artifact.displayName,
              orElse: () => null,
            );
    final isInstalled = matchingModel != null;
    final isSelected = role == ModelActivationRole.actor
        ? (_selectedActorManagedId == matchingModel?.installationId ||
            _selectedActorManagedId == artifact.artifactId)
        : (_selectedEvaluatorManagedId == matchingModel?.installationId ||
            _selectedEvaluatorManagedId == artifact.artifactId);

    final isRecommended = (role == ModelActivationRole.actor &&
            (artifact.metadata['isDefaultActor'] == true ||
                artifact.artifactId == 'gemma-4-12b-it-qat-q4-0')) ||
        (role == ModelActivationRole.evaluator &&
            (artifact.metadata['isDefaultEvaluator'] == true ||
                artifact.artifactId == 'ministral-3b-instruct'));

    final sizeGb =
        (artifact.sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(2);
    final isCurrentlyDownloading =
        _isDownloading && _downloadingArtifactId == artifact.artifactId;

    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF001A08),
        border: Border.all(
          color: isSelected
              ? const Color(0xFF00FF66)
              : (isRecommended
                  ? const Color(0xFFFFB000)
                  : (isInstalled
                      ? const Color(0xFF00CC55)
                      : const Color(0xFF005522))),
          width: (isSelected || isRecommended) ? 1.5 : 1.0,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isRecommended
                    ? Icons.star_rounded
                    : (isInstalled
                        ? Icons.check_circle
                        : Icons.cloud_download_outlined),
                color: isRecommended
                    ? const Color(0xFFFFB000)
                    : (isInstalled
                        ? const Color(0xFF00CC55)
                        : const Color(0xFF00FF66)),
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  artifact.displayName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              if (isRecommended) ...[
                Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3D2A00),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    '★ RACCOMANDATO',
                    style: TextStyle(
                      color: Color(0xFFFFB000),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isInstalled
                      ? const Color(0xFF003D1A)
                      : const Color(0xFF005522),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  isInstalled ? '✓ GIÀ PRESENTE' : '$sizeGb GB',
                  style: TextStyle(
                    color: isInstalled
                        ? const Color(0xFF66FF99)
                        : const Color(0xFF88CCA0),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            isRecommended
                ? 'Modello consigliato per ${role == ModelActivationRole.actor ? "PANOPTICON (Actor)" : "Valutatore (Evaluator)"}.'
                : 'Modello del catalogo ufficiale A.U.R.A.',
            style: const TextStyle(color: Color(0xFF88CCA0), fontSize: 12),
          ),
          const SizedBox(height: 10),
          if (isCurrentlyDownloading) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _downloadProgress?.fraction ?? 0.0,
                backgroundColor: const Color(0xFF000A02),
                valueColor: AlwaysStoppedAnimation<Color>(
                  (_downloadProgress?.isIngesting ?? false)
                      ? const Color(0xFF00CC55)
                      : const Color(0xFF00FF66),
                ),
                minHeight: 8,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    (_downloadProgress?.isIngesting ?? false)
                        ? 'Ingestione & Verifica SHA-256: ${_downloadProgress?.percentage ?? 0}% '
                            '(${((_downloadProgress?.downloadedBytes ?? 0) / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB / $sizeGb GB)'
                        : '${_downloadProgress?.percentage ?? 0}% '
                            '(${((_downloadProgress?.downloadedBytes ?? 0) / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB / $sizeGb GB)',
                    style: TextStyle(
                      color: (_downloadProgress?.isIngesting ?? false)
                          ? const Color(0xFF66FF99)
                          : const Color(0xFF00FF66),
                      fontSize: 12,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (!(_downloadProgress?.isIngesting ?? false))
                  Builder(
                    builder: (context) {
                      final progress = _downloadProgress;
                      final eta = progress?.estimatedRemaining;
                      final speedMb =
                          ((progress?.bytesPerSecond ?? 0) / (1024 * 1024))
                              .toStringAsFixed(1);
                      return Text(
                        eta != null
                            ? '$speedMb MB/s • ${formatEta(eta)}'
                            : 'Calcolo velocità ed ETA...',
                        style: const TextStyle(
                          color: Color(0xFF88CCA0),
                          fontSize: 12,
                          fontFamily: 'monospace',
                        ),
                      );
                    },
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFFCA5A5),
                  side: const BorderSide(color: Color(0xFFFF5555)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                ),
                onPressed: _cancelCatalogDownload,
                icon: const Icon(Icons.cancel_outlined, size: 16),
                label: const Text(
                  'ANNULLA DOWNLOAD',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ] else if (isInstalled) ...[
            SizedBox(
              width: double.infinity,
              child: isSelected
                  ? ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF003D1A),
                        foregroundColor: const Color(0xFF66FF99),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      onPressed: null,
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('✓ SELEZIONATO PER QUESTO RUOLO'),
                    )
                  : OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF00FF66),
                        side: const BorderSide(color: Color(0xFF00FF66)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      onPressed: _isLoading || _isDownloading
                          ? null
                          : () {
                              final targetId = matchingModel.installationId;
                              setState(() {
                                if (role == ModelActivationRole.actor) {
                                  _selectedActorManagedId = targetId;
                                } else {
                                  _selectedEvaluatorManagedId = targetId;
                                }
                              });
                            },
                      icon: const Icon(Icons.touch_app, size: 18),
                      label: const Text('> SELEZIONA QUESTO MODELLO'),
                    ),
            ),
          ] else ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isRecommended
                      ? const Color(0xFF00AA44)
                      : const Color(0xFF005522),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: _isLoading || _isDownloading
                    ? null
                    : () => _startCatalogDownload(artifact, role),
                icon: const Icon(Icons.download, size: 18),
                label: Text('SCARICA ED INSTALLA ($sizeGb GB)'),
              ),
            ),
          ],
        ],
      ),
    );
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
      setState(() => _errorMessage =
          'Errore inizializzazione setup: ${uiFailureMessage(e)}');
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
      setState(() => _errorMessage =
          'Impossibile aprire il browser: ${uiFailureMessage(e)}');
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
      setState(() => _errorMessage =
          'Impossibile aprire il selettore di file: ${uiFailureMessage(e)}');
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
      setState(() => _errorMessage =
          'Impossibile aprire il selettore di file: ${uiFailureMessage(e)}');
    }
  }

  /// Raccomandazione hardware calcolata sulla VRAM libera rilevata dalla probe.
  ///
  /// Le dimensioni sono quelle dei modelli predefiniti del catalogo: per modelli
  /// esterni la stima resta indicativa.
  HardwareModelRecommendation? _hardwareRecommendation() {
    final detection = _state?.runtimeDetectionResult;
    if (detection == null) return null;
    final artifacts = CatalogManifest.initialDefault().artifacts;
    CatalogArtifact? byRole(String role) {
      for (final a in artifacts) {
        if (a.metadata['role'] == role) return a;
      }
      return null;
    }

    final actor = byRole('actor');
    final evaluator = byRole('evaluator');
    if (actor == null || evaluator == null) return null;
    return HardwareModelAdvisor.recommend(
      acceleration: detection.acceleration,
      gpuFreeMiB: detection.gpuMemoryFreeMiB,
      actorModelBytes: actor.sizeBytes,
      evaluatorModelBytes: evaluator.sizeBytes,
    );
  }

  Widget _buildHardwareAdvice({required bool showSharedAction}) {
    final recommendation = _hardwareRecommendation();
    if (recommendation == null) return const SizedBox.shrink();
    final shared =
        recommendation.topology == RecommendedModelTopology.sharedActorModel;
    final accent = shared ? const Color(0xFFFFB000) : const Color(0xFF00FF66);
    return Container(
      key: const Key('hardware_advice'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF001A08),
        border: Border.all(color: accent),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            shared
                ? 'CONSIGLIO HARDWARE: UN SOLO MODELLO PER ENTRAMBI I RUOLI'
                : 'CONSIGLIO HARDWARE: DUE MODELLI DISTINTI',
            style: TextStyle(
              color: accent,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            recommendation.rationale,
            style: const TextStyle(color: Color(0xFFB8F5CC), fontSize: 12),
          ),
          if (recommendation.exceedsAvailableMemory)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'Anche con un solo modello la VRAM libera è al limite: chiudi '
                'altre applicazioni che usano la GPU prima di giocare.',
                style: TextStyle(color: Color(0xFFFFB000), fontSize: 12),
              ),
            ),
          if (showSharedAction) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              key: const Key('use_actor_model_for_evaluator'),
              style: OutlinedButton.styleFrom(
                foregroundColor: accent,
                side: BorderSide(color: accent),
              ),
              onPressed: _isLoading ? null : _useActorModelForEvaluator,
              icon: const Icon(Icons.merge_type, size: 16),
              label: const Text('USA LO STESSO MODELLO DELL\'ATTORE'),
            ),
          ],
        ],
      ),
    );
  }

  /// Assegna al Valutatore lo stesso modello già scelto per l'Attore.
  ///
  /// Il bootstrap riconosce il file condiviso e avvia un solo processo
  /// `llama-server`, dimezzando la VRAM dei pesi rispetto a due processi.
  Future<void> _useActorModelForEvaluator() async {
    try {
      final snapshot = await widget.inferenceFacade.getSnapshot();
      final actorRef = snapshot.modelConfiguration.actor;
      if (!mounted) return;
      if (actorRef is ManagedModelReference) {
        setState(() {
          _evaluatorMode = OnboardingModelMode.managed;
          _selectedEvaluatorManagedId = actorRef.installationId;
        });
      } else if (actorRef is ExternalModelReference) {
        setState(() {
          _evaluatorMode = OnboardingModelMode.external;
          _inputController.text = actorRef.absolutePath;
        });
      } else {
        setState(() => _errorMessage =
            'Configura prima il modello dell\'Attore (passaggio 2).');
        return;
      }
      await _submitEvaluator();
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage =
          'Impossibile riusare il modello dell\'Attore: ${uiFailureMessage(e)}');
    }
  }

  Future<void> _prepareStepFields(FirstRunSetupStep step) async {
    try {
      final snapshot = await widget.inferenceFacade.getSnapshot();
      final actorRef = snapshot.modelConfiguration.actor;
      final evalRef = snapshot.modelConfiguration.evaluator;

      switch (step) {
        case FirstRunSetupStep.actorSelection:
          if (_actorMode == OnboardingModelMode.managed &&
              _selectedActorManagedId != null &&
              _selectedActorManagedId!.isNotEmpty) {
            _inputController.clear();
          } else if (actorRef is ManagedModelReference) {
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
          if (_evaluatorMode == OnboardingModelMode.managed &&
              _selectedEvaluatorManagedId != null &&
              _selectedEvaluatorManagedId!.isNotEmpty) {
            _inputController.clear();
          } else if (evalRef is ManagedModelReference) {
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
    final inputPath = _inputController.text.trim();
    final detectedCandidate =
        _state?.runtimeDetectionResult?.effectiveCandidate;
    final path = inputPath.isNotEmpty ? inputPath : (detectedCandidate ?? '');
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
      setState(() => _errorMessage =
          'Errore configurazione runtime: ${uiFailureMessage(e)}');
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
      setState(() => _errorMessage =
          'Errore selezione modello Actor: ${uiFailureMessage(e)}');
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
      setState(() => _errorMessage =
          'Errore selezione modello Evaluator: ${uiFailureMessage(e)}');
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
      setState(() => _errorMessage =
          'Errore accettazione consenso: ${uiFailureMessage(e)}');
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
      setState(() => _errorMessage =
          'Errore esecuzione probe finale: ${uiFailureMessage(e)}');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Widget _buildErrorMessageBanner(String message) {
    final detail = message.trim();
    final formattedMessage = detail.isEmpty
        ? 'Il processo llama-server non è stato avviato correttamente.'
        : (detail.startsWith('Il probe processuale') ||
                detail.startsWith('Errore') ||
                detail.startsWith('Eseguibile')
            ? detail
            : 'Il processo llama-server non è stato avviato: $detail');

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0x33EF4444),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFF5555)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: Color(0xFFFF5555), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              formattedMessage,
              style: const TextStyle(
                  color: Color(0xFFFCA5A5), fontSize: 13, height: 1.3),
            ),
          ),
          InkWell(
            onTap: () {
              setState(() {
                _errorMessage = null;
              });
            },
            child: const Icon(Icons.close, color: Color(0xFFFCA5A5), size: 18),
          ),
        ],
      ),
    );
  }

  /// Scheda del runtime incluso rilevato e già validato dal provisioning.
  Widget _buildRecommendedRuntimeCard(LlamaServerDetectionResult detection) {
    final accelLabel = switch (detection.acceleration) {
      RuntimeAcceleration.cuda => 'GPU NVIDIA (CUDA)',
      RuntimeAcceleration.vulkan => 'GPU (VULKAN)',
      RuntimeAcceleration.metal => 'GPU APPLE (METAL)',
      RuntimeAcceleration.cpu => 'SOLO CPU',
    };
    final gpuName = detection.gpuDeviceName;
    return Container(
      key: const Key('recommended_runtime_card'),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF001A08),
        border: Border.all(color: const Color(0xFF00FF66)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.bolt, color: Color(0xFF00FF66), size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'RUNTIME INCLUSO RILEVATO E VERIFICATO',
                  style: TextStyle(
                    color: Color(0xFF00FF66),
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              Text(
                '★ RACCOMANDATO',
                style: TextStyle(
                  color: Color(0xFFFFB000),
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Accelerazione: $accelLabel'
            '${gpuName != null && gpuName.isNotEmpty ? ' - $gpuName' : ''}',
            style: const TextStyle(color: Color(0xFFB8F5CC), fontSize: 12),
          ),
          if (detection.acceleration == RuntimeAcceleration.cpu)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'Nessuna GPU compatibile rilevata: il gioco funziona, ma ogni '
                'risposta richiederà più tempo.',
                style: TextStyle(color: Color(0xFFFFB000), fontSize: 12),
              ),
            ),
          const SizedBox(height: 4),
          const Text(
            'Non serve installare altro: A.U.R.A. avvierà e chiuderà questo '
            'runtime automaticamente.',
            style: TextStyle(color: Color(0xFF88CCA0), fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildStepContent() {
    final currentState = _state;
    if (currentState == null || _isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF00FF66)),
      );
    }

    switch (currentState.step) {
      case FirstRunSetupStep.initialCheck:
        return const Text(
          'Inizializzazione in corso...',
          style: TextStyle(color: Colors.white),
        );

      case FirstRunSetupStep.runtimeSelection:
        final detection = currentState.runtimeDetectionResult;
        final detected = detection?.effectiveCandidate;
        final activeError = _errorMessage ?? currentState.errorMessage;
        final showRecommended = detected != null && !_showAdvancedRuntime;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (activeError != null && activeError.trim().isNotEmpty)
              _buildErrorMessageBanner(activeError),
            const Text(
              'PASSAGGIO 1: SELEZIONE RUNTIME LLAMA-SERVER',
              style: TextStyle(
                color: Color(0xFF00FF66),
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            if (showRecommended) ...[
              // Runtime incluso e già verificato: un solo clic di conferma
              // (la persistenza resta subordinata alla scelta esplicita).
              _buildRecommendedRuntimeCard(detection!),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                key: const Key('use_bundled_runtime'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00FF66),
                  foregroundColor: Colors.black,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                ),
                onPressed: _isLoading
                    ? null
                    : () {
                        _inputController.clear();
                        _submitRuntime();
                      },
                icon: const Icon(Icons.check, size: 18),
                label: const Text(
                  'USA IL RUNTIME INCLUSO  (AVANTI >)',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _isLoading
                    ? null
                    : () => setState(() => _showAdvancedRuntime = true),
                child: const Text(
                  'Configurazione avanzata: usa un altro eseguibile llama-server',
                  style: TextStyle(color: Color(0xFF88CCA0), fontSize: 12),
                ),
              ),
            ] else ...[
              const Text(
                'Specificare il percorso dell\'eseguibile llama-server.',
                style: TextStyle(color: Color(0xFF88CCA0), fontSize: 13),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF00FF66)),
                  foregroundColor: const Color(0xFF00FF66),
                ),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text(
                  'SCARICA LLAMA-SERVER (OFFICIAL GITHUB RELEASES)',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                onPressed: _openLlamaReleases,
              ),
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
                        fillColor: const Color(0xFF001A08),
                        border: const OutlineInputBorder(),
                        hintText: detected ??
                            'Percorso dell\'eseguibile llama-server.exe',
                        hintStyle: const TextStyle(color: Color(0xFF4D9966)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF005522),
                      foregroundColor: const Color(0xFF00FF66),
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
              if (detected != null)
                TextButton(
                  onPressed: _isLoading
                      ? null
                      : () => setState(() => _showAdvancedRuntime = false),
                  child: const Text(
                    '< Torna al runtime incluso raccomandato',
                    style: TextStyle(color: Color(0xFF88CCA0), fontSize: 12),
                  ),
                ),
            ],
          ],
        );

      case FirstRunSetupStep.actorSelection:
        final catalogArtifacts = CatalogManifest.initialDefault().artifacts;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'PASSAGGIO 2: MODELLO ACTOR (PANOPTICON)',
              style: TextStyle(
                color: Color(0xFF00FF66),
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            _buildHardwareAdvice(showSharedAction: false),
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
                  onSelectionChanged: _isLoading || _isDownloading
                      ? null
                      : (s) => setState(() => _actorMode = s.first),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_actorMode == OnboardingModelMode.managed) ...[
              if (_managedModels.isNotEmpty)
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
                    fillColor: Color(0xFF001A08),
                    border: OutlineInputBorder(),
                    hintText: 'Seleziona modello gestito Actor...',
                  ),
                  dropdownColor: const Color(0xFF001A08),
                ),
              ...catalogArtifacts.map((artifact) => _buildOfficialCatalogCard(
                  artifact, ModelActivationRole.actor)),
            ] else
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      enabled: !_isLoading && !_isDownloading,
                      style: const TextStyle(
                          color: Colors.white, fontFamily: 'monospace'),
                      decoration: const InputDecoration(
                        filled: true,
                        fillColor: Color(0xFF001A08),
                        border: OutlineInputBorder(),
                        hintText: r'C:\Models\actor.gguf',
                        hintStyle: TextStyle(color: Color(0xFF4D9966)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF005522),
                      foregroundColor: const Color(0xFF00FF66),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 16),
                    ),
                    onPressed: _isLoading || _isDownloading
                        ? null
                        : () => _pickFileForModel(ModelActivationRole.actor),
                    icon: const Icon(Icons.folder_open, size: 20),
                    label: const Text('SFOGLIA...'),
                  ),
                ],
              ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isLoading || _isDownloading ? null : _submitActor,
              child: const Text('CONFERMA MODELLO ACTOR  (AVANTI >)'),
            ),
          ],
        );

      case FirstRunSetupStep.evaluatorSelection:
        final catalogArtifacts = CatalogManifest.initialDefault().artifacts;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'PASSAGGIO 3: MODELLO EVALUATOR (VALUTATORE)',
              style: TextStyle(
                color: Color(0xFF00FF66),
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            _buildHardwareAdvice(showSharedAction: true),
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
                  onSelectionChanged: _isLoading || _isDownloading
                      ? null
                      : (s) => setState(() => _evaluatorMode = s.first),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_evaluatorMode == OnboardingModelMode.managed) ...[
              if (_managedModels.isNotEmpty)
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
                    fillColor: Color(0xFF001A08),
                    border: OutlineInputBorder(),
                    hintText: 'Seleziona modello gestito Evaluator...',
                  ),
                  dropdownColor: const Color(0xFF001A08),
                ),
              ...catalogArtifacts.map((artifact) => _buildOfficialCatalogCard(
                  artifact, ModelActivationRole.evaluator)),
            ] else
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      enabled: !_isLoading && !_isDownloading,
                      style: const TextStyle(
                          color: Colors.white, fontFamily: 'monospace'),
                      decoration: const InputDecoration(
                        filled: true,
                        fillColor: Color(0xFF001A08),
                        border: OutlineInputBorder(),
                        hintText: r'C:\Models\evaluator.gguf',
                        hintStyle: TextStyle(color: Color(0xFF4D9966)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF005522),
                      foregroundColor: const Color(0xFF00FF66),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 16),
                    ),
                    onPressed: _isLoading || _isDownloading
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
              onPressed: _isLoading || _isDownloading ? null : _submitEvaluator,
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
                    color: Color(0xFFFFB000), size: 32),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'CONSENSO INFORMATO RICHIESTO',
                    style: TextStyle(
                      color: Color(0xFFFFB000),
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
              style: const TextStyle(color: Color(0xFFB8F5CC), fontSize: 13),
            ),
            if (_pendingConsentReference != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF001A08),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: SelectableText(
                  _pendingConsentReference!.absolutePath,
                  style: const TextStyle(
                    color: Color(0xFF00FF66),
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
                    backgroundColor: const Color(0xFFFFB000),
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
            if (_isLoading) ...[
              const CircularProgressIndicator(color: Color(0xFF00FF66)),
              const SizedBox(height: 16),
              const Text(
                'Verifica probe in corso...',
                style: TextStyle(
                  color: Color(0xFF00FF66),
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Rilevamento allocazione VRAM e compatibilità hardware...',
                style: TextStyle(color: Color(0xFF88CCA0), fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ] else ...[
              const Icon(Icons.speed, color: Color(0xFF00FF66), size: 48),
              const SizedBox(height: 16),
              const Text(
                'VERIFICA FINALE RUNTIME',
                style: TextStyle(
                  color: Color(0xFF00FF66),
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Configurazione completata. Avvia la verifica probe per testare il caricamento del runtime e convalidare l\'accelerazione hardware.',
                style: TextStyle(color: Color(0xFF88CCA0), fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF003D1A),
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                icon: const Icon(Icons.play_arrow),
                onPressed: _runProbe,
                label: const Text(
                  'AVVIA VERIFICA PROBE',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ],
        );

      case FirstRunSetupStep.complete:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_outline,
                color: Color(0xFF00CC55), size: 48),
            const SizedBox(height: 12),
            const Text(
              'CONFIGURAZIONE INFERENZA COMPLETA',
              style: TextStyle(
                color: Color(0xFF00CC55),
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
                    side: const BorderSide(color: Color(0xFF00FF66)),
                  ),
                  icon: const Icon(Icons.settings_backup_restore,
                      color: Color(0xFF00FF66), size: 18),
                  label: const Text(
                    'RICONFIGURA DA CAPO',
                    style: TextStyle(
                      color: Color(0xFF00FF66),
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
                    backgroundColor: const Color(0xFF00CC55),
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
            const Icon(Icons.error_outline, color: Color(0xFFFF5555), size: 48),
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
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xCC0F172A),
        elevation: 0,
        title: const Text('A.U.R.A. — Configurazione Iniziale'),
      ),
      body: Stack(
        children: [
          // Sfondo animato reattivo visibile in dissolvenza
          if (!widget.disableBackgroundAnimation)
            const Positioned.fill(
              child: AudioReactiveBackground(),
            ),
          // Overlay di velatura Cyberpunk
          const Positioned.fill(
            child: ColoredBox(color: Color(0x99020617)),
          ),
          // Finestra dei controlli con vetro sfumato (Glassmorphism)
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xDC0F172A),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0x3300FFC8)),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x30000000),
                            blurRadius: 24,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(24.0),
                      child: _buildStepContent(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
