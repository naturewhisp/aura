import 'catalog_public_key.dart';

/// Contratto astratto del trust store contenente le chiavi pubbliche fidate del client.
abstract interface class CatalogTrustStore {
  /// Cerca ed ordina una chiave pubblica fidata per identificatore [keyId].
  /// Restituisce `null` se il [keyId] non è presente o non è fidato.
  Future<CatalogPublicKey?> findTrustedKey(String keyId);
}

/// Implementazione in-memory di [CatalogTrustStore] per testing, fixture e bootstrap.
final class InMemoryCatalogTrustStore implements CatalogTrustStore {
  final Map<String, CatalogPublicKey> _keys;

  InMemoryCatalogTrustStore(Map<String, CatalogPublicKey> keys)
      : _keys = Map.unmodifiable(keys);

  factory InMemoryCatalogTrustStore.fromKeys(List<CatalogPublicKey> keyList) {
    final map = <String, CatalogPublicKey>{};
    for (final k in keyList) {
      map[k.keyId] = k;
    }
    return InMemoryCatalogTrustStore(map);
  }

  @override
  Future<CatalogPublicKey?> findTrustedKey(String keyId) async {
    return _keys[keyId];
  }
}
