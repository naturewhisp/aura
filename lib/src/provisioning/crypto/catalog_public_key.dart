import 'dart:typed_data';
import 'package:meta/meta.dart';

/// Rappresentazione immutabile e tipizzata di una chiave pubblica di catalogo (es. ed25519-v1).
@immutable
final class CatalogPublicKey {
  final String keyId;
  final String algorithm;
  final Uint8List rawKeyBytes;

  CatalogPublicKey({
    required String keyId,
    required String algorithm,
    required Uint8List rawKeyBytes,
  })  : keyId = keyId.trim(),
        algorithm = algorithm.trim(),
        rawKeyBytes = Uint8List.fromList(rawKeyBytes) {
    if (this.keyId.isEmpty) {
      throw ArgumentError('keyId non può essere vuoto.');
    }
    if (this.algorithm.isEmpty) {
      throw ArgumentError('algorithm non può essere vuoto.');
    }
    if (this.algorithm == 'ed25519-v1' && this.rawKeyBytes.length != 32) {
      throw ArgumentError(
        'Per ed25519-v1 la chiave pubblica deve contenere esattamente 32 byte (ricevuti: ${this.rawKeyBytes.length}).',
      );
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! CatalogPublicKey) return false;
    if (keyId != other.keyId || algorithm != other.algorithm) return false;
    if (rawKeyBytes.length != other.rawKeyBytes.length) return false;
    for (var i = 0; i < rawKeyBytes.length; i++) {
      if (rawKeyBytes[i] != other.rawKeyBytes[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hash(keyId, algorithm, Object.hashAll(rawKeyBytes));

  @override
  String toString() =>
      'CatalogPublicKey(keyId: $keyId, algorithm: $algorithm, bytes: ${rawKeyBytes.length})';
}
