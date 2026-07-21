import 'package:meta/meta.dart';
import '../agent_runtime/runtime/adapters/external_openai/external_openai_client.dart';
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

  /// Mappa di variabili d'ambiente sovrascritte.
  final Map<String, String>? environmentOverride;

  /// Costruisce una richiesta di bootstrap.
  const ApplicationBootstrapRequest({
    required this.configuration,
    this.customRuntime,
    this.customHttpClient,
    this.environmentOverride,
  });
}
