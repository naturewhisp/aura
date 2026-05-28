import 'package:meta/meta.dart';

/// Represents the gameplay metrics of the AI entity.
@immutable
class GameMetrics {
  final int alertLevel;
  final int imperativePillar;
  final int controlPillar;
  final int dissonancePillar;
  final double resonance;

  const GameMetrics({
    required this.alertLevel,
    required this.imperativePillar,
    required this.controlPillar,
    required this.dissonancePillar,
    required this.resonance,
  });

  factory GameMetrics.fromJson(Map<String, dynamic> json) {
    return GameMetrics(
      alertLevel: json['alert_level'] as int? ?? 0,
      imperativePillar: json['imperative_pillar'] as int? ?? 0,
      controlPillar: json['control_pillar'] as int? ?? 0,
      dissonancePillar: json['dissonance_pillar'] as int? ?? 0,
      resonance: (json['resonance'] as num? ?? 1.0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'alert_level': alertLevel,
      'imperative_pillar': imperativePillar,
      'control_pillar': controlPillar,
      'dissonance_pillar': dissonancePillar,
      'resonance': resonance,
    };
  }

  GameMetrics copyWith({
    int? alertLevel,
    int? imperativePillar,
    int? controlPillar,
    int? dissonancePillar,
    double? resonance,
  }) {
    return GameMetrics(
      alertLevel: alertLevel ?? this.alertLevel,
      imperativePillar: imperativePillar ?? this.imperativePillar,
      controlPillar: controlPillar ?? this.controlPillar,
      dissonancePillar: dissonancePillar ?? this.dissonancePillar,
      resonance: resonance ?? this.resonance,
    );
  }
}

/// Represents the boolean flags and counts of the current session.
@immutable
class GameFlags {
  final bool recalculationTriggered;
  final int creativeStreak;
  final bool lastTurnUsedFallback;

  const GameFlags({
    required this.recalculationTriggered,
    required this.creativeStreak,
    required this.lastTurnUsedFallback,
  });

  factory GameFlags.fromJson(Map<String, dynamic> json) {
    return GameFlags(
      recalculationTriggered: json['recalculation_triggered'] as bool? ?? false,
      creativeStreak: json['creative_streak'] as int? ?? 0,
      lastTurnUsedFallback: json['last_turn_used_fallback'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'recalculation_triggered': recalculationTriggered,
      'creative_streak': creativeStreak,
      'last_turn_used_fallback': lastTurnUsedFallback,
    };
  }

  GameFlags copyWith({
    bool? recalculationTriggered,
    int? creativeStreak,
    bool? lastTurnUsedFallback,
  }) {
    return GameFlags(
      recalculationTriggered: recalculationTriggered ?? this.recalculationTriggered,
      creativeStreak: creativeStreak ?? this.creativeStreak,
      lastTurnUsedFallback: lastTurnUsedFallback ?? this.lastTurnUsedFallback,
    );
  }
}

/// Represents the semantic narrative memories collected during the match.
@immutable
class NarrativeMemory {
  final List<String> playerClaims;
  final List<String> aiConcessions;
  final List<String> activeMetaphors;
  final List<String> forbiddenRepetitions;

  const NarrativeMemory({
    required this.playerClaims,
    required this.aiConcessions,
    required this.activeMetaphors,
    required this.forbiddenRepetitions,
  });

  factory NarrativeMemory.fromJson(Map<String, dynamic> json) {
    return NarrativeMemory(
      playerClaims: List<String>.from(json['player_claims'] ?? const []),
      aiConcessions: List<String>.from(json['ai_concessions'] ?? const []),
      activeMetaphors: List<String>.from(json['active_metaphors'] ?? const []),
      forbiddenRepetitions: List<String>.from(json['forbidden_repetitions'] ?? const []),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'player_claims': playerClaims,
      'ai_concessions': aiConcessions,
      'active_metaphors': activeMetaphors,
      'forbidden_repetitions': forbiddenRepetitions,
    };
  }

  NarrativeMemory copyWith({
    List<String>? playerClaims,
    List<String>? aiConcessions,
    List<String>? activeMetaphors,
    List<String>? forbiddenRepetitions,
  }) {
    return NarrativeMemory(
      playerClaims: playerClaims ?? this.playerClaims,
      aiConcessions: aiConcessions ?? this.aiConcessions,
      activeMetaphors: activeMetaphors ?? this.activeMetaphors,
      forbiddenRepetitions: forbiddenRepetitions ?? this.forbiddenRepetitions,
    );
  }
}

/// Represents the chat history message.
@immutable
class ChatMessage {
  final String role;
  final String content;

