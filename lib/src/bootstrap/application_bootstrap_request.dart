import 'package:meta/meta.dart';
import '../agent_runtime/runtime/adapters/external_openai/external_openai_client.dart';
import '../agent_runtime/runtime/adapters/external_openai/external_openai_configuration.dart';
import '../agent_runtime/runtime/adapters/external_openai/external_openai_runtime.dart';
import '../agent_runtime/runtime/adapters/managed_llama_server/llama_server_health_probe.dart';
import '../agent_runtime/runtime/adapters/managed_llama_server/port_allocator.dart';
import '../agent_runtime/runtime/adapters/managed_llama_server/process_launcher.dart';
import '../agent_runtime/runtime/inference_runtime.dart';
import 'application_runtime_configuration.dart';

/// Richiesta di bootstrap contenente la configurazione applicativa ed eventuali override per i test.
@immutable
class ApplicationBootstrapRequest {
  /// Configurazione del runtime applicativo.
  final ApplicationRuntimeConfiguration configuration;

  /// Custom [InferenceRuntime] per iniezione nei test.
  final InferenceRuntime? customRuntime;

  /// Custom [ExternalOpenAiClient] per iniezione nei test.
  final ExternalOpenAiClient? customHttpClient;

  /// Custom [ProcessLauncher] per iniezione nei test managed llama-server.
  final ProcessLauncher? customProcessLauncher;

  /// Custom [PortAllocator] per iniezione nei test managed llama-server.
  final PortAllocator? customPortAllocator;

  /// Custom [HealthProbe] per iniezione nei test managed llama-server.
  final HealthProbe? customHealthProbe;

  /// Custom delegate factory per `ExternalOpenAiRuntime` nei test.
  final ExternalOpenAiRuntime Function(ExternalOpenAiConfiguration config)?
      customDelegateFactory;

  /// Mappa di variabili d'ambiente sovrascritte.
  final Map<String, String>? environmentOverride;

  /// Costruisce una richiesta di bootstrap.
  const ApplicationBootstrapRequest({
    required this.configuration,
    this.customRuntime,
    this.customHttpClient,
    this.customProcessLauncher,
    this.customPortAllocator,
    this.customHealthProbe,
    this.customDelegateFactory,
    this.environmentOverride,
  });
}
