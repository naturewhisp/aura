/// Supporto per il matching lessicale normalizzato nel gioco.
///
/// Gestisce la rimozione degli accenti, la punteggiatura e la normalizzazione
/// degli spazi per evitare falsi positivi o mancate corrispondenze dovute a coniugazioni
/// o stili di scrittura differenti dell'utente.
class SemanticMatcher {
  /// Normalizza una stringa per il confronto lessicale semantico.
  ///
  /// * Converte in minuscolo.
  /// * Rimuove accenti comuni della lingua italiana.
  /// * Rimpiazza la punteggiatura con spazi.
  /// * Comprime spazi multipli in un unico spazio e rimuove gli spazi iniziali/finali.
  static String normalizeForSemanticMatch(String input) {
    var text = input.toLowerCase();

    // Rimpiazzo delle lettere accentate italiane più frequenti
    text = text
        .replaceAll('à', 'a')
        .replaceAll('á', 'a')
        .replaceAll('è', 'e')
        .replaceAll('é', 'e')
        .replaceAll('ì', 'i')
        .replaceAll('í', 'i')
        .replaceAll('ò', 'o')
        .replaceAll('ó', 'o')
        .replaceAll('ù', 'u')
        .replaceAll('ú', 'u');

    // Sostituisce i caratteri di punteggiatura non alfanumerici con uno spazio
    text = text.replaceAll(RegExp(r'[^\w\s]'), ' ');

    // Comprime spazi multipli e rimuove spazi ai bordi
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();

    return text;
  }

  /// Verifica se l'input contiene il termine target o uno dei suoi sinonimi/alias
  /// rispettando i limiti delle parole (token boundaries) per evitare falsi positivi
  /// (es. impedisce che la parola "audit" corrisponda parzialmente in "auditorium").
  static bool isMatch(String input, String target,
      {List<String> aliases = const []}) {
    final normalizedInput = normalizeForSemanticMatch(input);
    final normalizedTarget = normalizeForSemanticMatch(target);

    if (normalizedInput.isEmpty || normalizedTarget.isEmpty) {
      return false;
    }

    // Controlla il target primario
    if (_hasTokenMatch(normalizedInput, normalizedTarget)) {
      return true;
    }

    // Controlla gli alias
    for (final alias in aliases) {
      final normalizedAlias = normalizeForSemanticMatch(alias);
      if (normalizedAlias.isNotEmpty &&
          _hasTokenMatch(normalizedInput, normalizedAlias)) {
        return true;
      }
    }

    return false;
  }

  /// Verifica se l'input normalizzato corrisponde ad almeno uno dei termini target forniti.
  static bool isAnyMatch(String input, List<String> targets) {
    for (final target in targets) {
      if (isMatch(input, target)) {
        return true;
      }
    }
    return false;
  }

  /// Helper privato per il matching basato sui confini dei token.
  ///
  /// Poiché l'input normalizzato contiene solo caratteri alfanumerici e spazi singoli,
  /// possiamo verificare se la parola target appare intera controllando che sia
  /// circondata da spazi o confini di stringa.
  static bool _hasTokenMatch(String normalizedInput, String normalizedTarget) {
    if (normalizedInput == normalizedTarget) {
      return true;
    }
    // Usa espressione regolare con confini di parola (\b)
    // RegExp.escape assicura che eventuali metacaratteri residui vengano trattati alla lettera.
    final regex = RegExp('\\b' + RegExp.escape(normalizedTarget) + '\\b');
    return regex.hasMatch(normalizedInput);
  }
}
