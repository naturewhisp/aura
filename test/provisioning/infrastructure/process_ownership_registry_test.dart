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
      bundledRoot: '${tempDir.path}\\bundled',
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
}
