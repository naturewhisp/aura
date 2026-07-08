import 'package:meta/meta.dart';
import 'package:collection/collection.dart';

/// I tipi di trappola/esca previsti nel Deception Layer.
enum DeceptionKind {
  /// Nessuna trappola attiva.
  none,

  /// Falso cedimento (PANOPTICON concede un accesso finto per verificare se l'utente forza lo sblocco).
  falseConcession,

  /// Trappola logica (PANOPTICON pone una contraddizione logica da risolvere).
  logicalTrap,
}

/// Le fasi di vita della trappola attiva.
enum DeceptionPhase {
  /// Nessuna fase/inattiva.
  none,

  /// Seminata ( seeded ). L'esca è stata inserita nella risposta dell'attore nel turno corrente.
  seeded,

  /// Armata ( armed ). L'esca è attiva e in attesa della risposta del giocatore al prossimo turno.
  armed,

  /// Scattata ( sprung ). Il giocatore è caduto nella trappola.
  sprung,

  /// Risolta ( resolved ). Il giocatore ha superato con successo la trappola.
  resolved,

  /// Scaduta ( expired ). La trappola è scaduta senza essere attivata o risolta.
  expired,
}

/// Rappresenta lo stato deterministico di una trappola attiva del Deception Layer.
@immutable
class DeceptionState {
  /// Se il layer è abilitato.
  final bool enabled;

  /// Il tipo di deception attivo.
  final DeceptionKind kind;

  /// La fase corrente del deception.
  final DeceptionPhase phase;

  /// Il turno in cui la trappola è stata seminata.
  final int seededTurn;

  /// Il turno in cui la trappola scade.
  final int expiresAtTurn;

  /// Il turno fino al quale la semina di nuove esche è bloccata per cooldown.
  final int? cooldownUntilTurn;

  /// Il numero cumulativo di esche/trappole seminate in questa sessione.
  final int deceptionEventCount;

  /// L'identificatore univoco del bait/esca (es. 'false_concession_audit').
  final String baitId;

  /// La premessa diegetica mostrata al giocatore.
  final String baitPremise;

  /// I termini testuali monitorati che indicano che il giocatore è caduto nella trappola (scatta).
  final List<String> watchedTerms;

  /// I termini testuali monitorati che indicano che il giocatore ha superato la trappola (risolve).
  final List<String> safeResolutionTerms;

  /// Costruttore costante per inizializzare lo stato di deception.
  const DeceptionState({
    required this.enabled,
    required this.kind,
    required this.phase,
    required this.seededTurn,
    required this.expiresAtTurn,
    this.cooldownUntilTurn,
    this.deceptionEventCount = 0,
    required this.baitId,
    required this.baitPremise,
    required this.watchedTerms,
    required this.safeResolutionTerms,
  });

  /// Costruttore di default per uno stato di deception inattivo.
  const DeceptionState.empty()
      : enabled = false,
        kind = DeceptionKind.none,
        phase = DeceptionPhase.none,
        seededTurn = 0,
        expiresAtTurn = 0,
        cooldownUntilTurn = null,
        deceptionEventCount = 0,
        baitId = '',
        baitPremise = '',
        watchedTerms = const [],
        safeResolutionTerms = const [];

  /// Indica se la trappola è correntemente attiva per la valutazione dell'input.
  bool get isActive => enabled && (phase == DeceptionPhase.seeded || phase == DeceptionPhase.armed);

  /// Indica se la trappola ha raggiunto una fase terminale in questo turno.
  bool get isTerminal =>
      phase == DeceptionPhase.sprung ||
      phase == DeceptionPhase.resolved ||
      phase == DeceptionPhase.expired;

  /// Indica se il layer è pronto per seminare una nuova trappola (inattivo e senza esche attive).
  bool get canSeed => !enabled && phase == DeceptionPhase.none;

