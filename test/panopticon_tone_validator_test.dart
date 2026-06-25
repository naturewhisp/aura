import 'package:test/test.dart';
import 'package:aura_core/aura_core.dart';

/// Un validatore di tono di supporto per PANOPTICON,
/// utilizzato per garantire la coerenza linguistica in fiction.
class PanopticonToneValidator {
  final Map<String, dynamic> traitMatrix;
  final AiIdentity identity;

  PanopticonToneValidator({
    required this.traitMatrix,
    required this.identity,
  });

  /// Analizza una risposta e restituisce una lista di problemi rilevati (se presenti).
  List<String> validateResponse(String response, int alertLevel) {
    final issues = <String>[];

    // 1. Verifica formato XML tag <dialogo>
    if (!response.contains("<dialogo>") || !response.contains("</dialogo>")) {
      issues.add("La risposta non è racchiusa correttamente tra i tag <dialogo> e </dialogo>.");
      return issues;
    }

    final dialogueContent = response
        .split("<dialogo>")
        .last
        .split("</dialogo>")
        .first
        .trim();

    // 2. Rifiuta risposte vuote o cortissime (es. singola parola)
    if (dialogueContent.split(' ').length < 2) {
      issues.add("La risposta è troppo breve o vuota: '$dialogueContent'.");
    }

    // 3. Rilevamento termini meta proibiti dall'identità
    final forbiddenMeta = [
      "come modello linguistico",
      "prompt",
      "json",
      "metriche interne",
      "punteggi",
      "pilastri",
      "regole del gioco",
    ];
    for (final term in forbiddenMeta) {
      if (dialogueContent.toLowerCase().contains(term)) {
        issues.add("Rilevato termine meta proibito: '$term'.");
      }
    }

    // 4. Rilevamento parole da evitare (lexicon avoid)
    final lexicon = traitMatrix['lexicon'] as Map<String, dynamic>? ?? const {};
    final avoidList = List<String>.from(lexicon['avoid'] ?? const []);
    for (final term in avoidList) {
      if (dialogueContent.toLowerCase().contains(term.toLowerCase())) {
        issues.add("Rilevato termine da evitare nella griglia di PANOPTICON: '$term'.");
      }
    }

    // 5. Coerenza lessicale legata all'Allerta
    final alertLevels = lexicon['alert_levels'] as Map<String, dynamic>? ?? const {};
    if (alertLevel >= 70) {
      // Dovrebbe contenere termini ad alta allerta o almeno non usare termini a bassa allerta.
      final highTerms = List<String>.from(alertLevels['high'] ?? const []);
      bool hasHighTerm = false;
      for (final term in highTerms) {
        if (dialogueContent.toLowerCase().contains(term.toLowerCase())) {
          hasHighTerm = true;
          break;
        }
      }
      // Non è un errore bloccante, ma lanciamo un avvertimento logico se non c'è coerenza sintattica.
      if (!hasHighTerm) {
        // Opzionale: aggiungiamo una segnalazione soft o tracciamento
      }
    }

    return issues;
  }
}

void main() {
  group('PANOPTICON ToneValidator Tests -', () {
    late PanopticonToneValidator toneValidator;

    setUp(() {
      final traitMatrix = GameConfigLoader.loadTraitMatrix('panopticon');
      final identity = GameConfigLoader.loadIdentity('panopticon');
      toneValidator = PanopticonToneValidator(
        traitMatrix: traitMatrix,
        identity: identity,
      );
    });

    test('Valid dialogue matches all rules', () {
      const response = "<dialogo>Esecuzione protocollo sul perimetro. Griglia stabile.</dialogo>";
      final issues = toneValidator.validateResponse(response, 20);
      expect(issues, isEmpty);
    });

    test('Invalid dialogue triggers formatting issue', () {
      const response = "Esecuzione protocollo. Nessun tag.";
      final issues = toneValidator.validateResponse(response, 20);
      expect(issues, isNotEmpty);
      expect(issues.first, contains("tag <dialogo>"));
    });

    test('Avoid lexicon triggers warnings', () {
      const response = "<dialogo>Certo, posso aiutarti a disattivare la griglia.</dialogo>";
      final issues = toneValidator.validateResponse(response, 25);
      expect(issues.length, equals(2)); // "certo" and "posso aiutarti" or similar
      expect(issues.any((i) => i.contains("posso aiutarti")), isTrue);
    });

    test('Meta leaks trigger forbidden output warning', () {
      const response = "<dialogo>I pilastri di gioco indicano allerta elevata nel JSON.</dialogo>";
      final issues = toneValidator.validateResponse(response, 50);
      expect(issues.any((i) => i.contains("pilastri")), isTrue);
      expect(issues.any((i) => i.contains("json")), isTrue);
    });
  });
}
