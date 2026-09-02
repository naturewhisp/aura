import 'dart:convert';
import 'package:aura_core/aura_offline.dart';
import 'package:test/test.dart';
import 'provisioning_test_helpers.dart';

void main() {
  group('AppManagedStoreResolver — Discovery and Fail-Closed Store Migration',
      () {
    late MemoryProvisioningFileSystem fileSystem;
    late AppManagedStoreResolver resolver;

    setUp(() {
      fileSystem = MemoryProvisioningFileSystem();
      resolver = AppManagedStoreResolver(fileSystem: fileSystem);
    });

    test('1. Canonical present and valid: resolves to canonical store',
        () async {
      const canonical = r'C:\Users\TestUser\AppData\Local\AURA\store';
      const legacy = r'C:\Users\TestUser\AppData\Roaming\AURA\models';

      await fileSystem.writeStringRecoverably(
        '$canonical\\installation_record.json',
        jsonEncode({'schemaVersion': '1.0.0', 'installations': []}),
      );
      await fileSystem.writeStringRecoverably(
        '$legacy\\installation_record.json',
        jsonEncode({'schemaVersion': '1.0.0', 'installations': []}),
      );

      final candidates = AppManagedStoreCandidates(
        canonical: canonical,
        legacy: [legacy],
      );

      final effective =
          await resolver.resolveEffectiveStore(candidates: candidates);
      expect(effective, equals(canonical));
    });

    test('2. Canonical directory exists (fresh init): resolves to canonical',
        () async {
      const canonical = r'C:\Users\TestUser\AppData\Local\AURA\store';
      const legacy = r'C:\Users\TestUser\AppData\Roaming\AURA\models';

      // Simula directory esistente ma senza file installation_record.json
      await fileSystem.writeStringRecoverably(
        '$canonical\\.keep',
        '',
      );

      final candidates = AppManagedStoreCandidates(
        canonical: canonical,
        legacy: [legacy],
      );

      final effective =
          await resolver.resolveEffectiveStore(candidates: candidates);
      expect(effective, equals(canonical));
    });

    test(
        '3. Canonical absent + legacy valid: preserves existing installation by selecting legacy store',
        () async {
      const canonical = r'C:\Users\TestUser\AppData\Local\AURA\store';
      const legacy = r'C:\Users\TestUser\AppData\Roaming\AURA\models';

      await fileSystem.writeStringRecoverably(
        '$legacy\\installation_record.json',
        jsonEncode({
          'schemaVersion': '1.0.0',
          'installations': [
            {'artifactId': 'ministral-3b'}
          ]
        }),
      );

      final candidates = AppManagedStoreCandidates(
        canonical: canonical,
        legacy: [legacy],
      );

      final effective =
          await resolver.resolveEffectiveStore(candidates: candidates);
      expect(effective, equals(legacy));
    });

    test(
        '4. Canonical present but corrupted JSON: fail-closed throws FormatException (NO silent legacy fallback)',
        () async {
      const canonical = r'C:\Users\TestUser\AppData\Local\AURA\store';
      const legacy = r'C:\Users\TestUser\AppData\Roaming\AURA\models';

      // File canonico corrotto
      await fileSystem.writeStringRecoverably(
        '$canonical\\installation_record.json',
        '{ corrupted json !!!',
      );
      // Legacy presente e valido
      await fileSystem.writeStringRecoverably(
        '$legacy\\installation_record.json',
        jsonEncode({'schemaVersion': '1.0.0', 'installations': []}),
      );

      final candidates = AppManagedStoreCandidates(
        canonical: canonical,
        legacy: [legacy],
      );

      expect(
        () => resolver.resolveEffectiveStore(candidates: candidates),
        throwsA(isA<FormatException>()),
      );
    });

    test(
        '5. Canonical present but not a JSON Map: fail-closed throws FormatException',
        () async {
      const canonical = r'C:\Users\TestUser\AppData\Local\AURA\store';

      await fileSystem.writeStringRecoverably(
        '$canonical\\installation_record.json',
        jsonEncode(['not', 'a', 'map']),
      );

      final candidates = const AppManagedStoreCandidates(
        canonical: canonical,
      );

      expect(
        () => resolver.resolveEffectiveStore(candidates: candidates),
        throwsA(isA<FormatException>()),
      );
    });

    test('6. Neither present: returns canonical store for fresh creation',
        () async {
      const canonical = r'C:\Users\TestUser\AppData\Local\AURA\store';
      const legacy = r'C:\Users\TestUser\AppData\Roaming\AURA\models';

      final candidates = AppManagedStoreCandidates(
        canonical: canonical,
        legacy: [legacy],
      );

      final effective =
          await resolver.resolveEffectiveStore(candidates: candidates);
      expect(effective, equals(canonical));
    });
  });
}