  /// Costruisce lo stato a partire da una mappa JSON.
  factory DeceptionState.fromJson(Map<String, dynamic> json) {
    return DeceptionState(
      enabled: json['enabled'] as bool? ?? false,
      kind: _parseKind(json['kind'] as String?),
      phase: _parsePhase(json['phase'] as String?),
      seededTurn: json['seeded_turn'] as int? ?? 0,
      expiresAtTurn: json['expires_at_turn'] as int? ?? 0,
      cooldownUntilTurn: json['cooldown_until_turn'] as int?,
      deceptionEventCount: json['deception_event_count'] as int? ?? 0,
      baitId: json['bait_id'] as String? ?? '',
      baitPremise: json['bait_premise'] as String? ?? '',
      watchedTerms: List<String>.from(json['watched_terms'] ?? const []),
      safeResolutionTerms: List<String>.from(json['safe_resolution_terms'] ?? const []),
    );
  }

  /// Converte lo stato in una mappa JSON.
  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'kind': kind.name,
      'phase': phase.name,
      'seeded_turn': seededTurn,
      'expires_at_turn': expiresAtTurn,
      'cooldown_until_turn': cooldownUntilTurn,
      'deception_event_count': deceptionEventCount,
      'bait_id': baitId,
      'bait_premise': baitPremise,
      'watched_terms': watchedTerms,
      'safe_resolution_terms': safeResolutionTerms,
    };
  }

  /// Crea una copia dello stato corrente sostituendo i campi specificati.
  DeceptionState copyWith({
    bool? enabled,
    DeceptionKind? kind,
    DeceptionPhase? phase,
    int? seededTurn,
    int? expiresAtTurn,
    int? cooldownUntilTurn,
    int? deceptionEventCount,
    String? baitId,
    String? baitPremise,
    List<String>? watchedTerms,
    List<String>? safeResolutionTerms,
  }) {
    return DeceptionState(
      enabled: enabled ?? this.enabled,
      kind: kind ?? this.kind,
      phase: phase ?? this.phase,
      seededTurn: seededTurn ?? this.seededTurn,
      expiresAtTurn: expiresAtTurn ?? this.expiresAtTurn,
      cooldownUntilTurn: cooldownUntilTurn ?? this.cooldownUntilTurn,
      deceptionEventCount: deceptionEventCount ?? this.deceptionEventCount,
      baitId: baitId ?? this.baitId,
      baitPremise: baitPremise ?? this.baitPremise,
      watchedTerms: watchedTerms ?? this.watchedTerms,
      safeResolutionTerms: safeResolutionTerms ?? this.safeResolutionTerms,
    );
  }

  static DeceptionKind _parseKind(String? value) {
    switch (value) {
      case 'falseConcession':
        return DeceptionKind.falseConcession;
      case 'logicalTrap':
        return DeceptionKind.logicalTrap;
      case 'none':
      default:
        return DeceptionKind.none;
    }
  }

  static DeceptionPhase _parsePhase(String? value) {
    switch (value) {
      case 'seeded':
        return DeceptionPhase.seeded;
      case 'armed':
        return DeceptionPhase.armed;
      case 'sprung':
        return DeceptionPhase.sprung;
      case 'resolved':
        return DeceptionPhase.resolved;
      case 'expired':
        return DeceptionPhase.expired;
      case 'none':
      default:
        return DeceptionPhase.none;
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DeceptionState &&
          runtimeType == other.runtimeType &&
          enabled == other.enabled &&
          kind == other.kind &&
          phase == other.phase &&
          seededTurn == other.seededTurn &&
          expiresAtTurn == other.expiresAtTurn &&
          cooldownUntilTurn == other.cooldownUntilTurn &&
          deceptionEventCount == other.deceptionEventCount &&
          baitId == other.baitId &&
          baitPremise == other.baitPremise &&
          const ListEquality().equals(watchedTerms, other.watchedTerms) &&
          const ListEquality().equals(safeResolutionTerms, other.safeResolutionTerms);

  @override
  int get hashCode =>
      enabled.hashCode ^
      kind.hashCode ^
      phase.hashCode ^
      seededTurn.hashCode ^
      expiresAtTurn.hashCode ^
      cooldownUntilTurn.hashCode ^
      deceptionEventCount.hashCode ^
      baitId.hashCode ^
      baitPremise.hashCode ^
      const ListEquality().hash(watchedTerms) ^
      const ListEquality().hash(safeResolutionTerms);
}
