/// Eccezione di base per tutte le anomalie sollevate durante il caricamento o parsing delle configurazioni.
sealed class ConfigException implements Exception {
  final String path;
  final String operation;
  final String message;
  final Object? cause;

  const ConfigException({
    required this.path,
    required this.operation,
    required this.message,
    this.cause,
  });

  @override
  String toString() =>
      '$runtimeType: $message [Path: $path, Operation: $operation, Cause: $cause]';
}

/// Eccezione lanciata in caso di errore di caricamento o I/O della sorgente (es. errori reali del file system).
final class ConfigSourceException extends ConfigException {
  const ConfigSourceException({
    required super.path,
    required super.operation,
    required super.message,
    super.cause,
  });
}

/// Eccezione lanciata in caso di JSON malformato o errore sintattico di parsing.
final class ConfigParseException extends ConfigException {
  const ConfigParseException({
    required super.path,
    required super.operation,
    required super.message,
    super.cause,
  });
}

/// Eccezione lanciata in caso di mapping strutturale non valido (strutture non corrispondenti o chiavi/tipi JSON errati).
final class ConfigMappingException extends ConfigException {
  const ConfigMappingException({
    required super.path,
    required super.operation,
    required super.message,
    super.cause,
  });
}
