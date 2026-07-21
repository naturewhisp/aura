import 'application_bootstrap_request.dart';
import 'application_bootstrap_result.dart';

/// Interfaccia astratta del composition root applicativo di A.U.R.A.
abstract interface class ApplicationBootstrap {
  /// Esegue la fase di bootstrap e la selezione del runtime path in base alla richiesta.
  Future<ApplicationBootstrapResult> bootstrap(
    ApplicationBootstrapRequest request,
  );

  /// Dismette in modo sicuro e deterministico tutte le risorse create dal bootstrap.
  Future<void> dispose();
}
