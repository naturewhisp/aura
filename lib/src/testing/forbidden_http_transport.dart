import 'dart:async';
import '../agent_runtime/runtime/adapters/external_openai/external_openai_client.dart';
import '../provisioning/domain/provisioning_cancellation_token.dart';
import '../provisioning/infrastructure/provisioning_http_client.dart';
import 'test_runtime_policy.dart';

/// A [ProvisioningHttpClient] implementation that enforces test network guardrails.
///
/// Unconditionally throws [StateError] whenever a remote download attempt is made in tests.
final class ForbiddenProvisioningHttpClient implements ProvisioningHttpClient {
  final TestRuntimePolicy policy;

  const ForbiddenProvisioningHttpClient({
    this.policy = TestRuntimePolicy.neverNative,
  });

  @override
  Future<int> downloadFile({
    required String uri,
    required String targetPath,
    required int expectedSizeBytes,
    ProvisioningCancellationToken? cancellationToken,
    RedirectHostPolicy redirectHostPolicy = RedirectHostPolicy.sameHostOnly,
    Set<String> allowedRedirectHosts = const {},
    Duration timeout = const Duration(minutes: 5),
  }) {
    throw StateError(
      'Remote artifact downloads are strictly forbidden during tests (policy: ${policy.name}). Attempted URI: $uri',
    );
  }

  @override
  Future<void> close() async {}
}

/// An [ExternalOpenAiClient] decorator that enforces loopback vs external network guardrails based on [TestRuntimePolicy].
final class GuardedExternalOpenAiClient implements ExternalOpenAiClient {
  final ExternalOpenAiClient delegate;
  final TestRuntimePolicy policy;
  final String serverUrl;

  GuardedExternalOpenAiClient({
    required this.delegate,
    required this.policy,
    required this.serverUrl,
  });

  void _validateNetworkAccess() {
    if (!policy.allowsLocalhost) {
      throw StateError(
        'Network access is strictly forbidden under test policy ${policy.name}. Target: $serverUrl',
      );
    }

    final uri = Uri.parse(serverUrl);
    final isLoopback = uri.host == '127.0.0.1' || uri.host == 'localhost';
    if (!isLoopback && !policy.allowsExternalNetwork) {
      throw StateError(
        'External (non-loopback) network access is strictly forbidden during tests. Target host: ${uri.host}',
      );
    }
  }

  @override
  bool get supportsRequestCancellation => delegate.supportsRequestCancellation;

  @override
  Future<ExternalOpenAiResponse> chatCompletions(
    Map<String, dynamic> payload, {
    String? requestId,
  }) {
    _validateNetworkAccess();
    return delegate.chatCompletions(payload, requestId: requestId);
  }

  @override
  Future<List<String>> discoverModels() {
    _validateNetworkAccess();
    return delegate.discoverModels();
  }

  @override
  Future<bool> checkHealth() {
    _validateNetworkAccess();
    return delegate.checkHealth();
  }

  @override
  Future<void> cancel(String requestId) {
    _validateNetworkAccess();
    return delegate.cancel(requestId);
  }

  @override
  Future<void> close() => delegate.close();
}

/// A strictly forbidden [ExternalOpenAiClient] implementation for offline tests.
final class ForbiddenExternalOpenAiClient implements ExternalOpenAiClient {
  const ForbiddenExternalOpenAiClient();

  @override
  bool get supportsRequestCancellation => false;

  @override
  Future<ExternalOpenAiResponse> chatCompletions(
    Map<String, dynamic> payload, {
    String? requestId,
  }) {
    throw StateError(
      'An external HTTP request was unexpectedly attempted during offline test execution.',
    );
  }

  @override
  Future<List<String>> discoverModels() {
    throw StateError(
      'Model discovery network call was unexpectedly attempted during offline test execution.',
    );
  }

  @override
  Future<bool> checkHealth() {
    throw StateError(
      'Health check network call was unexpectedly attempted during offline test execution.',
    );
  }

  @override
  Future<void> cancel(String requestId) async {}

  @override
  Future<void> close() async {}
}
