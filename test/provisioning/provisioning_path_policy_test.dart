import 'package:aura_core/aura_core.dart';
import 'package:test/test.dart';

void main() {
  group('ProvisioningPathResolver Tests -', () {
    final resolver = ProvisioningPathResolver(
      appManagedRoot: r'C:\CustomApp\Local\AURA',
      bundledRoot: r'C:\Program Files\AURA',
    );

    test(
        'Risolve correttamente le directory ed i file di configurazione con root obbligatorie',
        () {
      expect(
        resolver.installationRecordPath,
        equals(r'C:\CustomApp\Local\AURA\installation_record.json'),
      );
      expect(
        resolver.activeStatePath,
        equals(r'C:\CustomApp\Local\AURA\active_state.json'),
      );
      expect(
        resolver.runtimesDirectory,
        equals(r'C:\CustomApp\Local\AURA\runtimes'),
      );
      expect(
        resolver.modelsDirectory,
        equals(r'C:\CustomApp\Local\AURA\models'),
      );
      expect(
        resolver.stagingDirectory,
        equals(r'C:\CustomApp\Local\AURA\staging'),
      );
      expect(
        resolver.cacheDirectory,
        equals(r'C:\CustomApp\Local\AURA\cache'),
      );
      expect(
        resolver.logsDirectory,
        equals(r'C:\CustomApp\Local\AURA\logs'),
      );
      expect(
        resolver.bundledRuntimeDirectory,
        equals(r'C:\Program Files\AURA\bundled_runtime'),
      );
    });

    test(
        'Valida ed impone che appManagedRoot e bundledRoot siano assolute e non coincidenti',
        () {
      expect(
        () => ProvisioningPathResolver(
          appManagedRoot: 'relative/path',
          bundledRoot: r'C:\Program Files\AURA',
        ),
        throwsA(isA<ProvisioningException>().having(
          (e) => e.reason,
          'reason',
          equals(ProvisioningFailureReason.invalidCatalog),
        )),
      );

      expect(
        () => ProvisioningPathResolver(
          appManagedRoot: r'C:\SameRoot\AURA',
          bundledRoot: r'C:\SameRoot\AURA',
        ),
        throwsA(isA<ProvisioningException>().having(
          (e) => e.reason,
          'reason',
          equals(ProvisioningFailureReason.invalidCatalog),
        )),
      );
    });

    test(
        'Normalizza le root e rileva coincidenze case-insensitive e con trailing slash',
        () {
      expect(
        () => ProvisioningPathResolver(
          appManagedRoot: r'C:\SameRoot\AURA\',
          bundledRoot: r'c:/sameroot/aura',
        ),
        throwsA(isA<ProvisioningException>().having(
          (e) => e.reason,
          'reason',
          equals(ProvisioningFailureReason.invalidCatalog),
        )),
      );

      final customResolver = ProvisioningPathResolver(
        appManagedRoot: r'C:/AppManaged/Aura/',
        bundledRoot: r'C:\Program Files\Aura\',
      );

      expect(customResolver.appManagedRoot, equals(r'C:\AppManaged\Aura'));
      expect(customResolver.bundledRoot, equals(r'C:\Program Files\Aura'));
    });

    test('Risolve path utilizzando CatalogArtifactType fortemente tipizzato',
        () {
      final relRt = resolver.resolveRelativeInstallPath(
        artifactType: CatalogArtifactType.runtime,
        artifactId: 'llama-b3500',
        buildOrVersionId: 'b3500',
      );
      expect(relRt, equals('runtimes/llama-b3500/b3500'));

      final absRt = resolver.resolveAbsoluteInstallPath(
        artifactType: CatalogArtifactType.runtime,
        artifactId: 'llama-b3500',
        buildOrVersionId: 'b3500',
      );
      expect(
          absRt, equals(r'C:\CustomApp\Local\AURA\runtimes\llama-b3500\b3500'));

      final relModel = resolver.resolveRelativeInstallPath(
        artifactType: CatalogArtifactType.model,
        artifactId: 'ministral-3b',
        buildOrVersionId: 'q4_k_m',
      );
      expect(relModel, equals('models/ministral-3b/q4_k_m'));

      final absModel = resolver.resolveAbsoluteInstallPath(
        artifactType: CatalogArtifactType.model,
        artifactId: 'ministral-3b',
        buildOrVersionId: 'q4_k_m',
      );
      expect(absModel,
          equals(r'C:\CustomApp\Local\AURA\models\ministral-3b\q4_k_m'));
    });

    test(
        'Rifiuta severamente separatori (/ e \\), traversal e nomi riservati senza alcuna mutazione silenziosa',
        () {
      expect(
        () => ProvisioningPathResolver.sanitizeSegment(r'subfolder\segment'),
        throwsA(isA<ProvisioningException>().having(
          (e) => e.reason,
          'reason',
          equals(ProvisioningFailureReason.invalidCatalog),
        )),
      );

      expect(
        () => ProvisioningPathResolver.sanitizeSegment('subfolder/segment'),
        throwsA(isA<ProvisioningException>().having(
          (e) => e.reason,
          'reason',
          equals(ProvisioningFailureReason.invalidCatalog),
        )),
      );

      expect(
        () => ProvisioningPathResolver.sanitizeSegment('../traversal'),
        throwsA(isA<ProvisioningException>().having(
          (e) => e.reason,
          'reason',
          equals(ProvisioningFailureReason.invalidCatalog),
        )),
      );

      expect(
        () => ProvisioningPathResolver.sanitizeSegment('CON'),
        throwsA(isA<ProvisioningException>().having(
          (e) => e.reason,
          'reason',
          equals(ProvisioningFailureReason.invalidCatalog),
        )),
      );

      expect(
        () => ProvisioningPathResolver.sanitizeSegment('segment_with_space '),
        throwsA(isA<ProvisioningException>().having(
          (e) => e.reason,
          'reason',
          equals(ProvisioningFailureReason.invalidCatalog),
        )),
      );

      final sanitized =
          ProvisioningPathResolver.sanitizeSegment('valid-segment_123');
      expect(sanitized, equals('valid-segment_123'));
    });
  });
}
