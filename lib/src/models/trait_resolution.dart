import 'package:meta/meta.dart';

/// Rappresenta il risultato intermedio calcolato dalla risoluzione della Trait Matrix
/// per l'identità attiva. Permette di ispezionare le variazioni e le motivazioni dei tratti.
@immutable
class TraitResolution {
  /// Modificatore da applicare al delta allerta.
  final int deltaAlertModifier;

  /// Modificatore da applicare al delta imperativo.
  final int deltaImperativeModifier;

  /// Modificatore da applicare al delta controllo.
  final int deltaControlModifier;

  /// Modificatore da applicare al delta dissonanza.
  final int deltaDissonanceModifier;

  /// Modificatore da applicare al livello di risonanza.
  final double resonanceModifier;

  /// Tag occulti attivati da questa risoluzione dei tratti.
  final List<String> activatedHiddenTags;

  /// Direttive di recitazione aggiuntive suggerite per l'Actor.
  final List<String> actorCueDirectives;

  /// Motivazioni o log di debug per tracciare perché l'effetto è stato applicato.
  final List<String> debugReasons;

  /// Costruttore costante con parametri opzionali predefiniti.
  const TraitResolution({
    this.deltaAlertModifier = 0,
    this.deltaImperativeModifier = 0,
    this.deltaControlModifier = 0,
    this.deltaDissonanceModifier = 0,
    this.resonanceModifier = 0.0,
    this.activatedHiddenTags = const [],
    this.actorCueDirectives = const [],
    this.debugReasons = const [],
  });

  @override
  String toString() {
    return 'TraitResolution(alertMod: $deltaAlertModifier, imperativeMod: $deltaImperativeModifier, controlMod: $deltaControlModifier, dissonanceMod: $deltaDissonanceModifier, resMod: $resonanceModifier, tags: $activatedHiddenTags, reasons: $debugReasons)';
  }
}
