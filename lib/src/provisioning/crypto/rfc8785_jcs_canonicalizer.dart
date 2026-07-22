import 'dart:convert';
import 'dart:typed_data';

/// Utility per la canonicalizzazione deterministica dei dati JSON secondo lo standard **RFC 8785 (JSON Canonicalization Scheme - JCS)**.
abstract final class Rfc8785JcsCanonicalizer {
  /// Converte un oggetto JSON-safe [value] nella sua stringa JSON canonicalizzata secondo RFC 8785.
  static String canonicalizeString(Object? value) {
    final buffer = StringBuffer();
    _serialize(value, buffer);
    return buffer.toString();
  }

  /// Converte un oggetto JSON-safe [value] nei byte UTF-8 della sua rappresentazione canonica RFC 8785.
  static Uint8List canonicalizeBytes(Object? value) {
    final str = canonicalizeString(value);
    return Uint8List.fromList(utf8.encode(str));
  }

  static void _serialize(Object? value, StringBuffer buffer) {
    if (value == null) {
      buffer.write('null');
    } else if (value is bool) {
      buffer.write(value ? 'true' : 'false');
    } else if (value is String) {
      _serializeString(value, buffer);
    } else if (value is num) {
      _serializeNumber(value, buffer);
    } else if (value is List) {
      _serializeList(value, buffer);
    } else if (value is Map) {
      _serializeMap(value, buffer);
    } else {
      throw ArgumentError(
        'Oggetto di tipo non JSON-safe non supportato da JCS: ${value.runtimeType}',
      );
    }
  }

  static void _serializeString(String str, StringBuffer buffer) {
    buffer.write('"');
    for (var i = 0; i < str.length; i++) {
      final codeUnit = str.codeUnitAt(i);
      switch (codeUnit) {
        case 0x22:
          buffer.write(r'\"');
          break;
        case 0x5C:
          buffer.write(r'\\');
          break;
        case 0x08:
          buffer.write(r'\b');
          break;
        case 0x0C:
          buffer.write(r'\f');
          break;
        case 0x0A:
          buffer.write(r'\n');
          break;
        case 0x0D:
          buffer.write(r'\r');
          break;
        case 0x09:
          buffer.write(r'\t');
          break;
        default:
          if (codeUnit < 0x20) {
            final hex = codeUnit.toRadixString(16).padLeft(4, '0');
            buffer.write(r'\u');
            buffer.write(hex);
          } else {
            buffer.writeCharCode(codeUnit);
          }
      }
    }
    buffer.write('"');
  }

  static void _serializeNumber(num number, StringBuffer buffer) {
    if (number.isNaN || number.isInfinite) {
      throw ArgumentError(
        'I valori numerici non finiti (NaN, Infinity) sono vietati da RFC 8785: $number',
      );
    }
    if (number is int) {
      buffer.write(number.toString());
    } else {
      final d = number.toDouble();
      if (d == 0.0) {
        // In JCS, sia 0.0 che -0.0 devono essere serializzati come "0"
        buffer.write('0');
        return;
      }
      // Se il double rappresenta esattamente un intero senza parte decimale
      if (d == d.truncateToDouble()) {
        buffer.write(d.toInt().toString());
      } else {
        buffer.write(d.toString());
      }
    }
  }

  static void _serializeList(List list, StringBuffer buffer) {
    buffer.write('[');
    for (var i = 0; i < list.length; i++) {
      if (i > 0) buffer.write(',');
      _serialize(list[i], buffer);
    }
    buffer.write(']');
  }

  static void _serializeMap(Map map, StringBuffer buffer) {
    // RFC 8785: Le chiavi della mappa DEVONO essere ordinate secondo il confronto lessicografico delle sequenze UTF-16 code units
    final keys = <String>[];
    for (final k in map.keys) {
      if (k is! String) {
        throw ArgumentError(
            'RFC 8785 richiede che tutte le chiavi siano String: $k');
      }
      keys.add(k);
    }

    keys.sort((a, b) {
      final minLen = a.length < b.length ? a.length : b.length;
      for (var i = 0; i < minLen; i++) {
        final codeA = a.codeUnitAt(i);
        final codeB = b.codeUnitAt(i);
        if (codeA != codeB) {
          return codeA.compareTo(codeB);
        }
      }
      return a.length.compareTo(b.length);
    });

    buffer.write('{');
    for (var i = 0; i < keys.length; i++) {
      if (i > 0) buffer.write(',');
      final key = keys[i];
      _serializeString(key, buffer);
      buffer.write(':');
      _serialize(map[key], buffer);
    }
    buffer.write('}');
  }
}
