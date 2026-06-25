import 'dart:io';

/// Abstrae la sorgente da cui vengono caricati i file di configurazione JSON.
/// Consente di implementare caricamenti asincroni (come gli Asset di Flutter)
/// e caricamenti sincroni (come il FileSystem in Dart nativo o CLI).
abstract class ConfigSource {
  /// Carica in modo asincrono la stringa di configurazione dal percorso specificato.
  Future<String?> loadString(String path);

  /// Carica in modo sincrono la stringa di configurazione dal percorso specificato.
  /// Può lanciare un [UnsupportedError] se la sorgente non supporta il caricamento sincrono.
  String? loadStringSync(String path);
}

/// Implementazione di [ConfigSource] che utilizza il file system locale (tramite `dart:io`).
class FileSystemConfigSource implements ConfigSource {
  const FileSystemConfigSource();

  @override
  Future<String?> loadString(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        return await file.readAsString();
      }
    } catch (_) {}
    return null;
  }

  @override
  String? loadStringSync(String path) {
    try {
      final file = File(path);
      if (file.existsSync()) {
        return file.readAsStringSync();
      }
    } catch (_) {}
    return null;
  }
}

/// Implementazione di [ConfigSource] che utilizza mappe in memoria preconfigurate.
/// Usata per fallback statici integrati nel codice o test.
class EmbeddedFallbackConfigSource implements ConfigSource {
  final Map<String, String> embeddedData;

  const EmbeddedFallbackConfigSource(this.embeddedData);

  @override
  Future<String?> loadString(String path) async {
    return loadStringSync(path);
  }

  @override
  String? loadStringSync(String path) {
    for (final entry in embeddedData.entries) {
      if (path.endsWith(entry.key)) {
        return entry.value;
      }
    }
    return null;
  }
}
