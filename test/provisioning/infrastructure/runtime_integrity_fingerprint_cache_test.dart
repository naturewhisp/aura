import 'dart:convert';
import 'dart:io';

import 'package:aura_core/aura_offline.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

void main() {
  group('DefaultRuntimeBundleIntegrityVerifier - cache delle impronte', () {
    late Directory tempDir;
    late String runtimeRoot;
    late String cachePath;
    late RuntimeVariantDescriptor variant;
    final payload = utf8.encode('llama-server binario finto');

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('aura_integrity_cache_');
      final sep = Platform.pathSeparator;
      runtimeRoot = '${tempDir.path}${sep}runtime';
      cachePath = '${tempDir.path}${sep}fingerprints.json';
      await Directory('$runtimeRoot${sep}bin').create(recursive: true);
      await File('$runtimeRoot${sep}bin${sep}llama-server.exe')
          .writeAsBytes(payload);
      variant = RuntimeVariantDescriptor(
        id: 'win-x64-cpu-avx2',
        acceleration: RuntimeAcceleration.cpu,
        architecture: 'x64',
        requiredCpuFeatures: const ['avx2'],
        executable: 'bin/llama-server.exe',
        workingDirectory: 'bin',
        vendorDirectories: const [],
        files: [
          RuntimeFileEntry(
            path: 'bin/llama-server.exe',
            sizeBytes: payload.length,
            sha256: sha256.convert(payload).toString(),
          ),
        ],
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    DefaultRuntimeBundleIntegrityVerifier newVerifier() =>
        DefaultRuntimeBundleIntegrityVerifier(
          fileSystem: const LocalProvisioningFileSystem(),
          fingerprintCachePath: cachePath,
        );

    test('una verifica completa riuscita registra le impronte', () async {
      final result = await newVerifier()
          .verifyVariant(variant: variant, runtimeRootPath: runtimeRoot);

      expect(result.isValid, isTrue);
      final cache = jsonDecode(await File(cachePath).readAsString())
          as Map<String, dynamic>;
      expect(cache['schemaVersion'], 1);
      expect((cache['files'] as Map).length, 1);
    });

    test('un file modificato dopo la verifica viene ricontrollato e rifiutato',
        () async {
      await newVerifier()
          .verifyVariant(variant: variant, runtimeRootPath: runtimeRoot);

      // Stessa dimensione, contenuto diverso e data di modifica nuova.
      final exe = File(
          '$runtimeRoot${Platform.pathSeparator}bin${Platform.pathSeparator}llama-server.exe');
      final tampered = List<int>.from(payload)..[0] ^= 0xFF;
      await exe.writeAsBytes(tampered);
      await exe.setLastModified(DateTime.now().add(const Duration(hours: 1)));

      final result = await newVerifier()
          .verifyVariant(variant: variant, runtimeRootPath: runtimeRoot);

      expect(result.isValid, isFalse);
      expect(result.corruptedFiles, isNotEmpty);
    });

    test('una cache corrotta ricade sulla verifica completa', () async {
      await File(cachePath).writeAsString('{non è json');

      final result = await newVerifier()
          .verifyVariant(variant: variant, runtimeRootPath: runtimeRoot);

      expect(result.isValid, isTrue);
    });

    test(
        'manomissione con stessa dimensione e data: sfugge al controllo rapido, '
        'non al ricalcolo in background, e blocca il prossimo avvio', () async {
      final exe = File(
          '$runtimeRoot${Platform.pathSeparator}bin${Platform.pathSeparator}llama-server.exe');
      await newVerifier()
          .verifyVariant(variant: variant, runtimeRootPath: runtimeRoot);
      final modified = await exe.lastModified();
      await exe.writeAsBytes(List<int>.from(payload)..[0] ^= 0xFF);
      await exe.setLastModified(modified);

      final verifier = newVerifier();
      final quick = await verifier.verifyVariant(
          variant: variant, runtimeRootPath: runtimeRoot);
      expect(quick.isValid, isTrue);

      final deep = await verifier.reverifyTrustedVariants();
      expect(deep.single.isValid, isFalse);

      final nextStart = await newVerifier()
          .verifyVariant(variant: variant, runtimeRootPath: runtimeRoot);
      expect(nextStart.isValid, isFalse);
    });

    test('dopo una verifica completa non resta nulla da ricalcolare', () async {
      final verifier = newVerifier();
      await verifier.verifyVariant(
          variant: variant, runtimeRootPath: runtimeRoot);
      expect(await verifier.reverifyTrustedVariants(), isEmpty);
    });
  });
}
