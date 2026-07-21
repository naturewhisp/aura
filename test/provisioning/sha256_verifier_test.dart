import 'dart:convert';
import 'package:aura_core/aura_core.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'installation_record_repository_test.dart';

void main() {
  group('Sha256Verifier Tests -', () {
    late MemoryProvisioningFileSystem fileSystem;
    late DefaultSha256Verifier verifier;

    setUp(() {
      fileSystem = MemoryProvisioningFileSystem();
      verifier = const DefaultSha256Verifier();
    });

    test('Calcola correttamente l hash SHA-256 di un file testuale', () async {
      const content = 'hello aura provisioning engine';
      const path = r'C:\AppManaged\Aura\test.txt';
      fileSystem.files[path] = content;

      final expectedHash =
          sha256.convert(utf8.encode(content)).toString().toLowerCase();

      final calculated = await verifier.calculateSha256(path, fileSystem);
      expect(calculated, equals(expectedHash));
    });

    test(
        'verifySha256 lancia ProvisioningException con hashMismatch se l hash non corrisponde',
        () async {
      const path = r'C:\AppManaged\Aura\test.txt';
      fileSystem.files[path] = 'hello world';

      expect(
        () => verifier.verifySha256(
          filePath: path,
          expectedSha256: '0' * 64,
          fileSystem: fileSystem,
        ),
        throwsA(isA<ProvisioningException>().having(
          (e) => e.reason,
          'reason',
          equals(ProvisioningFailureReason.hashMismatch),
        )),
      );
    });
  });
}
