import 'package:flutter/services.dart';
import 'package:aura_core/aura_core.dart';

/// Implementazione di [ConfigSource] specifica per l'applicazione Flutter.
/// Carica i file JSON in modo asincrono dagli asset dell'applicazione tramite [rootBundle].
class FlutterAssetConfigSource implements ConfigSource {
  const FlutterAssetConfigSource();

  @override
  Future<String?> loadString(String path) async {
    try {
      return await rootBundle.loadString(path);
    } catch (_) {
      // Ritorna null in caso l'asset non esista o ci sia un errore
      return null;
    }
  }

  @override
  String? loadStringSync(String path) {
    throw UnsupportedError(
        'Il caricamento sincrono non è supportato da FlutterAssetConfigSource. '
        'Precarica i file all\'avvio utilizzando GameConfigLoader.preloadConfig(path).');
  }
}
