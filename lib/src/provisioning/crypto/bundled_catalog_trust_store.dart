import 'dart:typed_data';

import 'catalog_public_key.dart';
import 'catalog_trust_store.dart';

/// Trust store con le chiavi pubbliche Ed25519 fidate, versionare nel codice sorgente.
///
/// Ogni chiave registrata qui è considerata fidata dal client per la verifica
/// della firma crittografica dei cataloghi modelli scaricati.
///
/// **Aggiornamento chiavi:**
/// - Per aggiungere una nuova chiave (es. rotazione), aggiungerla a [_trustedKeys].
/// - Per revocare una chiave, rimuoverla dalla lista.
/// - Il [keyId] deve corrispondere a quello dichiarato nell'envelope firmato.
final class BundledCatalogTrustStore implements CatalogTrustStore {
  BundledCatalogTrustStore()
      : _inner = InMemoryCatalogTrustStore.fromKeys(_trustedKeys);

  final InMemoryCatalogTrustStore _inner;

  /// Chiavi pubbliche fidate, versionare nel codice sorgente.
  static final List<CatalogPublicKey> _trustedKeys = [
    // Chiave di development/release-candidate (generata 2026-08-04).
    CatalogPublicKey(
      keyId: 'aura-catalog-development-2026-01',
      algorithm: 'ed25519-v1',
      rawKeyBytes: _hexToBytes(
        '0112e7984ea2f973a3c5d7e2c9d7b504'
        'a76a8e031f93796756a719dbc8b745bf',
      ),
    ),
  ];

  @override
  Future<CatalogPublicKey?> findTrustedKey(String keyId) =>
      _inner.findTrustedKey(keyId);

  /// Converte una stringa esadecimale in [Uint8List].
  static Uint8List _hexToBytes(String hex) {
    final clean = hex.replaceAll(RegExp(r'\s+'), '');
    return Uint8List.fromList(
      List.generate(
        clean.length ~/ 2,
        (i) => int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16),
      ),
    );
  }
}
