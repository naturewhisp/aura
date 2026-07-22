import 'catalog_acquisition_exceptions.dart';
import 'catalog_acquisition_models.dart';

/// Policy di validazione per garantire che le revisioni dei repository siano strettamente immutabili.
abstract final class ImmutableRepositoryRevisionPolicy {
  /// Elenco esplicito dei riferimenti a branch o tag mobili non consentiti.
  static const Set<String> _floatingKeywords = {
    'main',
    'master',
    'head',
    'HEAD',
    'develop',
    'development',
    'nightly',
    'snapshot',
    'latest',
  };

  /// Convalida che [revision] sia un riferimento immutabile (es. un commit SHA completo a 40 caratteri hex).
  ///
  /// Se [source] è [CatalogSource.remoteSigned], in produzione viene richiesto un commit SHA-1 a 40 caratteri.
  /// Lancia [InvalidCatalogRevisionException] se la revisione è un riferimento mobile.
  static void validateRevision({
    required String revision,
    CatalogSource source = CatalogSource.remoteSigned,
  }) {
    final trimmed = revision.trim();
    if (trimmed.isEmpty) {
      throw InvalidCatalogRevisionException(
        'La revisione del repository non può essere vuota.',
      );
    }

    final lower = trimmed.toLowerCase();

    // 1. Verificare l'assenza di parole chiave di branch mobili
    if (_floatingKeywords.contains(lower)) {
      throw InvalidCatalogRevisionException(
        'La revisione "$trimmed" è un riferimento mobile non consentito.',
      );
    }

    // 2. Verificare l'assenza di prefissi branch o refs
    if (lower.startsWith('refs/heads/') || lower.startsWith('branch/')) {
      throw InvalidCatalogRevisionException(
        'I prefissi di branch "$trimmed" sono vietati come revisioni immutabili.',
      );
    }

    // 3. Per i cataloghi remoti firmati in produzione, la revisione deve essere un commit SHA a 40 caratteri hex
    if (source == CatalogSource.remoteSigned) {
      final shaRegExp = RegExp(r'^[a-f0-9]{40}$');
      if (!shaRegExp.hasMatch(lower)) {
        throw InvalidCatalogRevisionException(
          'La revisione remota "$trimmed" deve essere un commit SHA-1 di 40 caratteri esadecimali.',
        );
      }
    }
  }
}
