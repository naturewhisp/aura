import 'package:aura_core/aura_core.dart';
import 'package:test/test.dart';

void main() {
  group('ProvisioningPathResolver POSIX Semantics Tests -', () {
    const posixManagedRoot =
        '/Users/playtester/Library/Application Support/AURA';
    const posixBundledRoot =
        '/Applications/AURA.app/Contents/Resources/bundled';

    final resolver = ProvisioningPathResolver(
      appManagedRoot: posixManagedRoot,
      bundledRoot: posixBundledRoot,
    );

    test(
        'Identifica correttamente il contesto POSIX e adotta lo slash come separatore',
        () {
      expect(resolver.isPosix, isTrue);
      expect(resolver.separator, equals('/'));
      expect(resolver.appManagedRoot, equals(posixManagedRoot));
      expect(resolver.bundledRoot, equals(posixBundledRoot));
    });

    test('Risolve tutti i percorsi canonici con separatore POSIX', () {
      expect(
        resolver.installationRecordPath,
        equals('$posixManagedRoot/installation_record.json'),
      );
      expect(
        resolver.activeStatePath,
        equals('$posixManagedRoot/active_state.json'),
      );
      expect(
        resolver.runtimesDirectory,
        equals('$posixManagedRoot/runtimes'),
      );
      expect(
        resolver.modelsDirectory,
        equals('$posixManagedRoot/models'),
      );
      expect(
        resolver.stagingDirectory,
        equals('$posixManagedRoot/staging'),
      );
      expect(
        resolver.cacheDirectory,
        equals('$posixManagedRoot/cache'),
      );
      expect(
        resolver.logsDirectory,
        equals('$posixManagedRoot/logs'),
      );
      expect(
        resolver.bundledRuntimeDirectory,
        equals('$posixBundledRoot/bundled_runtime'),
      );
      expect(
        resolver.quarantineDirectory,
        equals('$posixManagedRoot/staging/quarantine'),
      );
      expect(
        resolver.stagingPartPath('op-123'),
        equals('$posixManagedRoot/staging/op-123.part'),
      );
      expect(
        resolver.stagingCheckpointPath('op-123'),
        equals('$posixManagedRoot/staging/op-123.checkpoint.json'),
      );
      expect(
        resolver.catalogCacheEnvelopePath,
        equals('$posixManagedRoot/cache/cached_catalog_envelope.json'),
      );
      expect(
        resolver.lkgCatalogMetadataPath,
        equals('$posixManagedRoot/cache/lkg_catalog_metadata.json'),
      );
    });

    test(
        'canonicalizeRoot normalizza percorsi Unix preservando il leading slash',
        () {
      expect(
        ProvisioningPathResolver.canonicalizeRoot('/Users/test//app/'),
        equals('/Users/test/app'),
      );
      expect(
        ProvisioningPathResolver.canonicalizeRoot('/Users/test/./app'),
        equals('/Users/test/app'),
      );
      expect(
        ProvisioningPathResolver.canonicalizeRoot('/'),
        equals('/'),
      );
      expect(
        () =>
            ProvisioningPathResolver.canonicalizeRoot('/Users/test/../escape'),
        throwsA(isA<ProvisioningException>().having(
          (e) => e.reason,
          'reason',
          equals(ProvisioningFailureReason.invalidCatalog),
        )),
      );
    });

    test('Rifiuta root POSIX coincidenti o non assolute', () {
      expect(
        () => ProvisioningPathResolver(
          appManagedRoot: 'Users/relative/path',
          bundledRoot: posixBundledRoot,
        ),
        throwsA(isA<ProvisioningException>()),
      );

      expect(
        () => ProvisioningPathResolver(
          appManagedRoot: '/Users/tester/aura',
          bundledRoot: '/users/tester/aura',
        ),
        throwsA(isA<ProvisioningException>().having(
          (e) => e.reason,
          'reason',
          equals(ProvisioningFailureReason.invalidCatalog),
        )),
      );
    });

    test(
        'Risolve percorsi di installazione e payload confinati sotto root POSIX',
        () {
      final absInstall = resolver.resolveAbsoluteInstallPath(
        artifactType: CatalogArtifactType.model,
        artifactId: 'gemma-4-12b',
        buildOrVersionId: 'q4_0',
      );
      expect(
        absInstall,
        equals('$posixManagedRoot/models/gemma-4-12b/q4_0'),
      );

      final relPath =
          resolver.resolveAppManagedRelativePath('models/gemma-4-12b/q4_0');
      expect(relPath, equals('$posixManagedRoot/models/gemma-4-12b/q4_0'));

      final entryPath = resolver.resolveEntryFilePath(
        relativeInstallPath: 'models/gemma-4-12b/q4_0',
        entryFileName: 'model.gguf',
      );
      expect(
        entryPath,
        equals('$posixManagedRoot/models/gemma-4-12b/q4_0/model.gguf'),
      );
    });

    test('Boundary check impedisce escape e traversal su root POSIX', () {
      expect(
        () => resolver.resolveAppManagedRelativePath('/etc/passwd'),
        throwsA(isA<ProvisioningException>()),
      );

      expect(
        () => resolver.resolveAppManagedRelativePath('../escape'),
        throwsA(isA<ProvisioningException>()),
      );

      expect(
        () => resolver.resolveEntryFilePath(
          relativeInstallPath: 'models/gemma-4-12b/q4_0',
          entryFileName: '../escape.gguf',
        ),
        throwsA(isA<ProvisioningException>()),
      );
    });
  });
}
