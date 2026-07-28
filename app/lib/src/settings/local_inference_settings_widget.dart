import 'package:aura_core/aura_offline.dart';
import 'package:flutter/material.dart';

import '../widgets/external_model_consent_dialog.dart';

enum ModelSelectionKind { managed, external }

/// Widget di gestione delle impostazioni del runtime e dei modelli di inferenza locale.
class LocalInferenceSettingsWidget extends StatefulWidget {
  final RuntimeModelSettingsFacade settingsFacade;
  final LocalInferenceFacade inferenceFacade;

  const LocalInferenceSettingsWidget({
    super.key,
    required this.settingsFacade,
    required this.inferenceFacade,
  });

  @override
  State<LocalInferenceSettingsWidget> createState() =>
      _LocalInferenceSettingsWidgetState();
}

class _LocalInferenceSettingsWidgetState
    extends State<LocalInferenceSettingsWidget> {
  final TextEditingController _runtimeController = TextEditingController();
  final TextEditingController _actorExternalController =
      TextEditingController();
  final TextEditingController _evaluatorExternalController =
      TextEditingController();

  LocalInferenceSnapshot? _snapshot;
  List<InstalledArtifactDescriptor> _managedModels = [];
  bool _isLoading = false;
  String? _statusMessage;
  InstallationAssistance? _winGetAssistance;

  ModelSelectionKind _actorKind = ModelSelectionKind.external;
  ModelSelectionKind _evaluatorKind = ModelSelectionKind.external;

  String? _selectedActorManagedId;
  String? _selectedEvaluatorManagedId;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  @override
  void dispose() {
    _runtimeController.dispose();
    _actorExternalController.dispose();
    _evaluatorExternalController.dispose();
    super.dispose();
  }

  Future<void> _loadState() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final snapshot = await widget.inferenceFacade.getSnapshot();
      final managed = await widget.inferenceFacade.listManagedModels();

      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _managedModels = managed;
        _runtimeController.text =
            snapshot.runtimeConfiguration?.executablePath ?? '';

        final actorRef = snapshot.modelConfiguration.actor;
        if (actorRef is ExternalModelReference) {
          _actorKind = ModelSelectionKind.external;
          _actorExternalController.text = actorRef.absolutePath;
          _selectedActorManagedId = null;
        } else if (actorRef is ManagedModelReference) {
          _actorKind = ModelSelectionKind.managed;
          _selectedActorManagedId = actorRef.installationId;
          _actorExternalController.clear();
        } else {
          _actorKind = ModelSelectionKind.external;
          _actorExternalController.clear();
          _selectedActorManagedId = null;
        }

        final evalRef = snapshot.modelConfiguration.evaluator;
        if (evalRef is ExternalModelReference) {
          _evaluatorKind = ModelSelectionKind.external;
          _evaluatorExternalController.text = evalRef.absolutePath;
          _selectedEvaluatorManagedId = null;
        } else if (evalRef is ManagedModelReference) {
          _evaluatorKind = ModelSelectionKind.managed;
          _selectedEvaluatorManagedId = evalRef.installationId;
          _evaluatorExternalController.clear();
        } else {
          _evaluatorKind = ModelSelectionKind.external;
          _evaluatorExternalController.clear();
          _selectedEvaluatorManagedId = null;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _statusMessage = 'Errore caricamento stato: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveRuntimePath() async {
    final path = _runtimeController.text.trim();
    if (path.isEmpty) return;

    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      await widget.settingsFacade.setRuntimeExecutable(path);
      if (!mounted) return;
      await _loadState();
    } catch (e) {
      if (!mounted) return;
      setState(() => _statusMessage = 'Errore salvataggio runtime: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _clearRuntime() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      await widget.settingsFacade.clearRuntimeExecutable();
      if (!mounted) return;
      _runtimeController.clear();
      await _loadState();
    } catch (e) {
      if (!mounted) return;
      setState(() => _statusMessage = 'Errore rimozione runtime: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _bindActor() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      ConfiguredModelReference ref;
      if (_actorKind == ModelSelectionKind.managed) {
        if (_selectedActorManagedId == null) {
          setState(() =>
              _statusMessage = 'Selezionare un modello gestito per Actor.');
          return;
        }
        ref = ManagedModelReference(installationId: _selectedActorManagedId!);
      } else {
        final path = _actorExternalController.text.trim();
        if (path.isEmpty) return;
        ref = ExternalModelReference(absolutePath: path);

        final isConsentValid = await widget.settingsFacade.isConsentValid();
        if (!isConsentValid) {
          if (!mounted) return;
          final accepted = await ExternalModelConsentDialog.show(
            context,
            modelPath: path,
          );
          if (accepted == true) {
            await widget.settingsFacade.recordConsent();
          } else {
            if (!mounted) return;
            setState(() => _statusMessage = 'Consenso non accettato.');
            return;
          }
        }
      }

      final result = await widget.settingsFacade.bindActor(ref);
      if (!mounted) return;

      if (!result.isValid) {
        setState(() => _statusMessage =
            result.errorMessage ?? 'Binding Actor non valido.');
      } else {
        setState(() => _statusMessage = 'Modello Actor salvato.');
        await _loadState();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _statusMessage = 'Errore binding Actor: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _clearActor() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      await widget.settingsFacade.clearActorBinding();
      if (!mounted) return;
      _actorExternalController.clear();
      _selectedActorManagedId = null;
      await _loadState();
    } catch (e) {
      if (!mounted) return;
      setState(() => _statusMessage = 'Errore rimozione Actor: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _bindEvaluator() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      ConfiguredModelReference ref;
      if (_evaluatorKind == ModelSelectionKind.managed) {
        if (_selectedEvaluatorManagedId == null) {
          setState(() =>
              _statusMessage = 'Selezionare un modello gestito per Evaluator.');
          return;
        }
        ref =
            ManagedModelReference(installationId: _selectedEvaluatorManagedId!);
      } else {
        final path = _evaluatorExternalController.text.trim();
        if (path.isEmpty) return;
        ref = ExternalModelReference(absolutePath: path);

        final isConsentValid = await widget.settingsFacade.isConsentValid();
        if (!isConsentValid) {
          if (!mounted) return;
          final accepted = await ExternalModelConsentDialog.show(
            context,
            modelPath: path,
          );
          if (accepted == true) {
            await widget.settingsFacade.recordConsent();
          } else {
            if (!mounted) return;
            setState(() => _statusMessage = 'Consenso non accettato.');
            return;
          }
        }
      }

      final result = await widget.settingsFacade.bindEvaluator(ref);
      if (!mounted) return;

      if (!result.isValid) {
        setState(() => _statusMessage =
            result.errorMessage ?? 'Binding Evaluator non valido.');
      } else {
        setState(() => _statusMessage = 'Modello Evaluator salvato.');
        await _loadState();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _statusMessage = 'Errore binding Evaluator: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _clearEvaluator() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      await widget.settingsFacade.clearEvaluatorBinding();
      if (!mounted) return;
      _evaluatorExternalController.clear();
      _selectedEvaluatorManagedId = null;
      await _loadState();
    } catch (e) {
      if (!mounted) return;
      setState(() => _statusMessage = 'Errore rimozione Evaluator: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _runProbe() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final res = await widget.inferenceFacade.runPreflight(
        depth: PreflightDepth.runtimeProbe,
      );
      if (!mounted) return;
      setState(() {
        _statusMessage = res.isReady
            ? 'Probe superato: versione ${res.runtimeConfiguration?.detectedVersion ?? "OK"}'
            : 'Probe fallito: ${res.sanitizedMessage}';
      });
      await _loadState();
    } catch (e) {
      if (!mounted) return;
      setState(() => _statusMessage = 'Errore esecuzione probe: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _checkWinGet() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final available = await widget.settingsFacade.isWinGetAvailable();
      if (!mounted) return;

      if (available) {
        final assistance = await widget.settingsFacade.getWinGetAssistance();
        if (!mounted) return;
        setState(() => _winGetAssistance = assistance);
      } else {
        setState(() => _statusMessage = 'WinGet non disponibile sul sistema.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _statusMessage = 'Errore controllo WinGet: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Widget _buildModelSelector({
    required String roleName,
    required ModelSelectionKind currentKind,
    required ValueChanged<ModelSelectionKind> onKindChanged,
    required TextEditingController externalController,
    required String? selectedManagedId,
    required ValueChanged<String?> onManagedChanged,
    required VoidCallback onSave,
    required VoidCallback onClear,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Modello $roleName:',
          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            SegmentedButton<ModelSelectionKind>(
              segments: const [
                ButtonSegment(
                  value: ModelSelectionKind.managed,
                  label: Text('MANAGED'),
                ),
                ButtonSegment(
                  value: ModelSelectionKind.external,
                  label: Text('EXTERNAL'),
                ),
              ],
              selected: {currentKind},
              onSelectionChanged: _isLoading
                  ? null
                  : (set) {
                      if (set.isNotEmpty) onKindChanged(set.first);
                    },
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (currentKind == ModelSelectionKind.managed)
          DropdownButtonFormField<String>(
            key: Key('${roleName.toLowerCase()}_managed_dropdown'),
            isExpanded: true,
            initialValue: selectedManagedId,
            items: _managedModels.map((artifact) {
              return DropdownMenuItem<String>(
                value: artifact.installationId,
                child: Text(
                  '${artifact.displayName} (${artifact.version})',
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              );
            }).toList(),
            onChanged: _isLoading ? null : onManagedChanged,
            decoration: const InputDecoration(
              filled: true,
              fillColor: Color(0xFF1E293B),
              border: OutlineInputBorder(),
              hintText: 'Seleziona un modello gestito...',
              hintStyle: TextStyle(color: Color(0xFF64748B)),
            ),
            dropdownColor: const Color(0xFF1E293B),
          )
        else
          TextField(
            controller: externalController,
            enabled: !_isLoading,
            style: const TextStyle(
              color: Colors.white,
              fontFamily: 'monospace',
              fontSize: 13,
            ),
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFF1E293B),
              border: const OutlineInputBorder(),
              hintText: 'C:\\Models\\$roleName.gguf',
              hintStyle: const TextStyle(color: Color(0xFF64748B)),
            ),
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ElevatedButton(
              onPressed: _isLoading ? null : onSave,
              child: const Text('SALVA'),
            ),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFEF4444),
                side: const BorderSide(color: Color(0xFFEF4444)),
              ),
              onPressed: _isLoading ? null : onClear,
              child: const Text('RIMUOVI'),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final isReady = snapshot?.isReady ?? false;

    return SingleChildScrollView(
      child: Card(
        color: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: isReady ? const Color(0xFF10B981) : const Color(0xFF334155),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  const Text(
                    'Inferenza Locale (llama-server)',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  Chip(
                    backgroundColor: isReady
                        ? const Color(0xFF064E3B)
                        : const Color(0xFF7F1D1D),
                    label: Text(
                      isReady ? 'PRONTO' : 'NON PRONTO',
                      style: TextStyle(
                        color: isReady
                            ? const Color(0xFF34D399)
                            : const Color(0xFFFCA5A5),
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_statusMessage != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _statusMessage!,
                    style:
                        const TextStyle(color: Color(0xFFF59E0B), fontSize: 12),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Runtime executable section
              const Text(
                'Percorso Eseguibile llama-server:',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
              ),
              const SizedBox(height: 4),
              TextField(
                controller: _runtimeController,
                enabled: !_isLoading,
                style: const TextStyle(
                  color: Colors.white,
                  fontFamily: 'monospace',
                  fontSize: 13,
                ),
                decoration: const InputDecoration(
                  filled: true,
                  fillColor: Color(0xFF1E293B),
                  border: OutlineInputBorder(),
                  hintText: r'C:\llama.cpp\llama-server.exe',
                  hintStyle: TextStyle(color: Color(0xFF64748B)),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ElevatedButton(
                    onPressed: _isLoading ? null : _saveRuntimePath,
                    child: const Text('SALVA RUNTIME'),
                  ),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFEF4444),
                      side: const BorderSide(color: Color(0xFFEF4444)),
                    ),
                    onPressed: _isLoading ? null : _clearRuntime,
                    child: const Text('RIMUOVI RUNTIME'),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Actor Model section
              _buildModelSelector(
                roleName: 'Actor',
                currentKind: _actorKind,
                onKindChanged: (kind) => setState(() => _actorKind = kind),
                externalController: _actorExternalController,
                selectedManagedId: _selectedActorManagedId,
                onManagedChanged: (val) =>
                    setState(() => _selectedActorManagedId = val),
                onSave: _bindActor,
                onClear: _clearActor,
              ),
              const SizedBox(height: 16),

              // Evaluator Model section
              _buildModelSelector(
                roleName: 'Evaluator',
                currentKind: _evaluatorKind,
                onKindChanged: (kind) => setState(() => _evaluatorKind = kind),
                externalController: _evaluatorExternalController,
                selectedManagedId: _selectedEvaluatorManagedId,
                onManagedChanged: (val) =>
                    setState(() => _selectedEvaluatorManagedId = val),
                onSave: _bindEvaluator,
                onClear: _clearEvaluator,
              ),
              const SizedBox(height: 16),

              // Actions row
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _isLoading ? null : _runProbe,
                    icon: const Icon(Icons.speed, size: 16),
                    label: const Text('TEST PROBE'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _isLoading ? null : _checkWinGet,
                    icon: const Icon(Icons.download, size: 16),
                    label: const Text('WINGET HELP'),
                  ),
                ],
              ),

              if (_winGetAssistance != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF00FFC8)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Comando WinGet Consigliato:',
                        style: TextStyle(
                          color: Color(0xFF00FFC8),
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      SelectableText(
                        _winGetAssistance!.command,
                        style: const TextStyle(
                          color: Colors.white,
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
