import 'dart:convert';
import 'dart:io';

import 'package:aura_core/aura_offline.dart';
import 'package:test/test.dart';

void main() {
  group(
      'Tranche 6.4f.8-lock-fix — CLI & FileBasedProvisioningLock Extended Tests',
      () {
    late Directory tempLockDir;
    setUp(() async {
      tempLockDir = await Directory.systemTemp.createTemp('aura_lock_test_');
    });

    tearDown(() async {
      if (await tempLockDir.exists()) {
        await tempLockDir.delete(recursive: true);
      }
    });

    group('AuraCliEnvironment Platform Resolution', () {
      test('risolve i percorsi Windows in modo corretto', () {
        final env = AuraCliEnvironment.fromPlatform(
          environment: {'APPDATA': r'C:\Users\TestUser\AppData\Roaming'},
          targetOS: AuraOperatingSystem.windows,
        );

        expect(env.appManagedRoot,
            equals(r'C:\Users\TestUser\AppData\Roaming\AURA\models'));
      });

      test('risolve i percorsi Linux (XDG Data Home)', () {
        final env = AuraCliEnvironment.fromPlatform(
          environment: {'XDG_DATA_HOME': '/home/testuser/.data'},
          targetOS: AuraOperatingSystem.linux,
        );

        expect(env.appManagedRoot, equals('/home/testuser/.data/aura/models'));
      });

      test('risolve i percorsi macOS (Application Support)', () {
        final env = AuraCliEnvironment.fromPlatform(
          environment: {'HOME': '/Users/testuser'},
          targetOS: AuraOperatingSystem.macOS,
        );

        expect(env.appManagedRoot,
            equals('/Users/testuser/Library/Application Support/AURA/models'));
      });
    });

    group('FileBasedProvisioningLock Multi-Instance & Exception Resilience',
        () {
      test(
          'serializza l\'accesso concorrente tra due istanze FileBasedProvisioningLock',
          () async {
        final lock1 = FileBasedProvisioningLock(
          lockDirectory: tempLockDir.path,
          acquisitionTimeout: const Duration(milliseconds: 100),
          retryInterval: const Duration(milliseconds: 20),
        );
        final lock2 = FileBasedProvisioningLock(
          lockDirectory: tempLockDir.path,
          acquisitionTimeout: const Duration(milliseconds: 100),
          retryInterval: const Duration(milliseconds: 20),
        );

        final executionOrder = <int>[];

        final future1 = lock1.synchronized('shared_key', () async {
          executionOrder.add(1);
          await Future.delayed(const Duration(milliseconds: 150));
          executionOrder.add(2);
        });

        // Breve delay per consentire a lock1 di acquisire il file lock
        await Future.delayed(const Duration(milliseconds: 20));

        final future2 = lock2.synchronized('shared_key', () async {
          executionOrder.add(3);
        });

        await Future.wait([future1, future2]);

        expect(executionOrder, equals([1, 2, 3]));
      });

      test(
          'rilascia il file lock se l\'azione solleva un\'eccezione imprevista',
          () async {
        final lock1 = FileBasedProvisioningLock(
          lockDirectory: tempLockDir.path,
          acquisitionTimeout: const Duration(milliseconds: 100),
          retryInterval: const Duration(milliseconds: 20),
        );
        final lock2 = FileBasedProvisioningLock(
          lockDirectory: tempLockDir.path,
          acquisitionTimeout: const Duration(milliseconds: 100),
          retryInterval: const Duration(milliseconds: 20),
        );

        await expectLater(
          lock1.synchronized('faulty_key', () async {
            throw Exception('Imprevisto nel lock');
          }),
          throwsA(isA<Exception>()),
        );

        // Verifica che lock2 riesca immediatamente ad acquisire il lock libero
        var lock2Acquired = false;
        await lock2.synchronized('faulty_key', () async {
          lock2Acquired = true;
        });

        expect(lock2Acquired, isTrue);
      });

      test('solleva ProvisioningException quando scade il maxWaitDuration',
          () async {
        final lock1 = FileBasedProvisioningLock(
          lockDirectory: tempLockDir.path,
          acquisitionTimeout: const Duration(milliseconds: 50),
          retryInterval: const Duration(milliseconds: 20),
          maxWaitDuration: const Duration(milliseconds: 500),
        );
        final lock2 = FileBasedProvisioningLock(
          lockDirectory: tempLockDir.path,
          acquisitionTimeout: const Duration(milliseconds: 50),
          retryInterval: const Duration(milliseconds: 20),
          maxWaitDuration: const Duration(milliseconds: 200),
        );

        final blocker = lock1.synchronized('block_key', () async {
          await Future.delayed(const Duration(milliseconds: 600));
        });

        await Future.delayed(const Duration(milliseconds: 30));

        await expectLater(
          lock2.synchronized('block_key', () async {
            return 'should_fail';
          }),
          throwsA(isA<ProvisioningException>()),
        );

        await blocker;
      });
    });

    group('Real Multi-Process Dart Integration Tests', () {
      test('sincronizza l\'accesso tra due processi Dart reali separati',
          () async {
        final workerScriptPath = r'test\bin\lock_process_worker.dart';
        if (!await File(workerScriptPath).exists()) {
          return;
        }

        final proc1 = await Process.start(
            'dart', [workerScriptPath, tempLockDir.path, '300']);
        final lines1 = <String>[];
        proc1.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(lines1.add);

        // Attende che il processo 1 abbia acquisito il lock
        await Future.delayed(const Duration(milliseconds: 150));

        final proc2 = await Process.start(
            'dart', [workerScriptPath, tempLockDir.path, '50']);
        final lines2 = <String>[];
        proc2.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(lines2.add);

        final code1 = await proc1.exitCode;
        final code2 = await proc2.exitCode;

        expect(code1, equals(0));
        expect(code2, equals(0));
        expect(lines1, contains('LOCKED'));
        expect(lines1, contains('UNLOCKED'));
        expect(lines2, contains('LOCKED'));
        expect(lines2, contains('UNLOCKED'));
      });
    });
  });
}
