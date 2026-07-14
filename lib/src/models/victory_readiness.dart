import 'package:meta/meta.dart';

/// Rappresenta lo stato di prontezza numerica per la vittoria in A.U.R.A.
///
/// Modella il soddisfacimento dei criteri legati alla media dei pilastri cognitivi
/// e al livello di allerta di PANOPTICON, fornendo dettagli diagnostici utili alla UI
/// e al resolver dello stato musicale.
@immutable
class VictoryReadiness {
  /// Soglia di progresso numerico oltre la quale si considera la vittoria imminente.
  ///
  /// Il valore 0.95 corrisponde al 95% di avanzamento rispetto alle soglie configurate.
  static const double approachingThreshold = 0.95;

  /// Specifica se le soglie dei pilastri cognitivi sono soddisfatte.
  final bool pillarsSatisfied;

  /// Specifica se il livello di allerta è compatibile con la vittoria.
  final bool alertSatisfied;

  /// La media corrente dei tre pilastri cognitivi.
  final double averagePillars;

  /// Il valore del pilastro più basso tra Imperativo, Controllo e Dissonanza.
  final int minimumPillar;

  /// Il limite massimo di allerta consentito per la vittoria in base alla media dei pilastri.
  final double maximumVictoryAlert;

  /// Il progresso numerico normalizzato verso le soglie di vittoria nell'intervallo [0.0, 1.0].
  ///
  /// Calcolato come `min(avgProgress, minPillarProgress)`, dove ciascun fattore è
  /// la proporzione del valore corrente rispetto alla rispettiva soglia configurata.
  final double numericProgress;

  /// Restituisce true se tutti i criteri numerici per la vittoria sono soddisfatti.
  bool get numericallyReady => pillarsSatisfied && alertSatisfied;

  /// Restituisce true se il progresso numerico ha raggiunto la fase finale (>= 95%)
  /// ma i pilastri non sono ancora completamente soddisfatti, e l'allerta è compatibile.
  ///
  /// Questo stato rappresenta l'avvicinamento imminente alla vittoria e attiva
  /// la traccia musicale `breakthrough` anche prima del completamento numerico completo.
  bool get approachingNumericalReadiness =>
      !pillarsSatisfied &&
      alertSatisfied &&
      numericProgress >= approachingThreshold;

  /// Costruttore costante per inizializzare lo stato di prontezza per la vittoria.
  const VictoryReadiness({
    required this.pillarsSatisfied,
    required this.alertSatisfied,
    required this.averagePillars,
    required this.minimumPillar,
    required this.maximumVictoryAlert,
    required this.numericProgress,
  });
}
