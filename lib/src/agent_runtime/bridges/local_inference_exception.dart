/// Eccezione tipizzata sollevata da un bridge di inferenza HTTP locale.
class LocalInferenceException implements Exception {
  /// Il codice di stato HTTP (es. 400, 401, 422, 500) se presente.
  final int? statusCode;

  /// Codice di errore specifico restituito dal backend o dalla libreria se presente.
  final String? backendErrorCode;

  /// L'eccezione o l'errore causale sottostante.
  final Object? cause;

  /// Messaggio diagnostico sanitizzato, privo di dati utente o percorsi locali (max 200 char).
  final String diagnosticMessage;

  LocalInferenceException({
    required this.diagnosticMessage,
    this.statusCode,
    this.backendErrorCode,
    this.cause,
  });

  /// Costruisce una [LocalInferenceException] sanitizzando il corpo o il messaggio di errore HTTP.
  factory LocalInferenceException.fromHttp({
    required int statusCode,
    required String rawBody,
    String? backendCode,
  }) {
    // Sanitizza eliminando possibili frammenti di prompt o dati riservati
    String snippet = rawBody.replaceAll(RegExp(r'[\r\n\t]+'), ' ').trim();
    if (snippet.length > 150) {
      snippet = '${snippet.substring(0, 147)}...';
    }
    final diag =
        'HTTP $statusCode: ${snippet.isEmpty ? "Server Error" : snippet}';
    final cleanDiag = diag.length > 200 ? diag.substring(0, 200) : diag;

    return LocalInferenceException(
      statusCode: statusCode,
      backendErrorCode: backendCode,
      diagnosticMessage: cleanDiag,
    );
  }

  @override
  String toString() => diagnosticMessage;
}
