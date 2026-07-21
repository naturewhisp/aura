import 'package:meta/meta.dart';
import '../../runtime_backend.dart';

/// Strategy used to probe the health of an external OpenAI-compatible backend.
enum ExternalOpenAiHealthStrategy {
  /// Probes the `/v1/models` endpoint as health indicator.
  modelsEndpoint,

  /// Probes a custom health endpoint path if available.
  customEndpoint,
}

/// Immutable, platform-neutral configuration for [ExternalOpenAiRuntime].
@immutable
class ExternalOpenAiConfiguration {
  /// Base URI of the external server (e.g. `http://127.0.0.1:1234`).
  final Uri baseUri;

  /// Identifier for this adapter instance.
  final String adapterId;

  /// Human-readable name for the runtime.
  final String runtimeName;

  /// Optional server or adapter version string.
  final String? runtimeVersion;

  /// HTTP transport timeout limit.
  final Duration transportTimeout;

  /// Strategy used to check server health.
  final ExternalOpenAiHealthStrategy healthStrategy;

  /// Custom path for health checks if using [ExternalOpenAiHealthStrategy.customEndpoint].
  final String healthEndpointPath;

  /// Relative path for model discovery endpoint.
  final String modelsEndpointPath;

  /// Relative path for chat completions endpoint.
  final String chatCompletionsEndpointPath;

  /// Static HTTP headers appended to all requests.
  final Map<String, String> staticHeaders;

  /// Optional API key for authentication (not logged in error messages).
  final String? apiKey;

  /// Whether model discovery is supported by the server.
  final bool supportsDiscovery;

  /// Reported execution backend.
  final RuntimeBackend selectedBackend;

  /// Maximum concurrent generations supported.
  final int maxConcurrentGenerations;

  /// Maximum simultaneously loaded models supported.
  final int maxLoadedModels;

  /// Whether JSON schema structured output is supported.
  final bool supportsStructuredJson;

  /// Whether real request-level cancellation is supported.
  final bool supportsCancellation;

  /// Whether multiple loaded models are supported.
  final bool supportsMultipleLoadedModels;

  const ExternalOpenAiConfiguration({
    required this.baseUri,
    this.adapterId = 'adapter.external.openai',
    this.runtimeName = 'External OpenAI-Compatible Runtime',
    this.runtimeVersion = '1.0.0',
    this.transportTimeout = const Duration(seconds: 300),
    this.healthStrategy = ExternalOpenAiHealthStrategy.modelsEndpoint,
    this.healthEndpointPath = '/v1/models',
    this.modelsEndpointPath = '/v1/models',
    this.chatCompletionsEndpointPath = '/v1/chat/completions',
    this.staticHeaders = const {},
    this.apiKey,
    this.supportsDiscovery = true,
    this.selectedBackend = RuntimeBackend.external,
    this.maxConcurrentGenerations = 1,
    this.maxLoadedModels = 1,
    this.supportsStructuredJson = true,
    this.supportsCancellation = false,
    this.supportsMultipleLoadedModels = false,
  });

  /// Default configuration for local development backends (e.g., LM Studio / llama-server).
  factory ExternalOpenAiConfiguration.developmentDefault({
    Uri? baseUri,
    String? apiKey,
  }) {
    return ExternalOpenAiConfiguration(
      baseUri: baseUri ?? Uri.parse('http://127.0.0.1:1234'),
      apiKey: apiKey,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExternalOpenAiConfiguration &&
          runtimeType == other.runtimeType &&
          baseUri == other.baseUri &&
          adapterId == other.adapterId &&
          runtimeName == other.runtimeName &&
          transportTimeout == other.transportTimeout &&
          supportsCancellation == other.supportsCancellation;

  @override
  int get hashCode => Object.hash(
        baseUri,
        adapterId,
        runtimeName,
        transportTimeout,
        supportsCancellation,
      );
}
