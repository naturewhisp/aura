import 'package:flutter/material.dart';

/// Dialogo di conferma prima di sovrascrivere la sessione salvata.
///
/// "Nuova connessione" e il tutorial eliminano il checkpoint attivo: senza
/// conferma un tasto premuto per errore cancella una partita in corso.
/// Il pulsante predefinito è ANNULLA (azione non distruttiva).
class OverwriteSessionDialog extends StatelessWidget {
  /// Nome dell'azione che sovrascrive la sessione (es. "NUOVA CONNESSIONE").
  final String actionLabel;

  const OverwriteSessionDialog({super.key, required this.actionLabel});

  /// Mostra il dialogo e restituisce `true` solo se l'utente conferma.
  static Future<bool> show(
    BuildContext context, {
    required String actionLabel,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => OverwriteSessionDialog(actionLabel: actionLabel),
    );
    return confirmed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    const amber = Color(0xFFFFB000);
    const green = Color(0xFF00FF66);
    const textStyle = TextStyle(
      fontFamily: 'monospace',
      color: Color(0xFF88FFB0),
      fontSize: 13.0,
      height: 1.5,
    );

    return AlertDialog(
      backgroundColor: const Color(0xFF000A02),
      shape: const RoundedRectangleBorder(
        side: BorderSide(color: amber, width: 1.5),
      ),
      title: const Text(
        'SOVRASCRIVERE LA SESSIONE SALVATA?',
        style: TextStyle(
          fontFamily: 'monospace',
          color: amber,
          fontWeight: FontWeight.bold,
          fontSize: 16.0,
        ),
      ),
      content: Text(
        'Esiste una connessione interrotta che puoi ancora ripristinare.\n'
        'Avviando $actionLabel il checkpoint verrà eliminato e non potrà '
        'essere recuperato.',
        style: textStyle,
      ),
      actions: [
        OutlinedButton(
          autofocus: true,
          style: OutlinedButton.styleFrom(
            foregroundColor: green,
            side: const BorderSide(color: green),
            shape: const RoundedRectangleBorder(),
          ),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text(
            'ANNULLA',
            style: TextStyle(fontFamily: 'monospace'),
          ),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: amber,
            foregroundColor: Colors.black,
            shape: const RoundedRectangleBorder(),
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text(
            'SOVRASCRIVI',
            style: TextStyle(
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}
