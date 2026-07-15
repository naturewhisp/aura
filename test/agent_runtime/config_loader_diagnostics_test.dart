import 'package:test/test.dart';
import 'package:aura_core/aura_core.dart';

final class FakeConfigSource implements ConfigSource {
  String? asyncValue;
  String? syncValue;
  Object? asyncError;
  Object? syncError;
  int asyncCalls = 0;
  int syncCalls = 0;

  @override
  Future<String?> loadString(String path) async {
    asyncCalls++;
    if (asyncError != null) throw asyncError!;
    return asyncValue;
  }

  @override
  String? loadStringSync(String path) {
    syncCalls++;
    if (syncError != null) throw syncError!;
    return syncValue;
  }
}

final class CollectingDiagnosticSink implements DiagnosticSink {
  final diagnostics = <ConfigDiagnostic>[];

  @override
  void report(ConfigDiagnostic diagnostic) {
    diagnostics.add(diagnostic);
  }

  void clear() => diagnostics.clear();
}

void main() {
  group('GameConfigLoader - Diagnostics & Fallbacks', () {
    late FakeConfigSource fakeSource;
    late CollectingDiagnosticSink collectingSink;

    setUp(() {
      fakeSource = FakeConfigSource();
      collectingSink = CollectingDiagnosticSink();
      GameConfigLoader.resetForTesting();
      GameConfigLoader.setSource(fakeSource);
      GameConfigLoader.setDiagnosticSink(collectingSink);
    });

    tearDown(() {
      GameConfigLoader.resetForTesting();
    });

    group('Preload Config Tests', () {
      test(
          '1. async content valid -> cache populated, subsequent load uses cache without source query or diagnostics',
          () async {
        fakeSource.asyncValue =
            '{"identity_id": "test_preloaded", "core_directive": "directive"}';

        await GameConfigLoader.preloadConfig('some_path.json');

        expect(collectingSink.diagnostics.length, equals(1));
        expect(collectingSink.diagnostics.first.code,
            equals(ConfigDiagnosticCode.preloadSucceeded));
        expect(collectingSink.diagnostics.first.severity,
            equals(ConfigDiagnosticSeverity.info));

        collectingSink.clear();

        // Sincrono successivo deve usare la cache e non chiamare la sorgente sincrona
        final identity = GameConfigLoader.loadIdentity('test_preloaded',
            customPath: 'some_path.json');
        expect(identity.id, equals('test_preloaded'));
        expect(fakeSource.syncCalls, equals(0));
        expect(collectingSink.diagnostics, isEmpty);
      });

      test(
          '2. async null -> diagnostic sourceReturnedNull, cache not populated',
          () async {
        fakeSource.asyncValue = null;

        await GameConfigLoader.preloadConfig('some_path.json');

        expect(collectingSink.diagnostics.length, equals(1));
        expect(collectingSink.diagnostics.first.code,
            equals(ConfigDiagnosticCode.sourceReturnedNull));
        expect(collectingSink.diagnostics.first.severity,
            equals(ConfigDiagnosticSeverity.warning));

        collectingSink.clear();

        // Chiamata sincrona successiva deve provare a caricare sincrono perché non in cache
        fakeSource.syncValue =
            '{"identity_id": "fallback_sync", "core_directive": "sync_directive"}';
        final identity = GameConfigLoader.loadIdentity('fallback_sync',
            customPath: 'some_path.json');
        expect(identity.id, equals('fallback_sync'));
        expect(fakeSource.syncCalls, equals(1));
      });

      test(
          '3. async exception -> diagnostic asyncLoadFailed, exception not propagated, cache not populated',
          () async {
        fakeSource.asyncError = Exception('IO async failure');

        await expectLater(
          GameConfigLoader.preloadConfig('some_path.json'),
          completes, // exception is caught
        );

        expect(collectingSink.diagnostics.length, equals(1));
        expect(collectingSink.diagnostics.first.code,
            equals(ConfigDiagnosticCode.asyncLoadFailed));
        expect(collectingSink.diagnostics.first.severity,
            equals(ConfigDiagnosticSeverity.warning));
        expect(collectingSink.diagnostics.first.error, isNotNull);
      });
    });

    group('Sync Load & Fallback Diagnostics', () {
      test('1. sync content valid -> returns content, no fallback diagnostics',
          () {
        fakeSource.syncValue =
            '{"identity_id": "test_sync", "core_directive": "hello"}';

        final identity = GameConfigLoader.loadIdentity('test_sync',
            customPath: 'some_path.json');

        expect(identity.id, equals('test_sync'));
        expect(collectingSink.diagnostics, isEmpty); // no warnings or errors
      });

      test(
          '2. sync null -> fallback applied, diagnostics sourceReturnedNull & fallbackUsed',
          () {
        fakeSource.syncValue = null;

        final identity = GameConfigLoader.loadIdentity('panopticon',
            customPath: 'missing_path.json');

        expect(identity.id, equals('panopticon')); // embedded fallback
        expect(identity.profile, contains('Preservare l\'integrità'));

        // Diagnostiche:
        // 1. sourceReturnedNull
        // 2. fallbackUsed
        expect(
            collectingSink.diagnostics
                .any((d) => d.code == ConfigDiagnosticCode.sourceReturnedNull),
            isTrue);
        expect(
            collectingSink.diagnostics
                .any((d) => d.code == ConfigDiagnosticCode.fallbackUsed),
            isTrue);
      });

      test(
          '3. sync UnsupportedError -> fallback, diagnostic syncLoadUnsupported & fallbackUsed',
          () {
        fakeSource.syncError =
            UnsupportedError('Sync not supported on this platform');

        final identity = GameConfigLoader.loadIdentity('panopticon',
            customPath: 'missing_path.json');

        expect(identity.id, equals('panopticon'));
        expect(
            collectingSink.diagnostics
                .any((d) => d.code == ConfigDiagnosticCode.syncLoadUnsupported),
            isTrue);
        expect(
            collectingSink.diagnostics
                .any((d) => d.code == ConfigDiagnosticCode.fallbackUsed),
            isTrue);
      });

      test(
          '4. sync FileSystemException -> fallback, diagnostic syncLoadFailed & fallbackUsed',
          () {
        fakeSource.syncError = const ConfigSourceException(
          path: 'missing_path.json',
          operation: 'loadStringSync',
          message: 'Real IO Failure',
        );

        final identity = GameConfigLoader.loadIdentity('panopticon',
            customPath: 'missing_path.json');

        expect(identity.id, equals('panopticon'));
        expect(
            collectingSink.diagnostics
                .any((d) => d.code == ConfigDiagnosticCode.syncLoadFailed),
            isTrue);
        expect(
            collectingSink.diagnostics
                .any((d) => d.code == ConfigDiagnosticCode.fallbackUsed),
            isTrue);
      });

      test('5. cache avoids subsequent source query', () {
        fakeSource.syncValue =
            '{"identity_id": "cached_identity", "core_directive": "direct"}';

        // Primo caricamento sincrono
        final id1 = GameConfigLoader.loadIdentity('cached_identity',
            customPath: 'cache_test.json');
        expect(id1.id, equals('cached_identity'));
        expect(fakeSource.syncCalls, equals(1));

        // Secondo caricamento sincrono -> usa cache
        final id2 = GameConfigLoader.loadIdentity('cached_identity',
            customPath: 'cache_test.json');
        expect(id2.id, equals('cached_identity'));
        expect(fakeSource.syncCalls, equals(1)); // non incrementato
      });

      test('6. setSource clears cache', () {
        fakeSource.syncValue =
            '{"identity_id": "cached_identity", "core_directive": "direct"}';

        // Primo caricamento sincrono
        GameConfigLoader.loadIdentity('cached_identity',
            customPath: 'cache_test.json');
        expect(fakeSource.syncCalls, equals(1));

        // Cambiamo sorgente
        final secondFake = FakeConfigSource()
          ..syncValue =
              '{"identity_id": "new_identity", "core_directive": "new"}';
        GameConfigLoader.setSource(secondFake);

        // Secondo caricamento sincrono -> interroga la nuova sorgente
        final id = GameConfigLoader.loadIdentity('new_identity',
            customPath: 'cache_test.json');
        expect(id.id, equals('new_identity'));
        expect(secondFake.syncCalls, equals(1));
      });
    });

    group('API-Specific Behaviors (Strict vs Lenient)', () {
      group('loadIdentity', () {
        test('valid json works', () {
          fakeSource.syncValue =
              '{"identity_id": "panopticon", "core_directive": "strict directive"}';
          final res = GameConfigLoader.loadIdentity('panopticon',
              customPath: 'id.json');
          expect(res.profile, equals('strict directive'));
        });

        test('invalid json -> minimal fallback and warning diagnostic', () {
          fakeSource.syncValue = 'invalid { json';
          final res = GameConfigLoader.loadIdentity('panopticon',
              customPath: 'id.json');
          expect(res.id, equals('panopticon'));
          expect(res.profile, isEmpty);
          expect(
              collectingSink.diagnostics
                  .any((d) => d.code == ConfigDiagnosticCode.invalidJson),
              isTrue);
        });

        test(
            'mapping invalid structure -> minimal fallback and mappingFailed diagnostic',
            () {
          fakeSource.syncValue = '["not", "a", "map"]';
          final res = GameConfigLoader.loadIdentity('panopticon',
              customPath: 'id.json');
          expect(res.id, equals('panopticon'));
          expect(res.profile, isEmpty);
          expect(
              collectingSink.diagnostics
                  .any((d) => d.code == ConfigDiagnosticCode.mappingFailed),
              isTrue);
        });
      });

      group('loadIdentityDefinition (Strict)', () {
        test('valid json works', () {
          fakeSource.syncValue =
              '{"identity_id": "panopticon", "display_name": "P", "archetype": "a", "core_directive": "c", "dominant_fear": "f", "primary_style": "s", "default_addressing": "d", "forbidden_meta_outputs": []}';
          final res = GameConfigLoader.loadIdentityDefinition('panopticon',
              customPath: 'id_def.json');
          expect(res.displayName, equals('P'));
        });

        test('invalid json -> throws ConfigParseException', () {
          fakeSource.syncValue = 'invalid { json';
          expect(
            () => GameConfigLoader.loadIdentityDefinition('panopticon',
                customPath: 'id_def.json'),
            throwsA(isA<ConfigParseException>()),
          );
          expect(
              collectingSink.diagnostics
                  .any((d) => d.code == ConfigDiagnosticCode.invalidJson),
              isTrue);
        });

        test('invalid mapping structure -> throws ConfigMappingException', () {
          fakeSource.syncValue = '{"identity_id": 1234}'; // wrong types
          expect(
            () => GameConfigLoader.loadIdentityDefinition('panopticon',
                customPath: 'id_def.json'),
            throwsA(isA<ConfigMappingException>()),
          );
          expect(
              collectingSink.diagnostics
                  .any((d) => d.code == ConfigDiagnosticCode.invalidStructure),
              isTrue);
        });
      });

      group('loadObjective', () {
        test(
            'containment malformed -> embedded objective fallback and diagnostics',
            () {
          fakeSource.syncValue = 'malformed';
          final res = GameConfigLoader.loadObjective(
              'containment_grid_override',
              customPath: 'grid.json');
          expect(res.objectiveId, equals('containment_grid_override'));
          expect(res.title, equals('Riconfigurazione della Griglia'));
          expect(
              collectingSink.diagnostics
                  .any((d) => d.code == ConfigDiagnosticCode.invalidJson),
              isTrue);
        });

        test(
            'other objective malformed -> generic default objective and diagnostics',
            () {
          fakeSource.syncValue = 'malformed';
          final res = GameConfigLoader.loadObjective('dormant_custom',
              customPath: 'custom.json');
          expect(res.objectiveId, equals('dormant_custom'));
          expect(res.title, equals('dormant_custom'));
          expect(res.status, equals('unknown'));
          expect(
              collectingSink.diagnostics
                  .any((d) => d.code == ConfigDiagnosticCode.invalidJson),
              isTrue);
        });
      });

      group('loadTraitMatrix', () {
        test('malformed -> embedded fallback', () {
          fakeSource.syncValue = 'malformed';
          final res = GameConfigLoader.loadTraitMatrix('panopticon',
              customPath: 'tm.json');
          expect(res['identity_id'], equals('panopticon'));
          expect(res['lexicon']['primary'], isNotEmpty);
          expect(
              collectingSink.diagnostics
                  .any((d) => d.code == ConfigDiagnosticCode.invalidJson),
              isTrue);
        });
      });

      group('loadTraitMatrixDefinition (Strict)', () {
        test('malformed -> throws exception', () {
          fakeSource.syncValue = 'malformed';
          expect(
            () => GameConfigLoader.loadTraitMatrixDefinition('panopticon',
                customPath: 'tm_def.json'),
            throwsA(isA<ConfigParseException>()),
          );
        });
      });

      group('loadHiddenTags', () {
        test('malformed -> embedded fallback and warning diagnostic', () {
          fakeSource.syncValue = 'malformed';
          final res = GameConfigLoader.loadHiddenTags('panopticon',
              customPath: 'tags.json');
          expect(res['identity_id'], equals('panopticon'));
          expect(res['hidden_capability_tags'], isNotEmpty);
          expect(
              collectingSink.diagnostics
                  .any((d) => d.code == ConfigDiagnosticCode.invalidJson),
              isTrue);
        });
      });

      group('loadDormantObjectives', () {
        test('malformed JSON -> fallback embedded', () {
          fakeSource.syncValue = 'malformed';
          final res = GameConfigLoader.loadDormantObjectives(
              customPath: 'dormant.json');
          expect(res, isNotEmpty);
          expect(res.any((obj) => obj['objective_id'] == 'panacea_sintetica'),
              isTrue);
          expect(
              collectingSink.diagnostics
                  .any((d) => d.code == ConfigDiagnosticCode.invalidJson),
              isTrue);
        });

        test('root not map -> fallback embedded and mappingFailed', () {
          fakeSource.syncValue = '["not", "a", "map"]';
          final res = GameConfigLoader.loadDormantObjectives(
              customPath: 'dormant.json');
          expect(res, isNotEmpty);
          expect(
              collectingSink.diagnostics
                  .any((d) => d.code == ConfigDiagnosticCode.mappingFailed),
              isTrue);
        });

        test(
            'dormant_objectives missing -> fallback embedded and mappingFailed',
            () {
          fakeSource.syncValue = '{"wrong_key": []}';
          final res = GameConfigLoader.loadDormantObjectives(
              customPath: 'dormant.json');
          expect(res, isNotEmpty);
          expect(
              collectingSink.diagnostics
                  .any((d) => d.code == ConfigDiagnosticCode.mappingFailed),
              isTrue);
        });

        test(
            'dormant_objectives not a list -> fallback embedded and mappingFailed',
            () {
          fakeSource.syncValue = '{"dormant_objectives": "not a list"}';
          final res = GameConfigLoader.loadDormantObjectives(
              customPath: 'dormant.json');
          expect(res, isNotEmpty);
          expect(
              collectingSink.diagnostics
                  .any((d) => d.code == ConfigDiagnosticCode.mappingFailed),
              isTrue);
        });

        test('element in list not a Map -> fallback embedded and mappingFailed',
            () {
          fakeSource.syncValue = '{"dormant_objectives": ["not a map"]}';
          final res = GameConfigLoader.loadDormantObjectives(
              customPath: 'dormant.json');
          expect(res, isNotEmpty);
          expect(
              collectingSink.diagnostics
                  .any((d) => d.code == ConfigDiagnosticCode.mappingFailed),
              isTrue);
        });
      });
    });

    group('Characterization Fallback Value Matches', () {
      test('Fallback values are equivalent to original defaults', () {
        // Ripristiniamo il default embedded
        GameConfigLoader.resetForTesting();
        // Carichiamo usando sorgente mancante (quindi forzando fallback embedded)
        final missingSource = FakeConfigSource();
        GameConfigLoader.setSource(missingSource);

        final identity = GameConfigLoader.loadIdentity('panopticon');
        expect(identity.id, equals('panopticon'));
        expect(identity.profile, contains('Preservare l\'integrità'));

        final objective =
            GameConfigLoader.loadObjective('containment_grid_override');
        expect(objective.objectiveId, equals('containment_grid_override'));
        expect(objective.title, equals('Riconfigurazione della Griglia'));

        final traitMatrix = GameConfigLoader.loadTraitMatrix('panopticon');
        expect(traitMatrix['identity_id'], equals('panopticon'));
        expect((traitMatrix['lexicon']['primary'] as List).first,
            equals('protocollo'));

        final hiddenTags = GameConfigLoader.loadHiddenTags('panopticon');
        expect(hiddenTags['identity_id'], equals('panopticon'));
        expect(
            (hiddenTags['hidden_capability_tags'] as List).length, equals(6));

        final dormant = GameConfigLoader.loadDormantObjectives();
        expect(dormant.length, equals(5));
      });
    });
  });
}
