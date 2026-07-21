import 'package:aura_core/aura_testing.dart';
import 'package:test/test.dart';

void main() {
  group('PortAllocator Tests', () {
    test('FakePortAllocator returns preferred or configured port', () async {
      const allocator = FakePortAllocator(allocatedPort: 9090);

      final p1 = await allocator.allocatePort(preferredPort: 1234);
      expect(p1, equals(1234));

      final p2 = await allocator.allocatePort();
      expect(p2, equals(9090));
    });

    test('LoopbackPortAllocator allocates real open port on local machine',
        () async {
      const allocator = LoopbackPortAllocator();

      final port = await allocator.allocatePort();
      expect(port, greaterThan(0));
      expect(port, lessThanOrEqualTo(65535));
    });
  });
}
