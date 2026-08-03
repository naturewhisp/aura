import 'dart:ui';
import 'package:aura_core/aura_offline.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
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
        setState(
            () => _errorMessage = 'Errore durante il download del modello: $e');
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
        color: const Color(0xFF1E293B),
        border: Border.all(
          color: isSelected
              ? const Color(0xFF00FFC8)
              : (isRecommended
                  ? const Color(0xFFF59E0B)
                  : (isInstalled
                      ? const Color(0xFF10B981)
                      : const Color(0xFF334155))),
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
                    ? const Color(0xFFF59E0B)
                    : (isInstalled
                        ? const Color(0xFF10B981)
                        : const Color(0xFF00FFC8)),
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
                    color: const Color(0xFF78350F),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    '🌟 RACCOMANDATO',
                    style: TextStyle(
                      color: Color(0xFFFBBF24),
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
                      ? const Color(0xFF065F46)
                      : const Color(0xFF334155),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  isInstalled ? '✓ GIÀ PRESENTE' : '$sizeGb GB',
                  style: TextStyle(
                    color: isInstalled
                        ? const Color(0xFF34D399)
                        : const Color(0xFF94A3B8),
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
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
          ),
          const SizedBox(height: 10),
          if (isCurrentlyDownloading) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _downloadProgress?.fraction ?? 0.0,
                backgroundColor: const Color(0xFF0F172A),
                valueColor: AlwaysStoppedAnimation<Color>(
                  (_downloadProgress?.isIngesting ?? false)
                      ? const Color(0xFF10B981)
                      : const Color(0xFF00FFC8),
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
                        ? '⚡ Ingestione & Verifica SHA-256: ${_downloadProgress?.percentage ?? 0}% '
                            '(${((_downloadProgress?.downloadedBytes ?? 0) / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB / $sizeGb GB)'
                        : '${_downloadProgress?.percentage ?? 0}% '
                            '(${((_downloadProgress?.downloadedBytes ?? 0) / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB / $sizeGb GB)',
                    style: TextStyle(
                      color: (_downloadProgress?.isIngesting ?? false)
                          ? const Color(0xFF34D399)
                          : const Color(0xFF00FFC8),
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
                          color: Color(0xFF94A3B8),
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
                  side: const BorderSide(color: Color(0xFFEF4444)),
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
                        backgroundColor: const Color(0xFF065F46),
                        foregroundColor: const Color(0xFF34D399),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      onPressed: null,
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('✓ SELEZIONATO PER QUESTO RUOLO'),
                    )
                  : OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF00FFC8),
                        side: const BorderSide(color: Color(0xFF00FFC8)),
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
                      label: const Text('🔘 SELEZIONA QUESTO MODELLO'),
                    ),
            ),
          ] else ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isRecommended
                      ? const Color(0xFF059669)
                      : const Color(0xFF334155),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: _isLoading || _isDownloading
                    ? null
                    : () => _startCatalogDownload(artifact, role),
                icon: const Icon(Icons.download, size: 18),
                label: Text('📥 SCARICA ED INSTALLA ($sizeGb GB)'),
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
            child: const Text('RIPARTI / RITENTA'),
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
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.bolt, color: Color(0xFF00FFC8), size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Runtime Bundled: $detected',
                        style: const TextStyle(
                          color: Color(0xFF10B981),
                          fontSize: 12,
                          fontFamily: 'monospace',
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color:
                            currentState.runtimeDetectionResult?.acceleration ==
                                    RuntimeAcceleration.cuda
                                ? const Color(0xFF065F46)
                                : currentState.runtimeDetectionResult
                                            ?.acceleration ==
                                        RuntimeAcceleration.vulkan
                                    ? const Color(0xFF1E3A8A)
                                    : const Color(0xFF334155),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        currentState.runtimeDetectionResult?.variantId != null
                            ? 'VARIANTE: ${currentState.runtimeDetectionResult!.variantId!.toUpperCase()}'
                            : 'ACCEL: ${currentState.runtimeDetectionResult?.acceleration.name.toUpperCase()}',
                        style: const TextStyle(
                          color: Color(0xFF00FFC8),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
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
        final catalogArtifacts = CatalogManifest.initialDefault().artifacts;

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
                    fillColor: Color(0xFF1E293B),
                    border: OutlineInputBorder(),
                    hintText: 'Seleziona modello gestito Actor...',
                  ),
                  dropdownColor: const Color(0xFF1E293B),
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
                    fillColor: Color(0xFF1E293B),
                    border: OutlineInputBorder(),
                    hintText: 'Seleziona modello gestito Evaluator...',
                  ),
                  dropdownColor: const Color(0xFF1E293B),
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
