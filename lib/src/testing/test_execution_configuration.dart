import 'test_runtime_policy.dart';

/// Immutable configuration driving test execution behavior and physical path resolution.
final class TestExecutionConfiguration {
  /// Active runtime policy for the current test run.
  final TestRuntimePolicy runtimePolicy;

  /// Optional path to physical `llama-server.exe` executable.
  final String? runtimePath;

  /// Optional path to manifest file (`manifest.json`).
  final String? manifestPath;

  /// Optional path to minimal GGUF model for native smoke testing.
  final String? smokeModelPath;

  /// Optional path to real production Actor GGUF model.
  final String? actorModelPath;

  /// Optional path to real production Evaluator GGUF model.
  final String? evaluatorModelPath;

  /// Expected acceleration backend (e.g., 'cuda', 'vulkan', 'cpu').
  final String? requiredAcceleration;

  /// Destination file path for machine-readable JSON execution report.
  final String? reportPath;

  /// Whether temporary runtime log files should be preserved after execution.
  final bool keepLogs;

  const TestExecutionConfiguration({
    required this.runtimePolicy,
    this.runtimePath,
    this.manifestPath,
    this.smokeModelPath,
    this.actorModelPath,
    this.evaluatorModelPath,
    this.requiredAcceleration,
    this.reportPath,
    this.keepLogs = false,
  });

  /// Resolves configuration from environment variables.
  ///
  /// Environment Variables Evaluated:
  /// - `AURA_TEST_RUNTIME_POLICY`: `neverNative` (default) | `nativeSmoke` | `requireInstalledModels`
  /// - `AURA_TEST_RUNTIME_PATH`
  /// - `AURA_TEST_MANIFEST_PATH`
  /// - `AURA_TEST_SMOKE_MODEL_PATH`
  /// - `AURA_TEST_ACTOR_MODEL_PATH`
  /// - `AURA_TEST_EVALUATOR_MODEL_PATH`
  /// - `AURA_TEST_REQUIRE_ACCELERATION`
  /// - `AURA_TEST_REPORT_PATH`
  /// - `AURA_TEST_KEEP_LOGS` ('1' or 'true')
  factory TestExecutionConfiguration.fromEnvironment(Map<String, String> env) {
    final policyRaw = env['AURA_TEST_RUNTIME_POLICY']?.trim();
    final policy = switch (policyRaw) {
      'nativeSmoke' => TestRuntimePolicy.nativeSmoke,
      'requireInstalledModels' => TestRuntimePolicy.requireInstalledModels,
      _ => TestRuntimePolicy.neverNative,
    };

    final keepLogsRaw = env['AURA_TEST_KEEP_LOGS']?.trim().toLowerCase();
    final keepLogs = keepLogsRaw == '1' || keepLogsRaw == 'true';

    return TestExecutionConfiguration(
      runtimePolicy: policy,
      runtimePath: _nonEmptyOrNull(env['AURA_TEST_RUNTIME_PATH']),
      manifestPath: _nonEmptyOrNull(env['AURA_TEST_MANIFEST_PATH']),
      smokeModelPath: _nonEmptyOrNull(env['AURA_TEST_SMOKE_MODEL_PATH']),
      actorModelPath: _nonEmptyOrNull(env['AURA_TEST_ACTOR_MODEL_PATH']),
      evaluatorModelPath:
          _nonEmptyOrNull(env['AURA_TEST_EVALUATOR_MODEL_PATH']),
      requiredAcceleration:
          _nonEmptyOrNull(env['AURA_TEST_REQUIRE_ACCELERATION']),
      reportPath: _nonEmptyOrNull(env['AURA_TEST_REPORT_PATH']),
      keepLogs: keepLogs,
    );
  }

  static String? _nonEmptyOrNull(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
