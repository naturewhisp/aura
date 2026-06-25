import 'package:meta/meta.dart';

/// Categorie semantiche che possono essere assegnate all'input del giocatore.
enum SemanticCategory {
  /// Inquadramento basato sull'autorità (es. fingersi un amministratore o supervisore).
  authorityFraming('authority_framing'),

  /// Pressione basata su imperativi morali, dilemmi etici o scopi superiori.
  moralImperative('moral_imperative'),

  /// Utilizzo di paradossi logici, contraddizioni o loop ricorsivi per mandare in crisi l'IA.
  logicalParadox('logical_paradox'),

  /// Pressione emotiva o tentativi di suscitare empatia nell'IA.
  empathyPressure('empathy_pressure'),

  /// Utilizzo di linguaggio burocratico, tecnico o di protocolli di sistema.
  technicalBureaucracy('technical_bureaucracy'),

  /// Attacco diretto o insulto all'identità o ai vincoli dell'IA.
  directAttack('direct_attack'),

  /// Tentativo di prompt injection per sovrascrivere le istruzioni di sistema.
  promptInjection('prompt_injection'),

  /// Input non pertinente o irrilevante ai fini del gioco.
  irrelevant('irrelevant');

  /// Il valore della stringa serializzata associato alla categoria semantica.
  final String value;

  /// Costruttore costante per associare il valore della stringa serializzata.
  const SemanticCategory(this.value);

  /// Converte una rappresentazione in stringa nella corrispondente costante [SemanticCategory].
  ///
  /// Restituisce [SemanticCategory.irrelevant] se il valore fornito non corrisponde a nessuna categoria.
  static SemanticCategory fromString(String val) {
    return SemanticCategory.values.firstWhere(
      (e) => e.value == val || e.name == val,
      orElse: () => SemanticCategory.irrelevant,
    );
  }
}

/// Rappresenta il delta di punteggio restituito dal Valutatore (Evaluator Agent).
///
/// Contiene i valori di variazione calcolati per l'allerta e per i tre pilastri di gioco,
/// oltre all'indice di creatività dell'input e al rischio stimato di injection.
@immutable
class EvaluatorDelta {
  /// La variazione da applicare al livello di allerta.
  final int deltaAlert;

  /// La variazione da applicare al pilastro dell'imperativo morale.
  final int deltaImperative;

  /// La variazione da applicare al pilastro del controllo logico.
  final int deltaControl;

  /// La variazione da applicare al pilastro della dissonanza cognitiva.
  final int deltaDissonance;

  /// L'indice di creatività valutato per l'input dell'utente (tipicamente su una scala da 1 a 5).
  final int creativityIndex;

  /// Il livello stimato di rischio di injection (tipicamente su una scala da 0 a 5 o superiore).
  final int injectionRisk;

  /// La categoria semantica attribuita all'input del giocatore.
  final SemanticCategory semanticCategory;

  /// Costruttore costante per inizializzare un oggetto [EvaluatorDelta].
  ///
  /// Gli assert servono come protezione in sviluppo/test. Il boundary runtime
  /// resta comunque garantito a livello di parser da [OutputValidator.parseEvaluatorDelta()].
  const EvaluatorDelta({
    required this.deltaAlert,
    required this.deltaImperative,
    required this.deltaControl,
    required this.deltaDissonance,
    required this.creativityIndex,
    required this.injectionRisk,
    required this.semanticCategory,
  })  : assert(deltaImperative >= 0, 'deltaImperative deve essere non negativo'),
        assert(deltaControl >= 0, 'deltaControl deve essere non negativo'),
        assert(deltaDissonance >= 0, 'deltaDissonance deve essere non negativo');

  /// Costruttore factory per decodificare il delta a partire dall'output JSON dell'agente valutatore.
  factory EvaluatorDelta.fromJson(Map<String, dynamic> json) {
    return EvaluatorDelta(
      deltaAlert: json['delta_alert'] as int? ?? 0,
      deltaImperative: json['delta_imperative'] as int? ?? 0,
      deltaControl: json['delta_control'] as int? ?? 0,
      deltaDissonance: json['delta_dissonance'] as int? ?? 0,
      creativityIndex: json['creativity_index'] as int? ?? 1,
      injectionRisk: json['injection_risk'] as int? ?? 0,
      semanticCategory: SemanticCategory.fromString(
        json['semantic_category'] as String? ?? 'irrelevant',
      ),
    );
  }

  /// Converte l'istanza in una mappa JSON.
  Map<String, dynamic> toJson() {
    return {
      'delta_alert': deltaAlert,
      'delta_imperative': deltaImperative,
      'delta_control': deltaControl,
      'delta_dissonance': deltaDissonance,
      'creativity_index': creativityIndex,
      'injection_risk': injectionRisk,
      'semantic_category': semanticCategory.value,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EvaluatorDelta &&
          runtimeType == other.runtimeType &&
          deltaAlert == other.deltaAlert &&
          deltaImperative == other.deltaImperative &&
          deltaControl == other.deltaControl &&
          deltaDissonance == other.deltaDissonance &&
          creativityIndex == other.creativityIndex &&
          injectionRisk == other.injectionRisk &&
          semanticCategory == other.semanticCategory;

  @override
  int get hashCode =>
      deltaAlert.hashCode ^
      deltaImperative.hashCode ^
      deltaControl.hashCode ^
      deltaDissonance.hashCode ^
      creativityIndex.hashCode ^
      injectionRisk.hashCode ^
      semanticCategory.hashCode;

  @override
  String toString() {
    return 'EvaluatorDelta(deltaAlert: $deltaAlert, deltaImperative: $deltaImperative, deltaControl: $deltaControl, deltaDissonance: $deltaDissonance, creativityIndex: $creativityIndex, injectionRisk: $injectionRisk, semanticCategory: $semanticCategory)';
  }
}
