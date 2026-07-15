/// Livelli di severità per le diagnostiche di configurazione.
enum ConfigDiagnosticSeverity {
  info,
  warning,
  error,
}

/// Codici diagnostici stabili per categorizzare le anomalie di configurazione.
enum ConfigDiagnosticCode {
  sourceReturnedNull,
  asyncLoadFailed,
  syncLoadUnsupported,
  syncLoadFailed,
  fallbackUsed,
  invalidJson,
  invalidStructure,
  mappingFailed,
  preloadSucceeded,
}

/// Rappresenta un evento diagnostico immutabile emesso durante il caricamento o parsing delle configurazioni.
final class ConfigDiagnostic {
  final ConfigDiagnosticSeverity severity;
  final ConfigDiagnosticCode code;
  final String path;
  final String operation;
  final String message;
  final Object? error;
  final StackTrace? stackTrace;
  final bool fallbackUsed;

  const ConfigDiagnostic({
    required this.severity,
    required this.code,
    required this.path,
    required this.operation,
    required this.message,
    this.error,
    this.stackTrace,
    this.fallbackUsed = false,
  });

  @override
  String toString() {
    final buffer = StringBuffer()
      ..write(
          '[$severity] Code: $code, Path: $path, Op: $operation, Msg: $message');
    if (fallbackUsed) {
      buffer.write(' (Fallback Used)');
    }
    if (error != null) {
      buffer.write(', Error: $error');
    }
    return buffer.toString();
  }
}
