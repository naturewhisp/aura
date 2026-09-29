import 'dart:io';

import 'package:aura_core/aura_offline.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late ProvisioningPathResolver pathResolver;
  late ProcessOwnershipRegistry registry;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('aura_ownership_test_');
    pathResolver = ProvisioningPathResolver(
      appManagedRoot: tempDir.path,
      bundledRoot: '${tempDir.path}${Platform.pathSeparator}bundled',
    );
    registry = ProcessOwnershipRegistry(
      pathResolver: pathResolver,
      lock: InMemoryProvisioningLock(),
      processChecker: (rec) async => rec.pid == 7777,
      processTerminator: (pid) async => true,
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('ProcessOwnershipRecord & Registry Tests', () {
    test(
        'ProcessOwnershipRecord serializza e deserializza in JSON correttamente',
        () {
      final record = ProcessOwnershipRecord(
        schemaVersion: 1,
        pid: 12345,
        role: 'actor',
        ownerInstanceId: 'inst-1',
        parentPid: 6789,
        executablePathHash:
            ProcessOwnershipRecord.hashPath(r'C:\Tools\llama-server.exe'),
        modelPathHash: ProcessOwnershipRecord.hashPath(r'C:\Models\model.gguf'),
        modelAlias: 'aura.actor.primary',
        port: 30201,
        startedAt: DateTime.parse('2026-07-29T20:00:00Z'),
        state: 'ready',
      );

      final json = record.toJson();
      expect(json['schemaVersion'], equals(1));
      expect(json['pid'], equals(12345));
      expect(json['role'], equals('actor'));
      expect(json['port'], equals(30201));

      final restored = ProcessOwnershipRecord.fromJson(json);
      expect(restored.pid, equals(record.pid));
      expect(restored.role, equals(record.role));
      expect(restored.executablePathHash, equals(record.executablePathHash));
      expect(restored.startedAt, equals(record.startedAt));
    });

    test(
        'registerRecord scrive atomicamente e getRecord/listRecords leggono i dati',
        () async {
      final record = ProcessOwnershipRecord(
        schemaVersion: 1,
        pid: 9999,
        role: 'actor',
        ownerInstanceId: 'inst-test',
        parentPid: 1000,
        executablePathHash: 'hash-exec',
        modelPathHash: 'hash-model',
        modelAlias: 'aura.actor.primary',
        port: 30201,
        startedAt: DateTime.now(),
        state: 'ready',
      );

      await registry.registerRecord(record);

      final fetched = await registry.getRecord('actor');
      expect(fetched, isNotNull);
      expect(fetched!.pid, equals(9999));
      expect(fetched.role, equals('actor'));

      final list = await registry.listRecords();
      expect(list.length, equals(1));
      expect(list.first.pid, equals(9999));
    });

    test('unregisterRecord rimuove il file record per il ruolo specificato',
        () async {
      final record = ProcessOwnershipRecord(
        schemaVersion: 1,
        pid: 8888,
        role: 'evaluator',
        ownerInstanceId: 'inst-eval',
        parentPid: 1000,
        executablePathHash: 'hash-exec',
        modelPathHash: 'hash-model',
        modelAlias: 'aura.evaluator.primary',
        port: 30202,
        startedAt: DateTime.now(),
        state: 'ready',
      );

      await registry.registerRecord(record);
      expect(await registry.getRecord('evaluator'), isNotNull);

      await registry.unregisterRecord('evaluator');
      expect(await registry.getRecord('evaluator'), isNull);
      expect(await registry.listRecords(), isEmpty);
    });

    test(
        'cleanupStaleProcesses non rimuove i record dell\'ownerInstanceId corrente',
        () async {
      final record = ProcessOwnershipRecord(
        schemaVersion: 1,
        pid: 7777,
        role: 'actor',
        ownerInstanceId: 'active-owner-123',
        parentPid: 1000,
        executablePathHash: 'hash-exec',
        modelPathHash: 'hash-model',
        modelAlias: 'aura.actor.primary',
        port: 30201,
        startedAt: DateTime.now(),
        state: 'ready',
      );

      await registry.registerRecord(record);

      final cleaned = await registry.cleanupStaleProcesses(
        currentOwnerInstanceId: 'active-owner-123',
      );

      expect(cleaned, isEmpty);
      expect(await registry.getRecord('actor'), isNotNull);
    });

    test(
        'cleanupStaleProcesses bonifica i record di PID non attivi di vecchie sessioni',
        () async {
      final record = ProcessOwnershipRecord(
        schemaVersion: 1,
        pid: 999999, // PID inesistente
        role: 'actor',
        ownerInstanceId: 'old-session-id',
        parentPid: 1000,
        executablePathHash: 'hash-exec',
        modelPathHash: 'hash-model',
        modelAlias: 'aura.actor.primary',
        port: 30201,
        startedAt: DateTime.now(),
        state: 'ready',
      );

      await registry.registerRecord(record);

      final cleaned = await registry.cleanupStaleProcesses(
        currentOwnerInstanceId: 'new-session-id',
      );

      expect(cleaned.length, equals(1));
      expect(cleaned.first.pid, equals(999999));
      expect(await registry.getRecord('actor'), isNull);
    });
  });

  group('System Process Probe Tests (POSIX & Windows) -', () {
    late FakeProcessCommandRunner fakeRunner;

    setUp(() {
      fakeRunner = FakeProcessCommandRunner();
    });

    test(
        'Branch POSIX rileva processo vivo e corrispondente tramite kill -0 e ps',
        () async {
      final posixRegistry = ProcessOwnershipRegistry(
        pathResolver: pathResolver,
        lock: InMemoryProvisioningLock(),
        commandRunner: fakeRunner,
        isWindows: false,
      );

      final exePath = '/usr/local/bin/llama-server';
      final exeHash =
          ProcessOwnershipRecord.hashPath(exePath, isWindows: false);

      var killCalledWithPid = 0;
      fakeRunner.onCommand('kill', (args) {
        if (args.contains('-0')) {
          expect(args, contains('4321'));
          return ProcessResult(1, 0, '', '');
        }
        if (args.contains('-9')) {
          killCalledWithPid = int.parse(args.last);
          return ProcessResult(2, 0, '', '');
        }
        return ProcessResult(3, 1, '', 'Unknown kill args');
      });

      fakeRunner.onCommand('lsof', (args) {
        return ProcessResult(4, 0, 'p4321\nftxt\nn$exePath\n', '');
      });

      final record = ProcessOwnershipRecord(
        schemaVersion: 1,
        pid: 4321,
        role: 'actor',
        ownerInstanceId: 'stale-instance-posix',
        parentPid: 1000,
        executablePathHash: exeHash,
        modelPathHash: 'hash-model',
        modelAlias: 'aura.actor.primary',
        port: 30201,
        startedAt: DateTime.now(),
        state: 'ready',
      );

      await posixRegistry.registerRecord(record);

      final cleaned = await posixRegistry.cleanupStaleProcesses(
        currentOwnerInstanceId: 'new-active-instance',
      );

      expect(cleaned.length, equals(1));
      expect(cleaned.first.pid, equals(4321));
      expect(killCalledWithPid, equals(4321));
      expect(await posixRegistry.getRecord('actor'), isNull);
    });

    test('Branch POSIX risolve correttamente path con spazi tramite lsof (-Fn)',
        () async {
      final posixRegistry = ProcessOwnershipRegistry(
        pathResolver: pathResolver,
        lock: InMemoryProvisioningLock(),
        commandRunner: fakeRunner,
        isWindows: false,
      );

      const exePath = '/Applications/AURA Runtime/llama-server';
      final exeHash =
          ProcessOwnershipRecord.hashPath(exePath, isWindows: false);

      var killNineCalled = false;
      fakeRunner.onCommand('kill', (args) {
        if (args.contains('-0')) {
          return ProcessResult(1, 0, '', '');
        }
        if (args.contains('-9')) {
          killNineCalled = true;
          return ProcessResult(2, 0, '', '');
        }
        return ProcessResult(3, 1, '', '');
      });

      fakeRunner.onCommand('lsof', (args) {
        expect(args, contains('-Fn'));
        expect(args, contains('7777'));
        return ProcessResult(4, 0, 'p7777\nftxt\nn$exePath\n', '');
      });

      final record = ProcessOwnershipRecord(
        schemaVersion: 1,
        pid: 7777,
        role: 'evaluator',
        ownerInstanceId: 'stale-space-instance',
        parentPid: 1000,
        executablePathHash: exeHash,
        modelPathHash: 'hash-model',
        modelAlias: 'aura.evaluator.primary',
        port: 30202,
        startedAt: DateTime.now(),
        state: 'ready',
      );

      await posixRegistry.registerRecord(record);

      final cleaned = await posixRegistry.cleanupStaleProcesses(
        currentOwnerInstanceId: 'new-instance',
      );

      expect(cleaned.length, equals(1));
      expect(cleaned.first.pid, equals(7777));
      expect(killNineCalled, isTrue);
      expect(await posixRegistry.getRecord('evaluator'), isNull);
    });

    test(
        'Branch POSIX fallback su ps rileva correttamente percorso con spazi prima degli argomenti',
        () async {
      final posixRegistry = ProcessOwnershipRegistry(
        pathResolver: pathResolver,
        lock: InMemoryProvisioningLock(),
        commandRunner: fakeRunner,
        isWindows: false,
      );

      const exePath = '/Applications/AURA Runtime/llama-server';
      final exeHash =
          ProcessOwnershipRecord.hashPath(exePath, isWindows: false);

      var killNineCalled = false;
      fakeRunner.onCommand('kill', (args) {
        if (args.contains('-0')) {
          return ProcessResult(1, 0, '', '');
        }
        if (args.contains('-9')) {
          killNineCalled = true;
          return ProcessResult(2, 0, '', '');
        }
        return ProcessResult(3, 1, '', '');
      });

      // Simula lsof non disponibile o fallito
      fakeRunner.onCommand('lsof', (args) {
        return ProcessResult(4, 1, '', 'lsof: not found');
      });

      fakeRunner.onCommand('ps', (args) {
        expect(args, contains('8888'));
        expect(args, contains('command='));
        return ProcessResult(
            5, 0, '$exePath --port 30201 --model /models/actor.gguf', '');
      });

      final record = ProcessOwnershipRecord(
        schemaVersion: 1,
        pid: 8888,
        role: 'actor',
        ownerInstanceId: 'stale-space-ps-instance',
        parentPid: 1000,
        executablePathHash: exeHash,
        modelPathHash: 'hash-model',
        modelAlias: 'aura.actor.primary',
        port: 30201,
        startedAt: DateTime.now(),
        state: 'ready',
      );

      await posixRegistry.registerRecord(record);

      final cleaned = await posixRegistry.cleanupStaleProcesses(
        currentOwnerInstanceId: 'new-instance',
      );

      expect(cleaned.length, equals(1));
      expect(cleaned.first.pid, equals(8888));
      expect(killNineCalled, isTrue);
      expect(await posixRegistry.getRecord('actor'), isNull);
    });

    test(
        'Branch POSIX bonifica record stale se kill -0 indica che il PID non esiste',
        () async {
      final posixRegistry = ProcessOwnershipRegistry(
        pathResolver: pathResolver,
        lock: InMemoryProvisioningLock(),
        commandRunner: fakeRunner,
        isWindows: false,
      );

      var killMinusNineCalled = false;
      fakeRunner.onCommand('kill', (args) {
        if (args.contains('-0')) {
          return ProcessResult(1, 1, '', 'No such process');
        }
        if (args.contains('-9')) {
          killMinusNineCalled = true;
          return ProcessResult(2, 0, '', '');
        }
        return ProcessResult(3, 1, '', '');
      });

      final record = ProcessOwnershipRecord(
        schemaVersion: 1,
        pid: 5555,
        role: 'evaluator',
        ownerInstanceId: 'stale-instance',
        parentPid: 1000,
        executablePathHash: 'any-hash',
        modelPathHash: 'hash-model',
        modelAlias: 'aura.evaluator.primary',
        port: 30202,
        startedAt: DateTime.now(),
        state: 'ready',
      );

      await posixRegistry.registerRecord(record);

      final cleaned = await posixRegistry.cleanupStaleProcesses(
        currentOwnerInstanceId: 'current-instance',
      );

      expect(cleaned.length, equals(1));
      expect(cleaned.first.pid, equals(5555));
      expect(killMinusNineCalled, isFalse);
      expect(await posixRegistry.getRecord('evaluator'), isNull);
    });

    test(
        'Branch Windows rileva processo vivo e corrispondente tramite tasklist e wmic',
        () async {
      final winRegistry = ProcessOwnershipRegistry(
        pathResolver: pathResolver,
        lock: InMemoryProvisioningLock(),
        commandRunner: fakeRunner,
        isWindows: true,
      );

      const exePath = r'C:\Tools\llama-server.exe';
      final exeHash = ProcessOwnershipRecord.hashPath(exePath, isWindows: true);

      var taskkillCalled = false;
      fakeRunner.onCommand('tasklist', (args) {
        return ProcessResult(
            1, 0, '"llama-server.exe","8888","Console","1","50.000 K"', '');
      });

      fakeRunner.onCommand('wmic', (args) {
        return ProcessResult(2, 0, 'ExecutablePath\n$exePath\n', '');
      });

      fakeRunner.onCommand('taskkill', (args) {
        taskkillCalled = true;
        expect(args, contains('8888'));
        return ProcessResult(3, 0, '', '');
      });

      final record = ProcessOwnershipRecord(
        schemaVersion: 1,
        pid: 8888,
        role: 'actor',
        ownerInstanceId: 'stale-win-instance',
        parentPid: 1000,
        executablePathHash: exeHash,
        modelPathHash: 'hash-model',
        modelAlias: 'aura.actor.primary',
        port: 30201,
        startedAt: DateTime.now(),
        state: 'ready',
      );

      await winRegistry.registerRecord(record);

      final cleaned = await winRegistry.cleanupStaleProcesses(
        currentOwnerInstanceId: 'current-win-instance',
      );

      expect(cleaned.length, equals(1));
      expect(cleaned.first.pid, equals(8888));
      expect(taskkillCalled, isTrue);
      expect(await winRegistry.getRecord('actor'), isNull);
    });
  });

  group('ProcessOwnershipRecord.hashPath Platform-Awareness Tests -', () {
    test(
        'hashPath su POSIX preserva il case e non collide tra maiuscole e minuscole',
        () {
      final pathUpper = '/Users/Test/llama-server';
      final pathLower = '/users/test/llama-server';

      final hashUpper =
          ProcessOwnershipRecord.hashPath(pathUpper, isWindows: false);
      final hashLower =
          ProcessOwnershipRecord.hashPath(pathLower, isWindows: false);

      expect(hashUpper, isNot(equals(hashLower)));
    });

    test('hashPath su Windows collassa il case (case-insensitive)', () {
      final pathUpper = r'C:\Users\Test\llama-server.exe';
      final pathLower = r'c:\users\test\llama-server.exe';

      final hashUpper =
          ProcessOwnershipRecord.hashPath(pathUpper, isWindows: true);
      final hashLower =
          ProcessOwnershipRecord.hashPath(pathLower, isWindows: true);

      expect(hashUpper, equals(hashLower));
    });

    test(
        'hashPath normalizza i separatori a slash su POSIX e backslash su Windows',
        () {
      final posixSlash = '/opt/aura/bin/llama-server';
      final posixBackslash = r'\opt\aura\bin\llama-server';

      expect(
        ProcessOwnershipRecord.hashPath(posixSlash, isWindows: false),
        equals(
            ProcessOwnershipRecord.hashPath(posixBackslash, isWindows: false)),
      );

      final winBackslash = r'C:\Aura\bin\llama-server.exe';
      final winSlash = 'C:/Aura/bin/llama-server.exe';

      expect(
        ProcessOwnershipRecord.hashPath(winBackslash, isWindows: true),
        equals(ProcessOwnershipRecord.hashPath(winSlash, isWindows: true)),
      );
    });
  });
}

final class FakeProcessCommandRunner implements ProcessCommandRunner {
  final Map<String, ProcessResult Function(List<String> args)> _handlers = {};

  void onCommand(
      String executable, ProcessResult Function(List<String> args) handler) {
    _handlers[executable] = handler;
  }

  @override
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    Duration? timeout,
  }) async {
    final handler = _handlers[executable];
    if (handler != null) {
      return handler(arguments);
    }
    return ProcessResult(0, 1, '', 'Unknown command: $executable');
  }
}
