import 'dart:io';
import 'package:aura_core/aura_core.dart';
import 'package:test/test.dart';

void main() {
  group('FileSystemLock Tests -', () {
    late Directory tempAppRoot;
    late Directory tempBundledRoot;
    late ProvisioningPathResolver pathResolver;
    late FileSystemLock lock1;
    late FileSystemLock lock2;

    setUp(() async {
      tempAppRoot =
          await Directory.systemTemp.createTemp('aura_lock_test_app_');
      tempBundledRoot =
          await Directory.systemTemp.createTemp('aura_lock_test_bundled_');
      pathResolver = ProvisioningPathResolver(
        appManagedRoot: tempAppRoot.path,
        bundledRoot: tempBundledRoot.path,
      );
      lock1 = FileSystemLock(pathResolver: pathResolver);
      lock2 = FileSystemLock(pathResolver: pathResolver);
    });

    tearDown(() async {
      await lock1.release();
      await lock2.release();
      try {
        if (await tempAppRoot.exists()) {
          await tempAppRoot.delete(recursive: true);
        }
      } catch (_) {}
      try {
        if (await tempBundledRoot.exists()) {
          await tempBundledRoot.delete(recursive: true);
        }
      } catch (_) {}
    });

    test(
        'Acquisisce e rilascia correttamente il lock sul file provisioning.lock',
        () async {
      await lock1.acquire();
      final lockFile =
          File('${pathResolver.stagingDirectory}\\provisioning.lock');
      expect(await lockFile.exists(), isTrue);

      await lock1.release();
      expect(await lockFile.exists(), isFalse);
    });

    test(
        'Impedisce l acquisizione concorrente ed interrompe con installationConflict',
        () async {
      await lock1.acquire();

      expect(
        () => lock2.acquire(),
        throwsA(isA<ProvisioningException>().having(
          (e) => e.reason,
          'reason',
          equals(ProvisioningFailureReason.installationConflict),
        )),
      );

      await lock1.release();

      // Dopo il rilascio di lock1, lock2 può acquisire con successo
      expect(() => lock2.acquire(), returnsNormally);
    });

    test(
        'withLock esegue l azione protetta e rilascia il lock anche in caso di eccezione',
        () async {
      try {
        await lock1.withLock(() async {
          throw Exception('Boom inside lock');
        });
      } catch (_) {}

      // Verifica che il lock sia stato rilasciato e lock2 possa acquisire
      expect(() => lock2.acquire(), returnsNormally);
    });
  });
}
