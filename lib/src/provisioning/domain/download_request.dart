import 'package:meta/meta.dart';
import 'provisioning_options.dart';

/// Richiesta immutabile di download per un artefatto di modello nello staging.
@immutable
final class DownloadRequest {
  /// Identificatore unico dell'operazione di download.
  final String operationId;

  /// Identificatore logico dell'artefatto (es. `gemma-4-12b-it-qat-q4_0`).
  final String artifactId;

  /// URI HTTPS di origine da cui scaricare la risorsa.
  final Uri sourceUri;

  /// Dimensione attesa in byte dichiarata dal catalogo.
  final int expectedSizeBytes;

  /// Header HTTP aggiuntivi opzionali forniti dal chiamante.
  final Map<String, String>? extraHeaders;

  /// Timeout opzionale per l'intera operazione di download o per inattività.
  final Duration? timeout;

  /// Header riservati gestiti dal motore che non possono essere sovrascritti da [extraHeaders].
  static const Set<String> _restrictedHeaders = {
    'range',
    'if-range',
    'host',
    'content-length',
    'connection',
  };

  DownloadRequest({
    required this.operationId,
    required this.artifactId,
    required this.sourceUri,
    required this.expectedSizeBytes,
    this.extraHeaders,
    this.timeout,
  }) {
    if (operationId.trim().isEmpty) {
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.invalidCatalog,
        message: 'operationId non puo essere vuoto.',
      );
    }
    if (artifactId.trim().isEmpty) {
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.invalidCatalog,
        message: 'artifactId non puo essere vuoto.',
      );
    }
    if (!sourceUri.hasScheme ||
        (sourceUri.scheme != 'https' && sourceUri.scheme != 'http')) {
      throw ProvisioningException(
        reason: ProvisioningFailureReason.invalidCatalog,
        message:
            'sourceUri deve essere un URI HTTP/HTTPS valido: "${sourceUri.toString()}".',
      );
    }
    if (expectedSizeBytes <= 0) {
      throw ProvisioningException(
        reason: ProvisioningFailureReason.invalidCatalog,
        message:
            'expectedSizeBytes deve essere un intero positivo (>0): $expectedSizeBytes.',
      );
    }
  }

  /// Restituisce la mappa degli header sanitizzati rimuovendo eventuali header riservati sovrascritti.
  Map<String, String> get sanitizedExtraHeaders {
    if (extraHeaders == null || extraHeaders!.isEmpty) {
      return const {};
    }
    final sanitized = <String, String>{};
    for (final entry in extraHeaders!.entries) {
      if (!_restrictedHeaders.contains(entry.key.toLowerCase())) {
        sanitized[entry.key] = entry.value;
      }
    }
    return Map<String, String>.unmodifiable(sanitized);
  }
}
