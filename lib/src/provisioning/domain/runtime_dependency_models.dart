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

/// Sorgente di acquisizione del runtime `llama-server`.
enum RuntimeSource {
  bundled,
  external,
}

/// DTO immutabile che rappresenta la configurazione persistita della dipendenza runtime `llama-server`.
@immutable
final class LlamaServerConfiguration {
  final int schemaVersion;
  final RuntimeSource source;
  final String? variantId;
  final String? runtimeSetId;
  final String? externalExecutablePath;
  final String executablePath;
  final String? detectedVersion;
  final DateTime? lastValidatedAtUtc;
  final LlamaServerValidationStatus validationStatus;
  final RuntimeAcceleration acceleration;
  final String? gpuDeviceName;
  final int? gpuLayers;

  const LlamaServerConfiguration({
    this.schemaVersion = 1,
    this.source = RuntimeSource.external,
    this.variantId,
    this.runtimeSetId,
    String? externalExecutablePath,
    required this.executablePath,
    this.detectedVersion,
    this.lastValidatedAtUtc,
    this.validationStatus = LlamaServerValidationStatus.unknown,
    this.acceleration = RuntimeAcceleration.cpu,
    this.gpuDeviceName,
    this.gpuLayers,
  }) : externalExecutablePath = externalExecutablePath ??
            (source == RuntimeSource.external ? executablePath : null);

  factory LlamaServerConfiguration.fromJson(Map<String, dynamic> json) {
    final rawPath = (json['executablePath'] as String?)?.trim() ?? '';
    final rawSourceStr = json['source'] as String?;
    final variantId = json['variantId'] as String?;
    final runtimeSetId = json['runtimeSetId'] as String?;
    final externalPath = (json['externalExecutablePath'] as String?)?.trim();

    RuntimeSource source;
    if (rawSourceStr != null) {
      source = RuntimeSource.values.firstWhere(
        (s) => s.name == rawSourceStr,
        orElse: () =>
            variantId != null ? RuntimeSource.bundled : RuntimeSource.external,
      );
    } else {
      // Migrazione automatica da configurazione legacy basata unicamente su executablePath
      if (rawPath.contains('win-x64-cuda') ||
          rawPath.contains('windows-x64-cuda')) {
        source = RuntimeSource.bundled;
      } else if (rawPath.contains('win-x64-vulkan')) {
        source = RuntimeSource.bundled;
      } else if (rawPath.contains('win-x64-cpu') ||
          rawPath.contains('windows-x64-cpu')) {
        source = RuntimeSource.bundled;
      } else {
        source = RuntimeSource.external;
      }
    }

    final effectiveVariantId = variantId ??
        (rawPath.contains('win-x64-cuda')
            ? 'win-x64-cuda'
            : rawPath.contains('win-x64-vulkan')
                ? 'win-x64-vulkan'
                : rawPath.contains('win-x64-cpu')
                    ? 'win-x64-cpu-avx2'
                    : null);

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

    final effectiveExternalPath =
        externalPath ?? (source == RuntimeSource.external ? rawPath : null);

    return LlamaServerConfiguration(
      schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 1,
      source: source,
      variantId: effectiveVariantId,
      runtimeSetId: runtimeSetId,
      externalExecutablePath: effectiveExternalPath,
      executablePath: effectiveExternalPath ?? rawPath,
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
      'schemaVersion': schemaVersion,
      'source': source.name,
      if (variantId != null) 'variantId': variantId,
      if (runtimeSetId != null) 'runtimeSetId': runtimeSetId,
      if (externalExecutablePath != null)
        'externalExecutablePath': externalExecutablePath,
      if (source == RuntimeSource.external || variantId == null)
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
    int? schemaVersion,
    RuntimeSource? source,
    Object? variantId = _unset,
    Object? runtimeSetId = _unset,
    Object? externalExecutablePath = _unset,
    String? executablePath,
    Object? detectedVersion = _unset,
    Object? lastValidatedAtUtc = _unset,
    LlamaServerValidationStatus? validationStatus,
    RuntimeAcceleration? acceleration,
    Object? gpuDeviceName = _unset,
    Object? gpuLayers = _unset,
  }) {
    return LlamaServerConfiguration(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      source: source ?? this.source,
      variantId:
          identical(variantId, _unset) ? this.variantId : variantId as String?,
      runtimeSetId: identical(runtimeSetId, _unset)
          ? this.runtimeSetId
          : runtimeSetId as String?,
      externalExecutablePath: identical(externalExecutablePath, _unset)
          ? this.externalExecutablePath
          : externalExecutablePath as String?,
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
          schemaVersion == other.schemaVersion &&
          source == other.source &&
          variantId == other.variantId &&
          runtimeSetId == other.runtimeSetId &&
          externalExecutablePath == other.externalExecutablePath &&
          executablePath == other.executablePath &&
          detectedVersion == other.detectedVersion &&
          lastValidatedAtUtc == other.lastValidatedAtUtc &&
          validationStatus == other.validationStatus &&
          acceleration == other.acceleration &&
          gpuDeviceName == other.gpuDeviceName &&
          gpuLayers == other.gpuLayers;

  @override
  int get hashCode => Object.hash(
        schemaVersion,
        source,
        variantId,
        runtimeSetId,
        externalExecutablePath,
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
  final String? variantId;
  final RuntimeAcceleration declaredAcceleration;
  final RuntimeAcceleration acceleration;
  final String? fallbackReason;
  final List<String> warnings;

  const LlamaServerDetectionResult({
    this.configuredCandidate,
    this.isConfiguredValid = false,
    this.detectedFallback,
    this.effectiveCandidate,
    this.variantId,
    this.declaredAcceleration = RuntimeAcceleration.cpu,
    this.acceleration = RuntimeAcceleration.cpu,
    this.fallbackReason,
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
          effectiveCandidate == other.effectiveCandidate &&
          variantId == other.variantId &&
          declaredAcceleration == other.declaredAcceleration &&
          acceleration == other.acceleration &&
          fallbackReason == other.fallbackReason;

  @override
  int get hashCode => Object.hash(
        configuredCandidate,
        isConfiguredValid,
        detectedFallback,
        effectiveCandidate,
        variantId,
        declaredAcceleration,
        acceleration,
        fallbackReason,
      );

  @override
  String toString() =>
      'LlamaServerDetectionResult(effective: $effectiveCandidate, variant: $variantId, accel: ${acceleration.name}, fallbackReason: $fallbackReason)';
}

/// DTO che racchiude l'esito della validazione operativa del probe processuale di `llama-server`.
@immutable
final class LlamaServerValidationResult {
  final LlamaServerValidationStatus status;
  final String executablePath;
  final String? variantId;
  final String? detectedVersion;
  final DateTime? lastValidatedAtUtc;
  final String? errorMessage;
  final RuntimeAcceleration declaredAcceleration;
  final RuntimeAcceleration acceleration;
  final String? gpuDeviceName;

  const LlamaServerValidationResult({
    required this.status,
    required this.executablePath,
    this.variantId,
    this.detectedVersion,
    this.lastValidatedAtUtc,
    this.errorMessage,
    this.declaredAcceleration = RuntimeAcceleration.cpu,
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
