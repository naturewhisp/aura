import 'package:meta/meta.dart';

import 'dataset_source.dart';

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
/// Distingue rigorosamente i quattro livelli semantici:
/// - [isStructurallyValid]: assenza di errori strutturali o di schema bloccanti.
/// - [isScientificallyComplete]: nessun valore presunto, omesso o 'unknown' nei metadati critici.
/// - [isCuratable]: scientificamente completo e con fonte nota ([datasetSource] != [DatasetSource.unknown]).
/// - [isLoraTrainingEligible]: eleggibile per il training LoRA dell'Attore (richiede tassativamente [DatasetSource.humanPlaytest]).
@immutable
class ProvenanceValidationResult {
  /// Elenco dei riscontri o delle violazioni individuate.
  final List<ProvenanceValidationIssue> issues;

  /// Fonte del dataset associata alla provenance validata.
  final DatasetSource datasetSource;

  const ProvenanceValidationResult([
    this.issues = const [],
    this.datasetSource = DatasetSource.unknown,
  ]);

  /// Indica se la provenance non presenta errori strutturali o di schema bloccanti.
  bool get isStructurallyValid =>
      !issues.any((i) => i.severity == ProvenanceValidationSeverity.error);

  /// Alias retrocompatibile per [isStructurallyValid].
  bool get isValid => isStructurallyValid;

  /// Indica se la provenance è scientificamente completa (nessun valore presunto o mancante).
  bool get isScientificallyComplete =>
      isStructurallyValid && !issues.any((i) => i.isDisqualifier);

  /// Alias retrocompatibile per [isScientificallyComplete].
  bool get isComplete => isScientificallyComplete;

  /// Indica se il record è curabile (scientificamente completo e con fonte nota).
  bool get isCuratable =>
      isScientificallyComplete && datasetSource != DatasetSource.unknown;

  /// Indica se il record è pienamente eleggibile per il training LoRA con human feedback (Fase 8).
  ///
  /// Esclude categoricamente simulazioni sintetiche o sessioni di valutazione sviluppatore.
  bool get isLoraTrainingEligible =>
      isCuratable && datasetSource == DatasetSource.humanPlaytest;

  /// Alias retrocompatibile per [isLoraTrainingEligible].
  bool get isDatasetEligible => isLoraTrainingEligible;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProvenanceValidationResult &&
          runtimeType == other.runtimeType &&
          datasetSource == other.datasetSource &&
          _issuesEqual(issues, other.issues);

  @override
  int get hashCode => Object.hash(datasetSource, Object.hashAll(issues));

  @override
  String toString() =>
      'ProvenanceValidationResult(structurallyValid: $isStructurallyValid, scientificallyComplete: $isScientificallyComplete, curatable: $isCuratable, loraEligible: $isLoraTrainingEligible, source: ${datasetSource.wireValue}, issues: ${issues.length})';

  static bool _issuesEqual(
      List<ProvenanceValidationIssue> a, List<ProvenanceValidationIssue> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
