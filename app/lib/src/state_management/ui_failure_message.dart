import 'package:aura_core/aura_core.dart';

/// Converte un'eccezione in un messaggio mostrabile in UI senza stringificarla.
///
/// `e.toString()` può esporre percorsi locali, endpoint o header: si usano solo
/// i messaggi già sanitizzati dei fallimenti tipizzati (politica "Zero Exception
/// Stringification" di AGENTS.md).
String uiFailureMessage(Object error) {
  if (error is ApplicationBootstrapException) {
    return error.failure.message;
  }
  if (error is RuntimeException) {
    return error.failure.message;
  }
  // I fallimenti fail-closed del bootstrap sollevano StateError con un
  // messaggio già sanitizzato dal resolver di configurazione.
  if (error is StateError) {
    return error.message;
  }
  return 'Errore interno non classificato. Consultare i log diagnostici.';
}