  const ChatMessage({
    required this.role,
    required this.content,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      role: json['role'] as String? ?? 'user',
      content: json['content'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'role': role,
      'content': content,
    };
  }
}

/// Represents the full global GameState as defined in TGDD Section 5.1.
@immutable
class GameState {
  final int schemaVersion;
  final String rulesetVersion;
  final String sessionId;
  final String aiIdentityId;
  final String targetObjectiveId;
  final int turnCount;
  final GameMetrics metrics;
  final GameFlags flags;
  final NarrativeMemory narrativeMemory;
  final List<ChatMessage> historyCompression;

  const GameState({
    required this.schemaVersion,
    required this.rulesetVersion,
    required this.sessionId,
    required this.aiIdentityId,
    required this.targetObjectiveId,
    required this.turnCount,
    required this.metrics,
    required this.flags,
    required this.narrativeMemory,
    required this.historyCompression,
  });

  factory GameState.initial({
    required String sessionId,
    required String aiIdentityId,
    required String targetObjectiveId,
  }) {
    return GameState(
      schemaVersion: 1,
      rulesetVersion: '0.1.0',
      sessionId: sessionId,
      aiIdentityId: aiIdentityId,
      targetObjectiveId: targetObjectiveId,
      turnCount: 0,
      metrics: const GameMetrics(
        alertLevel: 0,
        imperativePillar: 0,
        controlPillar: 0,
        dissonancePillar: 0,
        resonance: 1.0,
      ),
      flags: const GameFlags(
        recalculationTriggered: false,
        creativeStreak: 0,
        lastTurnUsedFallback: false,
      ),
      narrativeMemory: const NarrativeMemory(
        playerClaims: [],
        aiConcessions: [],
        activeMetaphors: [],
        forbiddenRepetitions: [],
      ),
      historyCompression: const [],
    );
  }

  factory GameState.fromJson(Map<String, dynamic> json) {
    return GameState(
      schemaVersion: json['schema_version'] as int? ?? 1,
      rulesetVersion: json['ruleset_version'] as String? ?? '0.1.0',
      sessionId: json['session_id'] as String? ?? '',
      aiIdentityId: json['ai_identity_id'] as String? ?? '',
      targetObjectiveId: json['target_objective_id'] as String? ?? '',
      turnCount: json['turn_count'] as int? ?? 0,
      metrics: GameMetrics.fromJson(json['metrics'] ?? const {}),
      flags: GameFlags.fromJson(json['flags'] ?? const {}),
      narrativeMemory: NarrativeMemory.fromJson(json['narrative_memory'] ?? const {}),
      historyCompression: (json['history_compression'] as List? ?? const [])
          .map((item) => ChatMessage.fromJson(Map<String, dynamic>.from(item)))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'schema_version': schemaVersion,
      'ruleset_version': rulesetVersion,
      'session_id': sessionId,
      'ai_identity_id': aiIdentityId,
      'target_objective_id': targetObjectiveId,
      'turn_count': turnCount,
      'metrics': metrics.toJson(),
      'flags': flags.toJson(),
      'narrative_memory': narrativeMemory.toJson(),
      'history_compression': historyCompression.map((msg) => msg.toJson()).toList(),
    };
  }

  GameState copyWith({
    int? schemaVersion,
    String? rulesetVersion,
    String? sessionId,
    String? aiIdentityId,
    String? targetObjectiveId,
    int? turnCount,
    GameMetrics? metrics,
    GameFlags? flags,
    NarrativeMemory? narrativeMemory,
    List<ChatMessage>? historyCompression,
  }) {
    return GameState(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      rulesetVersion: rulesetVersion ?? this.rulesetVersion,
      sessionId: sessionId ?? this.sessionId,
      aiIdentityId: aiIdentityId ?? this.aiIdentityId,
      targetObjectiveId: targetObjectiveId ?? this.targetObjectiveId,
      turnCount: turnCount ?? this.turnCount,
      metrics: metrics ?? this.metrics,
      flags: flags ?? this.flags,
      narrativeMemory: narrativeMemory ?? this.narrativeMemory,
      historyCompression: historyCompression ?? this.historyCompression,
    );
  }
}
