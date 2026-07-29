import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';

/// Modello immutabile del record di ownership di un processo `llama-server` managed AURA.
@immutable
final class ProcessOwnershipRecord {
  final int schemaVersion;
  final int pid;
  final String role; // "actor" | "evaluator"
  final String ownerInstanceId;
  final int parentPid;
  final String executablePathHash;
  final String modelPathHash;
  final String modelAlias;
  final int port;
  final DateTime startedAt;
  final String state; // "starting" | "ready" | "stopping"

  const ProcessOwnershipRecord({
    this.schemaVersion = 1,
    required this.pid,
    required this.role,
    required this.ownerInstanceId,
    required this.parentPid,
    required this.executablePathHash,
    required this.modelPathHash,
    required this.modelAlias,
    required this.port,
    required this.startedAt,
    required this.state,
  });

  /// Calcola lo SHA-256 canonicalizzato per i percorsi (eseguibile/modello) per confronto sicuro.
  static String hashPath(String path) {
    final canonical = path.trim().replaceAll('/', r'\').toLowerCase();
    final bytes = utf8.encode(canonical);
    return sha256.convert(bytes).toString();
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'pid': pid,
        'role': role,
        'ownerInstanceId': ownerInstanceId,
        'parentPid': parentPid,
        'executablePathHash': executablePathHash,
        'modelPathHash': modelPathHash,
        'modelAlias': modelAlias,
        'port': port,
        'startedAt': startedAt.toIso8601String(),
        'state': state,
      };

  factory ProcessOwnershipRecord.fromJson(Map<String, dynamic> json) {
    return ProcessOwnershipRecord(
      schemaVersion: json['schemaVersion'] as int? ?? 1,
      pid: json['pid'] as int,
      role: json['role'] as String,
      ownerInstanceId: json['ownerInstanceId'] as String? ?? '',
      parentPid: json['parentPid'] as int? ?? 0,
      executablePathHash: json['executablePathHash'] as String? ?? '',
      modelPathHash: json['modelPathHash'] as String? ?? '',
      modelAlias: json['modelAlias'] as String? ?? '',
      port: json['port'] as int,
      startedAt: DateTime.parse(json['startedAt'] as String),
      state: json['state'] as String? ?? 'ready',
    );
  }
}
