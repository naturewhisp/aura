import 'package:aura_core/aura_offline.dart';
import 'package:test/test.dart';

void main() {
  group('ApplicationBootstrapFactory Tests -', () {
    test('Factory creates a valid ApplicationBootstrap instance', () {
      const factory = ApplicationBootstrapFactory();
      final bootstrap = factory.create();

      expect(bootstrap, isA<ApplicationBootstrap>());
    });

    test('Created bootstrap runs rule-based mode offline without network',
        () async {
      const factory = ApplicationBootstrapFactory();
      final bootstrap = factory.create();

      final result = await bootstrap.bootstrap(
        const ApplicationBootstrapRequest(
          configuration: ApplicationRuntimeConfiguration(
            runtimeMode: ApplicationRuntimeMode.ruleBased,
          ),
        ),
      );

      expect(result.runtimeMode, equals(ApplicationRuntimeMode.ruleBased));
      expect(result.controller, isA<GameController>());
      expect(result.activeBridge, isA<InferenceBridge>());
      expect(result.status.isHealthy, isTrue);
      expect(result.runtime, isA<InferenceRuntime>());

      await result.dispose();
    });
  });
}
