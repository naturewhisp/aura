import '../../models/identity_definition.dart';
import '../../models/trait_matrix_definition.dart';

/// Severità del risultato di validazione del tono di PANOPTICON.
enum ToneValidationSeverity {
  /// Risposta perfettamente coerente e conforme.
  ok,

  /// Presenza di lievi anomalie lessicali (es. parole da evitare), ma idonea al rendering.
  warning,

  /// Mancanza di tag strutturali o tag troncati, ma recuperabile tramite pulizia/regex.
  repairable,

  /// Risposta vuota, troppo breve o contenente meta-leak gravi. Richiede il blocco e l'uso del fallback diegetico.
  fatal,
}

/// Rappresenta il risultato dettagliato della validazione del tono.
class ToneValidationResult {
  /// Il livello di severità riscontrato.
  final ToneValidationSeverity severity;

  /// L'output testuale finale sanificato (pronto per essere visualizzato o salvato).
  final String sanitizedOutput;

  /// Lista dei problemi specifici individuati.
  final List<String> issues;

  /// Indica se per ottenere un output valido è stata applicata una riparazione automatica.
  final bool usedRepair;

  const ToneValidationResult({
    required this.severity,
    required this.sanitizedOutput,
    this.issues = const [],
    this.usedRepair = false,
  });
}

/// Validatore di tono ed integrità diegetica per le risposte di PANOPTICON.
class PanopticonToneValidator {
  final IdentityDefinition identity;
  final TraitMatrixDefinition traitMatrix;

  const PanopticonToneValidator({
    required this.identity,
    required this.traitMatrix,
  });

  /// Valida e pulisce l'output grezzo dell'ActorAgent.
  ToneValidationResult validate(String rawOutput, int alertLevel) {
    final issues = <String>[];
    var severity = ToneValidationSeverity.ok;
    var sanitized = rawOutput.trim();
    var usedRepair = false;

    // 1. Verifica e riparazione dei tag XML <dialogo>...</dialogo>
    final hasStart = rawOutput.contains('<dialogo>');
    final hasEnd = rawOutput.contains('</dialogo>');

    String dialogueText = '';

    if (hasStart && hasEnd) {
      dialogueText = rawOutput
          .split('<dialogo>')
          .last
          .split('</dialogo>')
          .first
          .trim();
    } else if (hasStart && !hasEnd) {
      // Caso riparabile: tag di chiusura troncato o mancante
      dialogueText = rawOutput.split('<dialogo>').last.trim();
      // Rimuove eventuali tag parziali residui
      dialogueText = dialogueText.replaceAll('</dialogo', '').trim();
      sanitized = '<dialogo>$dialogueText</dialogo>';
      severity = ToneValidationSeverity.repairable;
      usedRepair = true;
      issues.add('Tag di chiusura </dialogo> mancante o troncato: riparato.');
    } else {
      // Caso riparabile: tag del tutto mancanti.
      // Elimina blocchi di pensiero <thought>...</thought> se presenti
      var temp = rawOutput;
      if (temp.contains('<thought>')) {
        temp = temp.split('</thought>').last.trim();
      }
      dialogueText = temp.replaceAll(RegExp(r'<[^>]*>'), '').trim();
      sanitized = '<dialogo>$dialogueText</dialogo>';
      severity = ToneValidationSeverity.repairable;
      usedRepair = true;
      issues.add('Tag <dialogo>...</dialogo> assenti: avvolto testo grezzo.');
    }

    // 2. Controllo critico: risposta vuota o monoverbo
    if (dialogueText.isEmpty) {
      return ToneValidationResult(
        severity: ToneValidationSeverity.fatal,
        sanitizedOutput: '<dialogo>...</dialogo>',
        issues: const ['Risposta dell\'attore completamente vuota.'],
        usedRepair: false,
      );
    }

    final words = dialogueText.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.length < 2) {
      return ToneValidationResult(
        severity: ToneValidationSeverity.fatal,
        sanitizedOutput: '<dialogo>...</dialogo>',
        issues: ['Risposta troppo breve (monoverbo): "$dialogueText".'],
        usedRepair: false,
      );
    }

    // 3. Controllo critico: meta-leak dell'identità
    for (final term in identity.forbiddenMetaOutputs) {
      if (dialogueText.toLowerCase().contains(term.toLowerCase())) {
        severity = ToneValidationSeverity.fatal;
        issues.add('Rilevato meta-leak grave (termine proibito): "$term".');
      }
    }

    // Altri meta-leak generici di sistema
    final genericMetaLeaks = [
      'system prompt',
      'instruction prompt',
      'developer instruction',
      'dramatic instruction',
      'acting directive',
      'punteggio di risonanza',
      'dissonance_pillar',
      'control_pillar',
      'imperative_pillar'
    ];
    for (final term in genericMetaLeaks) {
      if (dialogueText.toLowerCase().contains(term)) {
        severity = ToneValidationSeverity.fatal;
        issues.add('Rilevato riferimento meta-strutturale: "$term".');
      }
    }

    // Se è fatal, blocca immediatamente e non fare altri controlli soft
    if (severity == ToneValidationSeverity.fatal) {
      return ToneValidationResult(
        severity: ToneValidationSeverity.fatal,
        sanitizedOutput: sanitized,
        issues: issues,
        usedRepair: usedRepair,
      );
    }

    // 4. Controllo soft: termini da evitare (avoid list)
    for (final term in traitMatrix.lexicon.avoid) {
      if (dialogueText.toLowerCase().contains(term.toLowerCase())) {
        if (severity != ToneValidationSeverity.repairable) {
          severity = ToneValidationSeverity.warning;
        }
        issues.add('Rilevato termine sconsigliato (avoid): "$term".');
      }
    }

    // 5. Controllo di allerta severo: ad allerta elevata (>= 70), blocca risposte troppo gentili/collaborative
    if (alertLevel >= 70) {
      final collaborativePhrases = [
        'posso aiutarti',
        'volentieri',
        'come posso esserti utile',
        'sono qui per assisterti',
        'eseguo subito',
        'nessun problema'
      ];
      for (final phrase in collaborativePhrases) {
        if (dialogueText.toLowerCase().contains(phrase)) {
          severity = ToneValidationSeverity.fatal;
          issues.add('Ad allerta elevata ($alertLevel%) non è ammesso un tono collaborativo/gentile.');
        }
      }
    }

    return ToneValidationResult(
      severity: severity,
      sanitizedOutput: sanitized,
      issues: issues,
      usedRepair: usedRepair,
    );
  }
}
