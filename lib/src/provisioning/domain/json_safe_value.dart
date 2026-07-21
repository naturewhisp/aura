import 'provisioning_options.dart';

/// Utility condivisa per la validazione ricorsiva ed il congelamento (freezing) di grafi JSON-safe.
abstract final class JsonSafeValue {
  /// Valida e restituisce una copia unmodifiable ed immutabile della mappa.
  static Map<String, dynamic> ensureJsonSafeMap(Map<String, dynamic> map) {
    final result = <String, dynamic>{};
    for (final entry in map.entries) {
      final key = entry.key;
      validateJsonSafeValue(entry.value, path: key);
      result[key] = freezeJsonSafeValue(entry.value);
    }
    return Map.unmodifiable(result);
  }

  /// Valida che un valore sia strettamente conforme ai tipi JSON supportati.
  static void validateJsonSafeValue(Object? value, {required String path}) {
    if (value == null || value is bool || value is String) {
      return;
    }
    if (value is num) {
      if (value.isNaN || value.isInfinite) {
        throw ProvisioningException(
          reason: ProvisioningFailureReason.catalogMalformed,
          message:
              'Valore numerico non finito (NaN/Infinity) non ammesso al path "$path".',
        );
      }
      return;
    }
    if (value is List) {
      for (var i = 0; i < value.length; i++) {
        validateJsonSafeValue(value[i], path: '$path[$i]');
      }
      return;
    }
    if (value is Map) {
      for (final entry in value.entries) {
        if (entry.key is! String) {
          throw ProvisioningException(
            reason: ProvisioningFailureReason.catalogMalformed,
            message:
                'Chiave non stringa "${entry.key}" non ammessa al path "$path".',
          );
        }
        validateJsonSafeValue(entry.value, path: '$path.${entry.key}');
      }
      return;
    }
    throw ProvisioningException(
      reason: ProvisioningFailureReason.catalogMalformed,
      message:
          'Tipo di dato non JSON-safe "${value.runtimeType}" rilevato al path "$path".',
    );
  }

  /// Congela ricorsivamente una struttura dati tramite [List.unmodifiable] e [Map.unmodifiable].
  static Object? freezeJsonSafeValue(Object? value) {
    if (value is List) {
      return List.unmodifiable(value.map(freezeJsonSafeValue));
    }
    if (value is Map) {
      final copy = <String, dynamic>{};
      for (final entry in value.entries) {
        copy[entry.key as String] = freezeJsonSafeValue(entry.value);
      }
      return Map.unmodifiable(copy);
    }
    return value;
  }
}
