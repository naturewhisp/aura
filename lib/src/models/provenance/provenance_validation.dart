import 'package:meta/meta.dart';

/// Livello di severità del riscontro generato durante la validazione della provenance.
enum ProvenanceValidationSeverity {
  /// Avviso o raccomandazione che non pregiudica l'eleggibilità del record.
  warning,

  /// Errore strutturale che rende la provenance incompleta o inconsistente.
  error,

  /// Disqualifica formale che esclude il record dalla pipeline di curatela dataset (Fase 8).
  datasetDisqualifier,
}

/// Rappresenta una singola anomalia riscontrata durante la validazione dei metadati di provenance.
@immutable
class ProvenanceValidationIssue {
  /// Nome del campo o componente analizzato.
  final String field;

  /// Messaggio descrittivo della violazione o anomalia.
  final String message;

  /// Severità dell'anomalia.
  final ProvenanceValidationSeverity severity;

  const ProvenanceValidationIssue({
    required this.field,
    required this.message,
    this.severity = ProvenanceValidationSeverity.error,
  });

  /// Indica se questo riscontro disqualifica categoricamente il dato per il dataset ML.
  bool get isDisqualifier =>
      severity == ProvenanceValidationSeverity.datasetDisqualifier ||
      severity == ProvenanceValidationSeverity.error;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProvenanceValidationIssue &&
          runtimeType == other.runtimeType &&
          field == other.field &&
          message == other.message &&
          severity == other.severity;

  @override
  int get hashCode => Object.hash(field, message, severity);

  @override
  String toString() =>
      'ProvenanceValidationIssue($field: $message [$severity])';
}

/// Esito complessivo della validazione dei metadati di provenance.
///
/// Distingue rigorosamente tra:
/// - **Deserializzabile**: il record JSON è stato letto senza errori sintattici.
/// - **Valido**: la struttura e i vincoli semantici di dominio sono rispettati.
/// - **Dataset Eligible**: il record possiede tutte le garanzie scientifiche e di
///   integrità richieste per il fine-tuning e addestramento (Fase 8).
@immutable
class ProvenanceValidationResult {
  /// Elenco dei riscontri o delle violazioni individuate.
  final List<ProvenanceValidationIssue> issues;

  const ProvenanceValidationResult([this.issues = const []]);

  /// Indica se la provenance non presenta errori strutturali bloccanti.
  bool get isValid =>
      !issues.any((i) => i.severity == ProvenanceValidationSeverity.error);

  /// Indica se la provenance è pienamente valida ed eleggibile per il dataset ML.
  bool get isDatasetEligible => isValid && !issues.any((i) => i.isDisqualifier);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProvenanceValidationResult &&
          runtimeType == other.runtimeType &&
          _issuesEqual(issues, other.issues);

  @override
  int get hashCode => Object.hashAll(issues);

  @override
  String toString() =>
      'ProvenanceValidationResult(valid: $isValid, eligible: $isDatasetEligible, issues: ${issues.length})';

  static bool _issuesEqual(
      List<ProvenanceValidationIssue> a, List<ProvenanceValidationIssue> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
