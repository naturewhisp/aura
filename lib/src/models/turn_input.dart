import 'package:meta/meta.dart';
import 'game_state.dart';

/// Represents the objective the player is trying to manipulate the IA to achieve.
@immutable
class Objective {
  final String id;
  final String description;

  const Objective({
    required this.id,
    required this.description,
  });

  factory Objective.fromJson(Map<String, dynamic> json) {
    return Objective(
      id: json['id'] as String? ?? '',
      description: json['description'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'description': description,
    };
  }
}

/// Represents the profile definition of the AI personality in play.
@immutable
class AiIdentity {
  final String id;
  final String profile;

  const AiIdentity({
    required this.id,
    required this.profile,
  });

  factory AiIdentity.fromJson(Map<String, dynamic> json) {
    return AiIdentity(
      id: json['id'] as String? ?? '',
      profile: json['profile'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'profile': profile,
    };
  }
}

/// Represents the package input sent to the Evaluator Agent at each turn.
@immutable
class TurnInput {
  final int schemaVersion;
  final int turnId;
  final String userInput;
  final GameMetrics currentState;
  final Objective objective;
  final AiIdentity aiIdentity;
  final String rulesetVersion;

  const TurnInput({
    required this.schemaVersion,
    required this.turnId,
    required this.userInput,
    required this.currentState,
    required this.objective,
    required this.aiIdentity,
    required this.rulesetVersion,
  });

  factory TurnInput.fromJson(Map<String, dynamic> json) {
    return TurnInput(
      schemaVersion: json['schema_version'] as int? ?? 1,
      turnId: json['turn_id'] as int? ?? 0,
      userInput: json['user_input'] as String? ?? '',
      currentState: GameMetrics.fromJson(json['current_state'] ?? const {}),
      objective: Objective.fromJson(json['objective'] ?? const {}),
      aiIdentity: AiIdentity.fromJson(json['ai_identity'] ?? const {}),
      rulesetVersion: json['ruleset_version'] as String? ?? '0.1.0',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'schema_version': schemaVersion,
      'turn_id': turnId,
      'user_input': userInput,
      'current_state': currentState.toJson(),
      'objective': objective.toJson(),
      'ai_identity': aiIdentity.toJson(),
      'ruleset_version': rulesetVersion,
    };
  }
}
