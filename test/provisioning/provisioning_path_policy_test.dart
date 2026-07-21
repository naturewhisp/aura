import 'package:aura_core/aura_core.dart';
import 'package:test/test.dart';

void main() {
  group('ProvisioningPathResolver Tests -', () {
    const resolver = ProvisioningPathResolver(
      appManagedRoot: r'C:\CustomApp\Local\AURA',
      bundledRoot: r'C:\Program Files\AURA',
    );

    test(
        'Risolve correttamente le directory ed i file di configurazione predefiniti',
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
        'Risolve path relativi e assoluti di installazione per runtime e modello',
        () {
      final relRt = resolver.resolveRelativeInstallPath(
        artifactType: 'runtime',
        artifactId: 'llama-b3500',
        buildOrVersionId: 'b3500',
      );
      expect(relRt, equals('runtimes/llama-b3500/b3500'));

      final absRt = resolver.resolveAbsoluteInstallPath(
        artifactType: 'runtime',
        artifactId: 'llama-b3500',
        buildOrVersionId: 'b3500',
      );
      expect(
          absRt, equals(r'C:\CustomApp\Local\AURA\runtimes\llama-b3500\b3500'));

      final relModel = resolver.resolveRelativeInstallPath(
        artifactType: 'model',
        artifactId: 'ministral-3b',
        buildOrVersionId: 'q4_k_m',
      );
      expect(relModel, equals('models/ministral-3b/q4_k_m'));

      final absModel = resolver.resolveAbsoluteInstallPath(
        artifactType: 'model',
        artifactId: 'ministral-3b',
        buildOrVersionId: 'q4_k_m',
      );
      expect(absModel,
          equals(r'C:\CustomApp\Local\AURA\models\ministral-3b\q4_k_m'));
    });

    test('Risolve il path di staging per una specifica operazione', () {
      final staging = resolver.resolveStagingDirectory('op-uuid-1234');
      expect(staging, equals(r'C:\CustomApp\Local\AURA\staging\op-uuid-1234'));
    });

    test('Sanitizza ed impedisce traversal o nomi riservati Windows', () {
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
        () => ProvisioningPathResolver.sanitizeSegment('NUL.txt'),
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
