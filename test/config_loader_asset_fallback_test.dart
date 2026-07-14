import 'package:test/test.dart';
import 'package:aura_core/aura_core.dart';

void main() {
  group('GameConfigLoader & ConfigSource Tests -', () {
    test('EmbeddedFallbackConfigSource loads embedded configuration', () {
      final embedded = EmbeddedFallbackConfigSource(
          {'test_config.json': '{"hello": "world"}'});

      expect(embedded.loadStringSync('test_config.json'),
          equals('{"hello": "world"}'));
    });

    test('GameConfigLoader preloads and falls back to default', () {
      // Usa embedded source
      final embedded = EmbeddedFallbackConfigSource({
        'panopticon_identity.json':
            '{"identity_id": "test_identity", "display_name": "TEST"}'
      });

      GameConfigLoader.setSource(embedded);

      // Caricamento con path custom caricato dall'embedded
      final idDef = GameConfigLoader.loadIdentityDefinition('test',
          customPath: 'panopticon_identity.json');
      expect(idDef.identityId, equals('test_identity'));
      expect(idDef.displayName, equals('TEST'));

      // Caricamento di un file non esistente -> deve caricare il fallback hardcoded predefinito
      final fallbackIdDef = GameConfigLoader.loadIdentityDefinition(
          'panopticon',
          customPath: 'unknown.json');
      expect(fallbackIdDef.identityId, equals('panopticon'));
      expect(fallbackIdDef.displayName, equals('PANOPTICON'));
    });

    test('preloadConfig caches async loads', () async {
      final source = EmbeddedFallbackConfigSource({
        'assets/config/panopticon_identity.json':
            '{"identity_id": "async_identity", "display_name": "ASYNC"}'
      });

      GameConfigLoader.setSource(source);
      await GameConfigLoader.preloadConfig(
          'assets/config/panopticon_identity.json');

      // Ora la lettura sincrona deve pescare dalla cache
      final idDef = GameConfigLoader.loadIdentityDefinition('async',
          customPath: 'assets/config/panopticon_identity.json');
      expect(idDef.identityId, equals('async_identity'));
      expect(idDef.displayName, equals('ASYNC'));
    });
  });
}
