import 'dart:async';
import 'package:aura_core/aura_core.dart';
import 'package:test/test.dart';

void main() {
  group('InMemoryProvisioningLock Tests -', () {
    late InMemoryProvisioningLock lock;

    setUp(() {
      lock = InMemoryProvisioningLock();
    });

    test('Serializza le esecuzioni asincrone sulla medesima chiave', () async {
      final executionOrder = <int>[];
      final completer1 = Completer<void>();

      final f1 = lock.synchronized('key_installation', () async {
        executionOrder.add(1);
        await completer1.future;
        executionOrder.add(2);
      });

      final f2 = lock.synchronized('key_installation', () async {
        executionOrder.add(3);
      });

      // f1 ha avviato la sua esecuzione, f2 è in attesa
      await pumpEventQueue();
      expect(executionOrder, equals([1]));

      completer1.complete();
      await Future.wait([f1, f2]);

      expect(executionOrder, equals([1, 2, 3]));
    });

    test('Consente l esecuzione parallela per chiavi differenti', () async {
      final executionOrder = <String>[];
      final completer = Completer<void>();

      final f1 = lock.synchronized('key_1', () async {
        executionOrder.add('start_1');
        await completer.future;
        executionOrder.add('end_1');
      });

      final f2 = lock.synchronized('key_2', () async {
        executionOrder.add('start_2');
      });

      await pumpEventQueue();
      expect(executionOrder, containsAllInOrder(['start_1', 'start_2']));

      completer.complete();
      await Future.wait([f1, f2]);
    });
  });
}
