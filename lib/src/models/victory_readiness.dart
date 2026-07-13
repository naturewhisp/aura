import 'package:meta/meta.dart';

/// Rappresenta lo stato di prontezza numerica per la vittoria in A.U.R.A.
///
/// Modella il soddisfacimento dei criteri legati alla media dei pilastri cognitivi
/// e al livello di allerta di PANOPTICON, fornendo dettagli diagnostici utili alla UI.
@immutable
class VictoryReadiness {
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

  /// Restituisce true se tutti i criteri numerici per la vittoria sono soddisfatti.
  bool get numericallyReady => pillarsSatisfied && alertSatisfied;

  /// Costruttore costante per inizializzare lo stato di prontezza per la vittoria.
  const VictoryReadiness({
    required this.pillarsSatisfied,
    required this.alertSatisfied,
    required this.averagePillars,
    required this.minimumPillar,
    required this.maximumVictoryAlert,
  });
}
