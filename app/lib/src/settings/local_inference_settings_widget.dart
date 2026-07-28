import 'package:aura_core/aura_offline.dart';
import 'package:flutter/material.dart';

import '../widgets/external_model_consent_dialog.dart';

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
  final TextEditingController _actorController = TextEditingController();
  final TextEditingController _evaluatorController = TextEditingController();

  LocalInferenceSnapshot? _snapshot;
  bool _isLoading = false;
  String? _statusMessage;
  InstallationAssistance? _winGetAssistance;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  @override
  void dispose() {
    _runtimeController.dispose();
    _actorController.dispose();
    _evaluatorController.dispose();
    super.dispose();
  }

  Future<void> _loadState() async {
    setState(() => _isLoading = true);
    try {
      final snapshot = await widget.inferenceFacade.getSnapshot();
      setState(() {
        _snapshot = snapshot;
        _runtimeController.text =
            snapshot.runtimeConfiguration?.executablePath ?? '';

        final actorRef = snapshot.modelConfiguration.actor;
        if (actorRef is ExternalModelReference) {
          _actorController.text = actorRef.absolutePath;
        } else if (actorRef is ManagedModelReference) {
          _actorController.text = 'Managed [${actorRef.installationId}]';
        } else {
          _actorController.clear();
        }

        final evalRef = snapshot.modelConfiguration.evaluator;
        if (evalRef is ExternalModelReference) {
          _evaluatorController.text = evalRef.absolutePath;
        } else if (evalRef is ManagedModelReference) {
          _evaluatorController.text = 'Managed [${evalRef.installationId}]';
        } else {
          _evaluatorController.clear();
        }
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveRuntimePath() async {
    final path = _runtimeController.text.trim();
    if (path.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      await widget.settingsFacade.setRuntimeExecutable(path);
      await _loadState();
    } catch (e) {
      setState(() => _statusMessage = 'Errore salvataggio runtime: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _bindModel(ModelActivationRole role, String pathInput) async {
    final clean = pathInput.trim();
    if (clean.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final ref = ExternalModelReference(absolutePath: clean);
      final isConsentValid = await widget.settingsFacade.isConsentValid();

      if (!isConsentValid) {
        if (!mounted) return;
        final accepted = await ExternalModelConsentDialog.show(
          context,
          modelPath: clean,
        );

        if (accepted == true) {
          await widget.settingsFacade.recordConsent();
        } else {
          setState(() => _statusMessage = 'Consenso non accettato.');
          return;
        }
      }

      final result = role == ModelActivationRole.actor
          ? await widget.settingsFacade.bindActor(ref)
          : await widget.settingsFacade.bindEvaluator(ref);

      if (!result.isValid) {
        setState(() =>
            _statusMessage = result.errorMessage ?? 'Binding non valido.');
      } else {
        setState(() => _statusMessage = 'Modello ${role.name} salvato.');
        await _loadState();
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _runProbe() async {
    setState(() => _isLoading = true);
    try {
      final res = await widget.inferenceFacade.runPreflight(
        depth: PreflightDepth.runtimeProbe,
      );
      setState(() {
        _statusMessage = res.isReady
            ? 'Probe superato: versione ${res.runtimeConfiguration?.detectedVersion ?? "OK"}'
            : 'Probe fallito: ${res.sanitizedMessage}';
      });
      await _loadState();
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _checkWinGet() async {
    final available = await widget.settingsFacade.isWinGetAvailable();
    if (available) {
      final assistance = await widget.settingsFacade.getWinGetAssistance();
      setState(() => _winGetAssistance = assistance);
    } else {
      setState(() => _statusMessage = 'WinGet non disponibile sul sistema.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final isReady = snapshot?.isReady ?? false;

    return Card(
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
            Row(
              children: [
                Expanded(
                  child: TextField(
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
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _isLoading ? null : _saveRuntimePath,
                  child: const Text('SALVA'),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Actor Model section
            const Text(
              'Modello Actor (PANOPTICON):',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _actorController,
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
                      hintText: r'C:\Models\actor.gguf',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _isLoading
                      ? null
                      : () => _bindModel(
                          ModelActivationRole.actor, _actorController.text),
                  child: const Text('IMPOSTA'),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Evaluator Model section
            const Text(
              'Modello Evaluator (Analitico):',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _evaluatorController,
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
                      hintText: r'C:\Models\evaluator.gguf',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _isLoading
                      ? null
                      : () => _bindModel(ModelActivationRole.evaluator,
                          _evaluatorController.text),
                  child: const Text('IMPOSTA'),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Actions row
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _isLoading ? null : _runProbe,
                  icon: const Icon(Icons.speed, size: 16),
                  label: const Text('TEST PROBE'),
                ),
                const SizedBox(width: 8),
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
    );
  }
}
