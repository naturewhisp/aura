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
    final file = File(path);
    if (!await file.exists()) {
      if (await Directory(path).exists()) {
        throw FileSystemException('Is a directory', path);
      }
      return null;
    }
    return await file.readAsString();
  }

  @override
  String? loadStringSync(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      if (Directory(path).existsSync()) {
        throw FileSystemException('Is a directory', path);
      }
      return null;
    }
    return file.readAsStringSync();
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
