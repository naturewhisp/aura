import 'package:aura_core/aura_offline.dart';
import 'package:flutter/material.dart';

import '../widgets/external_model_consent_dialog.dart';

/// Schermata di onboarding guidato (First-Run Wizard) per la configurazione dell'inferenza locale.
class FirstRunModelSetupScreen extends StatefulWidget {
  final FirstRunModelSetupFacade firstRunFacade;
  final VoidCallback onComplete;

  const FirstRunModelSetupScreen({
    super.key,
    required this.firstRunFacade,
    required this.onComplete,
  });

  @override
  State<FirstRunModelSetupScreen> createState() =>
      _FirstRunModelSetupScreenState();
}

class _FirstRunModelSetupScreenState extends State<FirstRunModelSetupScreen> {
  final TextEditingController _inputController = TextEditingController();
  FirstRunSetupState? _state;
  bool _isLoading = false;

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
    setState(() => _isLoading = true);
    try {
      final state = await widget.firstRunFacade.evaluateInitialState();
      setState(() => _state = state);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _submitRuntime() async {
    final path = _inputController.text.trim();
    if (path.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final newState = await widget.firstRunFacade.configureRuntime(path);
      setState(() {
        _state = newState;
        _inputController.clear();
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _submitActor() async {
    final path = _inputController.text.trim();
    if (path.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final ref = ExternalModelReference(absolutePath: path);
      final newState = await widget.firstRunFacade.selectActorModel(ref);

      if (newState.step == FirstRunSetupStep.consentRequired) {
        if (!mounted) return;
        final accepted = await ExternalModelConsentDialog.show(
          context,
          modelPath: path,
        );

        if (accepted == true) {
          final retriedState =
              await widget.firstRunFacade.acceptConsentAndRetry(
            role: ModelActivationRole.actor,
            reference: ref,
          );
          setState(() {
            _state = retriedState;
            _inputController.clear();
          });
          return;
        }
      }

      setState(() {
        _state = newState;
        _inputController.clear();
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _submitEvaluator() async {
    final path = _inputController.text.trim();
    if (path.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final ref = ExternalModelReference(absolutePath: path);
      final newState = await widget.firstRunFacade.selectEvaluatorModel(ref);

      if (newState.step == FirstRunSetupStep.consentRequired) {
        if (!mounted) return;
        final accepted = await ExternalModelConsentDialog.show(
          context,
          modelPath: path,
        );

        if (accepted == true) {
          final retriedState =
              await widget.firstRunFacade.acceptConsentAndRetry(
            role: ModelActivationRole.evaluator,
            reference: ref,
          );
          setState(() {
            _state = retriedState;
            _inputController.clear();
          });
          return;
        }
      }

      setState(() {
        _state = newState;
        _inputController.clear();
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _runProbe() async {
    setState(() => _isLoading = true);
    try {
      final newState = await widget.firstRunFacade.runFinalPreflight();
      setState(() => _state = newState);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Widget _buildStepContent() {
    final currentState = _state;
    if (currentState == null || _isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF00FFC8)),
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
            TextField(
              controller: _inputController,
              enabled: !_isLoading,
              style:
                  const TextStyle(color: Colors.white, fontFamily: 'monospace'),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF1E293B),
                border: const OutlineInputBorder(),
                hintText: detected ?? r'C:\llama.cpp\llama-server.exe',
                hintStyle: const TextStyle(color: Color(0xFF64748B)),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isLoading ? null : _submitRuntime,
              child: const Text('CONFERMA RUNTIME'),
            ),
          ],
        );

      case FirstRunSetupStep.actorSelection:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
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
            const Text(
              'Inserire il percorso assoluto al file .gguf del modello Actor (es. Gemma 4 12B).',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _inputController,
              enabled: !_isLoading,
              style:
                  const TextStyle(color: Colors.white, fontFamily: 'monospace'),
              decoration: const InputDecoration(
                filled: true,
                fillColor: Color(0xFF1E293B),
                border: OutlineInputBorder(),
                hintText: r'C:\Models\actor.gguf',
                hintStyle: TextStyle(color: Color(0xFF64748B)),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isLoading ? null : _submitActor,
              child: const Text('IMPOSTA MODELLO ACTOR'),
            ),
          ],
        );

      case FirstRunSetupStep.evaluatorSelection:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
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
            const Text(
              'Inserire il percorso assoluto al file .gguf del modello Evaluator (es. Ministral 3B).',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _inputController,
              enabled: !_isLoading,
              style:
                  const TextStyle(color: Colors.white, fontFamily: 'monospace'),
              decoration: const InputDecoration(
                filled: true,
                fillColor: Color(0xFF1E293B),
                border: OutlineInputBorder(),
                hintText: r'C:\Models\evaluator.gguf',
                hintStyle: TextStyle(color: Color(0xFF64748B)),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isLoading ? null : _submitEvaluator,
              child: const Text('IMPOSTA MODELLO EVALUATOR'),
            ),
          ],
        );

      case FirstRunSetupStep.consentRequired:
      case FirstRunSetupStep.preflightCheck:
        return Column(
          children: [
            const CircularProgressIndicator(color: Color(0xFF00FFC8)),
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
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.black,
              ),
              onPressed: widget.onComplete,
              child: const Text(
                'PROSEGUI AL TERMINALE',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );

      case FirstRunSetupStep.failed:
        return Column(
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
      body: Padding(
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
