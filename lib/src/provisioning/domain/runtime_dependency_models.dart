import 'package:meta/meta.dart';

/// Stato di validazione dell'eseguibile `llama-server`.
enum LlamaServerValidationStatus {
  unknown,
  valid,
  missing,
  notExecutable,
  probeFailed,
  incompatible,
}

/// DTO immutabile che rappresenta la configurazione persistita della dipendenza runtime `llama-server`.
@immutable
final class LlamaServerConfiguration {
  final String executablePath;
  final String? detectedVersion;
  final DateTime? lastValidatedAtUtc;
  final LlamaServerValidationStatus validationStatus;

  const LlamaServerConfiguration({
    required this.executablePath,
    this.detectedVersion,
    this.lastValidatedAtUtc,
    this.validationStatus = LlamaServerValidationStatus.unknown,
  });

  factory LlamaServerConfiguration.fromJson(Map<String, dynamic> json) {
    final path = json['executablePath'] as String?;
    if (path == null || path.trim().isEmpty) {
      throw const FormatException(
        'Campo "executablePath" mancante o vuoto in LlamaServerConfiguration.',
      );
    }

    final statusStr = json['validationStatus'] as String?;
    final status = LlamaServerValidationStatus.values.firstWhere(
      (s) => s.name == statusStr,
      orElse: () => LlamaServerValidationStatus.unknown,
    );

    final lastValidatedStr = json['lastValidatedAtUtc'] as String?;
    final lastValidated = lastValidatedStr != null
        ? DateTime.tryParse(lastValidatedStr)?.toUtc()
        : null;

    return LlamaServerConfiguration(
      executablePath: path.trim(),
      detectedVersion: json['detectedVersion'] as String?,
      lastValidatedAtUtc: lastValidated,
      validationStatus: status,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'executablePath': executablePath,
      if (detectedVersion != null) 'detectedVersion': detectedVersion,
      if (lastValidatedAtUtc != null)
        'lastValidatedAtUtc': lastValidatedAtUtc!.toUtc().toIso8601String(),
      'validationStatus': validationStatus.name,
    };
  }

  LlamaServerConfiguration copyWith({
    String? executablePath,
    Object? detectedVersion = _unset,
    Object? lastValidatedAtUtc = _unset,
    LlamaServerValidationStatus? validationStatus,
  }) {
    return LlamaServerConfiguration(
      executablePath: executablePath ?? this.executablePath,
      detectedVersion: identical(detectedVersion, _unset)
          ? this.detectedVersion
          : detectedVersion as String?,
      lastValidatedAtUtc: identical(lastValidatedAtUtc, _unset)
          ? this.lastValidatedAtUtc
          : lastValidatedAtUtc as DateTime?,
      validationStatus: validationStatus ?? this.validationStatus,
    );
  }

  static const Object _unset = Object();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LlamaServerConfiguration &&
          runtimeType == other.runtimeType &&
          executablePath == other.executablePath &&
          detectedVersion == other.detectedVersion &&
          lastValidatedAtUtc == other.lastValidatedAtUtc &&
          validationStatus == other.validationStatus;

  @override
  int get hashCode => Object.hash(
        executablePath,
        detectedVersion,
        lastValidatedAtUtc,
        validationStatus,
      );

  @override
  String toString() =>
      'LlamaServerConfiguration(path: $executablePath, status: ${validationStatus.name}, version: $detectedVersion)';
}

/// DTO che racchiude l'esito del processo di discovery deterministica di `llama-server`.
@immutable
final class LlamaServerDetectionResult {
  final String? configuredCandidate;
  final bool isConfiguredValid;
  final String? detectedFallback;
  final String? effectiveCandidate;
  final List<String> warnings;

  const LlamaServerDetectionResult({
    this.configuredCandidate,
    this.isConfiguredValid = false,
    this.detectedFallback,
    this.effectiveCandidate,
    this.warnings = const [],
  });

  bool get isFound => effectiveCandidate != null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LlamaServerDetectionResult &&
          runtimeType == other.runtimeType &&
          configuredCandidate == other.configuredCandidate &&
          isConfiguredValid == other.isConfiguredValid &&
          detectedFallback == other.detectedFallback &&
          effectiveCandidate == other.effectiveCandidate;

  @override
  int get hashCode => Object.hash(
        configuredCandidate,
        isConfiguredValid,
        detectedFallback,
        effectiveCandidate,
      );

  @override
  String toString() =>
      'LlamaServerDetectionResult(effective: $effectiveCandidate, configuredValid: $isConfiguredValid)';
}

/// DTO che racchiude l'esito della validazione operativa del probe processuale di `llama-server`.
@immutable
final class LlamaServerValidationResult {
  final LlamaServerValidationStatus status;
  final String executablePath;
  final String? detectedVersion;
  final DateTime? lastValidatedAtUtc;
  final String? errorMessage;

  const LlamaServerValidationResult({
    required this.status,
    required this.executablePath,
    this.detectedVersion,
    this.lastValidatedAtUtc,
    this.errorMessage,
  });

  bool get isValid => status == LlamaServerValidationStatus.valid;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LlamaServerValidationResult &&
          runtimeType == other.runtimeType &&
          status == other.status &&
          executablePath == other.executablePath &&
          detectedVersion == other.detectedVersion &&
          lastValidatedAtUtc == other.lastValidatedAtUtc &&
          errorMessage == other.errorMessage;

  @override
  int get hashCode => Object.hash(
        status,
        executablePath,
        detectedVersion,
        lastValidatedAtUtc,
        errorMessage,
      );

  @override
  String toString() =>
      'LlamaServerValidationResult(status: ${status.name}, path: $executablePath)';
}
