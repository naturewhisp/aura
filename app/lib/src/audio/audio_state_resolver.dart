import 'package:aura_core/aura_core.dart';
import 'audio_scene.dart';

/// Risolvitore deterministico puro per lo stato della scena musicale durante il gameplay di A.U.R.A.
///
/// Questa classe non possiede stato interno e isola la logica semantica di selezione
/// dell'audio dalle chiamate tecniche ai player o dall'interfaccia utente grafica.
class AudioStateResolver {
  /// Risolve lo stato musicale target in base allo stato corrente della sessione.
  ///
  /// Le priorità applicate sono:
  /// 1. Sconfitta (defeat) -> se l'outcome è sconfitta.
  /// 2. Vittoria (victory) -> se l'outcome è vittoria.
  /// 3. Deception attiva o sprung -> se c'è una trappola attiva o appena attivata di PANOPTICON.
  /// 4. Breakthrough -> se l'outcome è partita in corso, ma i criteri numerici sono pienamente soddisfatti.
  /// 5. Tense -> se il livello di allerta è >= 40.
  /// 6. Ambient -> default per gameplay standard a bassa allerta.
  static AudioSceneState resolve({
    required GameState state,
    required GameOutcome outcome,
    required VictoryReadiness readiness,
  }) {
    // 1. Defeat
    if (outcome == GameOutcome.defeat) {
      return AudioSceneState.defeat;
    }

    // 2. Victory
    if (outcome == GameOutcome.victory) {
      return AudioSceneState.victory;
    }

    // 3. Deception Attiva o Sprung
    final deception = state.deceptionState;
    final deceptionThreat = deception.isActive || deception.phase == DeceptionPhase.sprung;
    if (deceptionThreat) {
      return AudioSceneState.gameTense;
    }

    // 4. Breakthrough (ongoing AND numericallyReady AND no Deception active/sprung)
    if (outcome == GameOutcome.ongoing && readiness.numericallyReady) {
      return AudioSceneState.breakthrough;
    }

    // 5. Alert >= 40 -> gameTense
    if (state.metrics.alertLevel >= 40) {
      return AudioSceneState.gameTense;
    }

    // 6. Ambient
    return AudioSceneState.gameAmbient;
  }
}
