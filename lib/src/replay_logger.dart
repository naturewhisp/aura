import 'package:meta/meta.dart';
import 'models/evaluator_delta.dart';

/// Represents a single recorded turn in the replay log.
@immutable
class ReplayEntry {
  final int turnId;
  final String userInput;
  final EvaluatorDelta evaluatorOutput;
  final Map<String, dynamic> stateBefore;
  final Map<String, dynamic> stateAfter;
  final String actorResponse;
  final String actorRequestId;
  final String actorResponseHash;
  final String evaluatorModel;
  final String actorModel;
  final int latencyTotalMs;

  const ReplayEntry({
    required this.turnId,
    required this.userInput,
    required this.evaluatorOutput,
    required this.stateBefore,
    required this.stateAfter,
    required this.actorResponse,
    required this.actorRequestId,
    required this.actorResponseHash,
    required this.evaluatorModel,
    required this.actorModel,
    required this.latencyTotalMs,
  });

  /// Factory constructor to parse a replay entry from JSON.
  factory ReplayEntry.fromJson(Map<String, dynamic> json) {
    final runtime = json['runtime'] as Map<String, dynamic>? ?? const {};
    return ReplayEntry(
      turnId: json['turn_id'] as int? ?? 0,
      userInput: json['user_input'] as String? ?? '',
      evaluatorOutput: EvaluatorDelta.fromJson(json['evaluator_output'] ?? const {}),
      stateBefore: Map<String, dynamic>.from(json['state_before'] ?? const {}),
      stateAfter: Map<String, dynamic>.from(json['state_after'] ?? const {}),
      actorResponse: json['actor_response'] as String? ?? '',
      actorRequestId: json['actor_request_id'] as String? ?? '',
      actorResponseHash: json['actor_response_hash'] as String? ?? '',
      evaluatorModel: runtime['evaluator_model'] as String? ?? '',
      actorModel: runtime['actor_model'] as String? ?? '',
      latencyTotalMs: runtime['latency_total_ms'] as int? ?? 0,
    );
  }

  /// Converts the entry to JSON as specified in TGDD Section 16.1.
  Map<String, dynamic> toJson() {
    return {
      'turn_id': turnId,
      'user_input': userInput,
      'evaluator_output': evaluatorOutput.toJson(),
      'state_before': stateBefore,
      'state_after': stateAfter,
      'actor_response': actorResponse,
      'actor_request_id': actorRequestId,
      'actor_response_hash': actorResponseHash,
      'runtime': {
        'evaluator_model': evaluatorModel,
        'actor_model': actorModel,
        'latency_total_ms': latencyTotalMs,
      }
    };
  }
}

/// Manages and aggregates replay logs for a full game session.
class ReplayLogger {
  final String sessionId;
  final List<ReplayEntry> _entries = [];

  ReplayLogger({required this.sessionId});

  /// Returns an unmodifiable list of all log entries.
  List<ReplayEntry> get entries => List.unmodifiable(_entries);

  /// Appends a new turn's replay entry.
  void logTurn(ReplayEntry entry) {
    _entries.add(entry);
  }

  /// Converts the full session log to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'session_id': sessionId,
      'total_turns': _entries.length,
      'entries': _entries.map((e) => e.toJson()).toList(),
    };
  }

  /// Restores a logger session from JSON.
  factory ReplayLogger.fromJson(Map<String, dynamic> json) {
    final logger = ReplayLogger(sessionId: json['session_id'] as String? ?? '');
    final list = json['entries'] as List? ?? const [];
    for (var item in list) {
      logger.logTurn(ReplayEntry.fromJson(Map<String, dynamic>.from(item)));
    }
    return logger;
  }
}
