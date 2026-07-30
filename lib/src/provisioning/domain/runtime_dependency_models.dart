import 'package:meta/meta.dart';

/// Tipo di accelerazione hardware rilevato o supportato dal runtime `llama-server`.
enum RuntimeAcceleration {
  /// Accelerazione GPU NVIDIA via CUDA Toolkit / cuBLAS.
  cuda,

  /// Accelerazione GPU cross-platform via Vulkan SDK.
  vulkan,

  /// Esecuzione standard su CPU senza accelerazione GPU dedicata.
  cpu,
}

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
  final RuntimeAcceleration acceleration;
  final String? gpuDeviceName;
  final int? gpuLayers;

  const LlamaServerConfiguration({
    required this.executablePath,
    this.detectedVersion,
    this.lastValidatedAtUtc,
    this.validationStatus = LlamaServerValidationStatus.unknown,
    this.acceleration = RuntimeAcceleration.cpu,
    this.gpuDeviceName,
    this.gpuLayers,
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

    final accelStr = json['acceleration'] as String?;
    final accel = RuntimeAcceleration.values.firstWhere(
      (a) => a.name == accelStr,
      orElse: () => RuntimeAcceleration.cpu,
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
      acceleration: accel,
      gpuDeviceName: json['gpuDeviceName'] as String?,
      gpuLayers: (json['gpuLayers'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'executablePath': executablePath,
      if (detectedVersion != null) 'detectedVersion': detectedVersion,
      if (lastValidatedAtUtc != null)
        'lastValidatedAtUtc': lastValidatedAtUtc!.toUtc().toIso8601String(),
      'validationStatus': validationStatus.name,
      'acceleration': acceleration.name,
      if (gpuDeviceName != null) 'gpuDeviceName': gpuDeviceName,
      if (gpuLayers != null) 'gpuLayers': gpuLayers,
    };
  }

  LlamaServerConfiguration copyWith({
    String? executablePath,
    Object? detectedVersion = _unset,
    Object? lastValidatedAtUtc = _unset,
    LlamaServerValidationStatus? validationStatus,
    RuntimeAcceleration? acceleration,
    Object? gpuDeviceName = _unset,
    Object? gpuLayers = _unset,
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
      acceleration: acceleration ?? this.acceleration,
      gpuDeviceName: identical(gpuDeviceName, _unset)
          ? this.gpuDeviceName
          : gpuDeviceName as String?,
      gpuLayers:
          identical(gpuLayers, _unset) ? this.gpuLayers : gpuLayers as int?,
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
          validationStatus == other.validationStatus &&
          acceleration == other.acceleration &&
          gpuDeviceName == other.gpuDeviceName &&
          gpuLayers == other.gpuLayers;

  @override
  int get hashCode => Object.hash(
        executablePath,
        detectedVersion,
        lastValidatedAtUtc,
        validationStatus,
        acceleration,
        gpuDeviceName,
        gpuLayers,
      );

  @override
  String toString() =>
      'LlamaServerConfiguration(path: $executablePath, status: ${validationStatus.name}, accel: ${acceleration.name}, version: $detectedVersion)';
}

/// DTO che racchiude l'esito del processo di discovery deterministica di `llama-server`.
@immutable
final class LlamaServerDetectionResult {
  final String? configuredCandidate;
  final bool isConfiguredValid;
  final String? detectedFallback;
  final String? effectiveCandidate;
  final List<String> warnings;
  final RuntimeAcceleration acceleration;

  const LlamaServerDetectionResult({
    this.configuredCandidate,
    this.isConfiguredValid = false,
    this.detectedFallback,
    this.effectiveCandidate,
    this.warnings = const [],
    this.acceleration = RuntimeAcceleration.cpu,
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
          effectiveCandidate == other.effectiveCandidate &&
          acceleration == other.acceleration;

  @override
  int get hashCode => Object.hash(
        configuredCandidate,
        isConfiguredValid,
        detectedFallback,
        effectiveCandidate,
        acceleration,
      );

  @override
  String toString() =>
      'LlamaServerDetectionResult(effective: $effectiveCandidate, accel: ${acceleration.name}, configuredValid: $isConfiguredValid)';
}

/// DTO che racchiude l'esito della validazione operativa del probe processuale di `llama-server`.
@immutable
final class LlamaServerValidationResult {
  final LlamaServerValidationStatus status;
  final String executablePath;
  final String? detectedVersion;
  final DateTime? lastValidatedAtUtc;
  final String? errorMessage;
  final RuntimeAcceleration acceleration;
  final String? gpuDeviceName;

  const LlamaServerValidationResult({
    required this.status,
    required this.executablePath,
    this.detectedVersion,
    this.lastValidatedAtUtc,
    this.errorMessage,
    this.acceleration = RuntimeAcceleration.cpu,
    this.gpuDeviceName,
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
          errorMessage == other.errorMessage &&
          acceleration == other.acceleration &&
          gpuDeviceName == other.gpuDeviceName;

  @override
  int get hashCode => Object.hash(
        status,
        executablePath,
        detectedVersion,
        lastValidatedAtUtc,
        errorMessage,
        acceleration,
        gpuDeviceName,
      );

  @override
  String toString() =>
      'LlamaServerValidationResult(status: ${status.name}, accel: ${acceleration.name}, path: $executablePath)';
}
