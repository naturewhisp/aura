import 'package:meta/meta.dart';

/// Metadati di provenance dinamica generati a livello di singolo turno di dialogo.
///
/// Registra i parametri effettivi di campionamento, il modello o motore di inferenza
/// realmente impiegato, l'eventuale ricorso a fallback euristici e la latenza totale
/// dell'interazione per il monitoraggio della qualità e per il dataset LoRA (Fase 8).
@immutable
class TurnGenerationProvenance {
  /// Parametri di campionamento effettivi utilizzati durante questo turno
  /// (es. temperature, top_p, top_k, seed).
  final Map<String, dynamic> samplingParameters;

  /// Modello che ha effettivamente generato la battuta diegetica dell'attore.
  final String actualActorModelId;

  /// Modello o motore che ha calcolato la classificazione semantica dell'input.
  final String actualEvaluatorModelId;

  /// Modalità di esecuzione del valutatore (es. "llmJsonSchema", "ruleBasedFallback").
  final String? evaluatorExecutionMode;

  /// Indica se l'inferenza primaria neurale è fallita ed è intervenuto il fallback deterministico.
  final bool usedRuleFallback;

  /// Latenza totale di elaborazione misurata per questo turno (ms).
  final int latencyTotalMs;

  const TurnGenerationProvenance({
    required this.samplingParameters,
    required this.actualActorModelId,
    required this.actualEvaluatorModelId,
    this.evaluatorExecutionMode,
    this.usedRuleFallback = false,
    required this.latencyTotalMs,
  });

  /// Converte l'istanza in una mappa JSON.
  Map<String, dynamic> toJson() => {
        'samplingParameters': samplingParameters,
        'actualActorModelId': actualActorModelId,
        'actualEvaluatorModelId': actualEvaluatorModelId,
        if (evaluatorExecutionMode != null)
          'evaluatorExecutionMode': evaluatorExecutionMode,
        'usedRuleFallback': usedRuleFallback,
        'latencyTotalMs': latencyTotalMs,
      };

  /// Ripristina un'istanza [TurnGenerationProvenance] a partire da una mappa JSON.
  factory TurnGenerationProvenance.fromJson(Map<String, dynamic> json) {
    return TurnGenerationProvenance(
      samplingParameters: Map<String, dynamic>.from(
          json['samplingParameters'] as Map? ?? const {}),
      actualActorModelId: json['actualActorModelId'] as String? ?? 'unknown',
      actualEvaluatorModelId:
          json['actualEvaluatorModelId'] as String? ?? 'unknown',
      evaluatorExecutionMode: json['evaluatorExecutionMode'] as String?,
      usedRuleFallback: json['usedRuleFallback'] as bool? ?? false,
      latencyTotalMs: json['latencyTotalMs'] as int? ?? 0,
    );
  }

  /// Crea una copia dell'istanza sostituendo solo i campi specificati.
  TurnGenerationProvenance copyWith({
    Map<String, dynamic>? samplingParameters,
    String? actualActorModelId,
    String? actualEvaluatorModelId,
    String? evaluatorExecutionMode,
    bool? usedRuleFallback,
    int? latencyTotalMs,
  }) {
    return TurnGenerationProvenance(
      samplingParameters: samplingParameters ?? this.samplingParameters,
      actualActorModelId: actualActorModelId ?? this.actualActorModelId,
      actualEvaluatorModelId:
          actualEvaluatorModelId ?? this.actualEvaluatorModelId,
      evaluatorExecutionMode:
          evaluatorExecutionMode ?? this.evaluatorExecutionMode,
      usedRuleFallback: usedRuleFallback ?? this.usedRuleFallback,
      latencyTotalMs: latencyTotalMs ?? this.latencyTotalMs,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TurnGenerationProvenance &&
          runtimeType == other.runtimeType &&
          actualActorModelId == other.actualActorModelId &&
          actualEvaluatorModelId == other.actualEvaluatorModelId &&
          evaluatorExecutionMode == other.evaluatorExecutionMode &&
          usedRuleFallback == other.usedRuleFallback &&
          latencyTotalMs == other.latencyTotalMs &&
          _mapsEqual(samplingParameters, other.samplingParameters);

  @override
  int get hashCode => Object.hash(
        actualActorModelId,
        actualEvaluatorModelId,
        evaluatorExecutionMode,
        usedRuleFallback,
        latencyTotalMs,
        Object.hashAll(
            samplingParameters.entries.map((e) => Object.hash(e.key, e.value))),
      );

  @override
  String toString() =>
      'TurnGenerationProvenance(actor: $actualActorModelId, eval: $actualEvaluatorModelId, mode: $evaluatorExecutionMode, fallback: $usedRuleFallback, latency: ${latencyTotalMs}ms)';

  static bool _mapsEqual(Map<String, dynamic> a, Map<String, dynamic> b) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || a[key] != b[key]) return false;
    }
    return true;
  }
}
