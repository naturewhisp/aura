import 'package:meta/meta.dart';

/// Codici di fallimento tipizzati per le operazioni di bootstrap dell'applicazione.
enum ApplicationBootstrapFailureCode {
  /// Modalità runtime non riconosciuta o non supportata.
  unknownMode,

  /// URI del server di inferenza non valida o priva di schema.
  invalidUri,

  /// Configurazione incompleta o incongruente.
  incompleteConfiguration,

  /// Identificatore del modello Attore mancante o vuoto.
  missingActorModelId,

  /// Identificatore del modello Valutatore mancante o vuoto.
  missingEvaluatorModelId,

  /// Controllo di integrità (health check) del runtime fallito.
  healthCheckFailed,

  /// Creazione del binding del modello o del ruolo fallita.
  bindingFailed,

  /// Caricamento dell'handle del modello fallito.
  modelLoadFailed,

  /// Inizializzazione dell'InferenceRuntime fallita.
  runtimeInitializationFailed,

  /// Operazione tentata su un bootstrap già dismesso (disposed).
  alreadyDisposed,

  /// Tentativo di rieseguire il bootstrap su un'istanza già inizializzata.
  alreadyBootstrapped,

  /// Errore durante la dismissione (dispose) delle risorse.
  disposeFailed,
}

/// Modello di fallimento tipizzato per la fase di composition root e bootstrap.
@immutable
class ApplicationBootstrapFailure {
  /// Codice di fallimento specifico.
  final ApplicationBootstrapFailureCode code;

  /// Messaggio di errore sanitizzato, idoneo alla registrazione e alla UI.
  final String message;

  /// Informazioni diagnostiche aggiuntive non sensibili.
  final Map<String, Object?> diagnostics;

  /// Costruisce un'istanza di [ApplicationBootstrapFailure].
  const ApplicationBootstrapFailure({
    required this.code,
    required this.message,
    this.diagnostics = const {},
  });

  @override
  String toString() => 'ApplicationBootstrapFailure($code: $message)';
}

/// Eccezione di bootstrap che incapsula [ApplicationBootstrapFailure] per prevenire il leak di eccezioni grezze.
class ApplicationBootstrapException implements Exception {
  /// Dettagli del fallimento di bootstrap.
  final ApplicationBootstrapFailure failure;

  /// Causa sottostante opzionale (es. eccezione originale).
  final Object? cause;

  /// Costruisce un'istanza di [ApplicationBootstrapException].
  const ApplicationBootstrapException(this.failure, [this.cause]);

  @override
  String toString() => 'ApplicationBootstrapException: ${failure.message}';
}
