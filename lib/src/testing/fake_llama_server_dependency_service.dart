import 'dart:async';
import '../provisioning/domain/runtime_dependency_models.dart';
import '../provisioning/infrastructure/llama_server_dependency_service.dart';

/// Implementazione fake di [LlamaServerDependencyService] per widget e unit test.
final class FakeLlamaServerDependencyService
    implements LlamaServerDependencyService {
  final LlamaServerDetectionResult detectionResult;

  const FakeLlamaServerDependencyService({
    this.detectionResult = const LlamaServerDetectionResult(
      configuredCandidate: 'C:\\fake\\llama-server.exe',
      isConfiguredValid: true,
      effectiveCandidate: 'C:\\fake\\llama-server.exe',
      acceleration: RuntimeAcceleration.cuda,
    ),
  });

  @override
  Future<LlamaServerDetectionResult> detect() async => detectionResult;

  @override
  Future<LlamaServerValidationResult> validateExecutable({
    required String executablePath,
    String? variantId,
    List<String> vendorDirectories = const [],
  }) async =>
      LlamaServerValidationResult(
        status: LlamaServerValidationStatus.valid,
        executablePath: executablePath,
        variantId: variantId,
        acceleration: detectionResult.acceleration,
      );

  @override
  Future<LlamaServerConfiguration> configureExecutable({
    required String executablePath,
    String? variantId,
    RuntimeSource? source,
  }) async =>
      LlamaServerConfiguration(
        executablePath: executablePath,
        variantId: variantId,
        source: source ?? RuntimeSource.external,
        validationStatus: LlamaServerValidationStatus.valid,
        lastValidatedAtUtc: DateTime.now().toUtc(),
        acceleration: detectionResult.acceleration,
      );

  @override
  Future<void> clearConfiguration() async {}

  @override
  Future<LlamaServerConfiguration?> readConfiguration() async => null;
}
