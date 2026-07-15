import 'config_diagnostic.dart';

/// Interfaccia per il sink di tracciamento degli eventi diagnostici delle configurazioni.
abstract interface class DiagnosticSink {
  /// Registra un singolo evento diagnostico.
  void report(ConfigDiagnostic diagnostic);
}

/// Implementazione no-op predefinita di [DiagnosticSink] che ignora tutte le segnalazioni.
final class NullDiagnosticSink implements DiagnosticSink {
  const NullDiagnosticSink();

  @override
  void report(ConfigDiagnostic diagnostic) {}
}
