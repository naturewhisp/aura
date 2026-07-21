import 'application_bootstrap.dart';
import 'default_application_bootstrap.dart';

/// Factory esplicita per la creazione di istanze di [ApplicationBootstrap].
class ApplicationBootstrapFactory {
  /// Costruttore `const` per [ApplicationBootstrapFactory].
  const ApplicationBootstrapFactory();

  /// Crea e restituisce un nuovo composition root [ApplicationBootstrap].
  ApplicationBootstrap create() {
    return DefaultApplicationBootstrap();
  }
}
