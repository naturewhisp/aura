import 'dart:convert';
import 'dart:typed_data';
import 'package:aura_core/aura_offline.dart';
import 'package:test/test.dart';
import '../provisioning_test_helpers.dart';

void main() {
  group('JsonCatalogCacheRepository Tests', () {
    late MemoryProvisioningFileSystem fileSystem;
    late ProvisioningPathResolver pathResolver;
    late InMemoryProvisioningLock lock;
    late JsonCatalogCacheRepository repository;

    late CatalogEnvelope testEnvelope;

    setUp(() {
      fileSystem = MemoryProvisioningFileSystem();
      pathResolver = ProvisioningPathResolver(
        appManagedRoot: r'C:\AURA\app_managed',
        bundledRoot: r'C:\AURA\bundled',
      );
      lock = InMemoryProvisioningLock();
      repository = JsonCatalogCacheRepository(
        pathResolver: pathResolver,
        lock: lock,
        fileSystem: fileSystem,
      );

      final manifest = CatalogManifest.initialDefault();
      final signedPayload = CatalogSignedPayload(
        schemaVersion: '1.0',
        signatureAlgorithm: 'ed25519-v1',
        keyId: 'aura-release-key-2026-01',
        catalogId: manifest.catalogId,
        catalogVersion: manifest.schemaVersion,
        catalogRevision: 42,
        issuedAt: '2026-07-22T21:30:00Z',
        expiresAt: '2026-08-22T21:30:00Z',
        manifest: manifest,
      );
      final dummySig = base64.encode(Uint8List(64));
      testEnvelope = CatalogEnvelope(
        signedPayload: signedPayload,
        signature: dummySig,
      );
    });

    test('Legge null se la cache non esiste ancora', () async {
      final envelope = await repository.readEnvelope();
      expect(envelope, isNull);
    });

    test('Scrive ed in seguito legge l envelope in modo integro ed atomico',
        () async {
      await repository.writeEnvelope(testEnvelope);

      final read = await repository.readEnvelope();
      expect(read, isNotNull);
      expect(read!.signedPayload.catalogId,
          equals(testEnvelope.signedPayload.catalogId));
      expect(read.signedPayload.catalogRevision, equals(42));
      expect(read.signature, equals(testEnvelope.signature));
    });

    test(
        'Crea un backup .bak al secondo salvataggio e recupera dal backup se il file primario e corrotto',
        () async {
      // 1. Primo salvataggio
      await repository.writeEnvelope(testEnvelope);

      // 2. Secondo salvataggio con revisione 43 (crea .bak con la rev 42)
      final updatedPayload = CatalogSignedPayload(
        schemaVersion: '1.0',
        signatureAlgorithm: 'ed25519-v1',
        keyId: 'aura-release-key-2026-01',
        catalogId: testEnvelope.signedPayload.catalogId,
        catalogVersion: '1.2.1',
        catalogRevision: 43,
        issuedAt: '2026-07-22T22:00:00Z',
        expiresAt: '2026-08-22T22:00:00Z',
        manifest: testEnvelope.signedPayload.manifest,
      );
      final updatedEnvelope = CatalogEnvelope(
        signedPayload: updatedPayload,
        signature: testEnvelope.signature,
      );

      await repository.writeEnvelope(updatedEnvelope);

      // 3. Corruzione deliberata del file primario su disco
      final cachePath = pathResolver.catalogCacheEnvelopePath;
      await fileSystem.writeAsString(cachePath, '{ CORRUPTED_JSON }');

      // 4. Lettura: deve effettuare il recovery dal file .bak (rev 42) senza crashare
      final readRecovered = await repository.readEnvelope();
      expect(readRecovered, isNotNull);
      expect(readRecovered!.signedPayload.catalogRevision, equals(42));
    });

    test('clearCache cancella sia il file primario sia il file di backup .bak',
        () async {
      await repository.writeEnvelope(testEnvelope);
      // Forza scrittura .bak al secondo save
      await repository.writeEnvelope(testEnvelope);

      final cachePath = pathResolver.catalogCacheEnvelopePath;
      final backupPath = '$cachePath.bak';

      expect(await fileSystem.fileExists(cachePath), isTrue);
      expect(await fileSystem.fileExists(backupPath), isTrue);

      await repository.clearCache();

      expect(await fileSystem.fileExists(cachePath), isFalse);
      expect(await fileSystem.fileExists(backupPath), isFalse);
      expect(await repository.readEnvelope(), isNull);
    });
  });
}
