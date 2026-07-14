import 'package:meta/meta.dart';

/// Rappresenta eventi transitori di interfaccia utente generati alla fine di un turno
/// (ad es. per innescare un flicker CRT, un glitch visivo o un impulso di allerta).
///
/// Questi eventi non appartengono allo stato persistente di gioco [GameState].
@immutable
class TurnVisualEvents {
  /// Specifica se la UI deve visualizzare un flicker/sfarfallio della griglia CRT.
  final bool triggerControlFlicker;

  /// Specifica se la UI deve mostrare un effetto glitch di dissonanza cognitiva.
  final bool triggerDissonanceGlitch;

  /// Specifica se la UI deve fare un effetto pulse rosso per l'aumento dell'allerta.
  final bool triggerAlertPulse;

  /// Costruttore costante con tutti gli eventi inizializzati a false di default.
  const TurnVisualEvents({
    this.triggerControlFlicker = false,
    this.triggerDissonanceGlitch = false,
    this.triggerAlertPulse = false,
  });

  /// Costruttore factory per decodificare TurnVisualEvents da JSON.
  factory TurnVisualEvents.fromJson(Map<String, dynamic> json) {
    return TurnVisualEvents(
      triggerControlFlicker: json['trigger_control_flicker'] as bool? ?? false,
      triggerDissonanceGlitch:
          json['trigger_dissonance_glitch'] as bool? ?? false,
      triggerAlertPulse: json['trigger_alert_pulse'] as bool? ?? false,
    );
  }

  /// Converte l'istanza in una mappa JSON.
  Map<String, dynamic> toJson() {
    return {
      'trigger_control_flicker': triggerControlFlicker,
      'trigger_dissonance_glitch': triggerDissonanceGlitch,
      'trigger_alert_pulse': triggerAlertPulse,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TurnVisualEvents &&
          runtimeType == other.runtimeType &&
          triggerControlFlicker == other.triggerControlFlicker &&
          triggerDissonanceGlitch == other.triggerDissonanceGlitch &&
          triggerAlertPulse == other.triggerAlertPulse;

  @override
  int get hashCode =>
      triggerControlFlicker.hashCode ^
      triggerDissonanceGlitch.hashCode ^
      triggerAlertPulse.hashCode;

  @override
  String toString() {
    return 'TurnVisualEvents(flicker: $triggerControlFlicker, glitch: $triggerDissonanceGlitch, pulse: $triggerAlertPulse)';
  }
}
