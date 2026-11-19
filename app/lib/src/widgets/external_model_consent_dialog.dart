import 'package:flutter/material.dart';

/// Dialogo modale per il consenso informato sull'utilizzo di modelli GGUF esterni.
class ExternalModelConsentDialog extends StatelessWidget {
  final String modelPath;
  final VoidCallback onAccept;
  final VoidCallback onCancel;

  const ExternalModelConsentDialog({
    super.key,
    required this.modelPath,
    required this.onAccept,
    required this.onCancel,
  });

  static Future<bool?> show(
    BuildContext context, {
    required String modelPath,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ExternalModelConsentDialog(
        modelPath: modelPath,
        onAccept: () => Navigator.of(ctx).pop(true),
        onCancel: () => Navigator.of(ctx).pop(false),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF000A02),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFFFB000), width: 1.5),
      ),
      title: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Color(0xFFFFB000), size: 28),
          SizedBox(width: 10),
          Text(
            'Consenso Modello Esterno',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Stai per configurare un modello GGUF fornito autonomamente dall\'utente:',
              style: TextStyle(color: Color(0xFF88CCA0), fontSize: 14),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF001A08),
                borderRadius: BorderRadius.circular(6),
              ),
              child: SelectableText(
                modelPath,
                style: const TextStyle(
                  color: Color(0xFF00FF66),
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Avviso di Sicurezza ed Esecuzione Locale:',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '• I modelli esterni sono eseguiti interamente in locale tramite llama-server.\n'
              '• Assicurati che il file provenga da una fonte fidata.\n'
              '• A.U.R.A. non garantisce il rispetto delle direttive di allerta su modelli non certificati.',
              style: TextStyle(
                  color: Color(0xFFB8F5CC), fontSize: 13, height: 1.4),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: onCancel,
          child: const Text(
            'ANNULLA',
            style: TextStyle(color: Color(0xFF88CCA0)),
          ),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFFB000),
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          onPressed: onAccept,
          child: const Text(
            'ACCETTA E CONTINUA',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}
