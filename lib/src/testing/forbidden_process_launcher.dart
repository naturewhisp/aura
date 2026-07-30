import '../agent_runtime/runtime/adapters/managed_llama_server/process_launcher.dart';
import 'test_runtime_policy.dart';

/// A [ProcessLauncher] decorator/implementation that enforces [TestRuntimePolicy] guardrails.
///
/// Throws a [StateError] whenever a native process execution is requested under a policy
/// that forbids native process execution (e.g. `neverNative`).
final class GuardedTestProcessLauncher implements ProcessLauncher {
  final ProcessLauncher delegate;
  final TestRuntimePolicy policy;

  const GuardedTestProcessLauncher({
    required this.delegate,
    required this.policy,
  });

  @override
  Future<ManagedProcess> start(ProcessLaunchRequest request) async {
    if (!policy.allowsNativeProcesses) {
      throw StateError(
        'Native process execution is strictly disabled under policy ${policy.name}. '
        'A native process (${request.executable}) was requested by an offline test.',
      );
    }
    return delegate.start(request);
  }
}

/// A strictly forbidden [ProcessLauncher] implementation for offline testing.
///
/// Unconditionally throws [StateError] on any process start attempt.
final class ForbiddenProcessLauncher implements ProcessLauncher {
  const ForbiddenProcessLauncher();

  @override
  Future<ManagedProcess> start(ProcessLaunchRequest request) {
    throw StateError(
      'A native process (${request.executable}) was unexpectedly requested by an offline test.',
    );
  }
}
