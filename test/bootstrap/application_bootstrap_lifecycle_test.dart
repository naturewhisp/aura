import 'package:aura_core/aura_offline.dart';
import 'package:test/test.dart';

void main() {
  group('ApplicationBootstrap Lifecycle & Safety Tests -', () {
    test('Dispose is idempotent and safe to invoke multiple times', () async {
      const factory = ApplicationBootstrapFactory();
      final bootstrap = factory.create();

      final result = await bootstrap.bootstrap(
        const ApplicationBootstrapRequest(
          configuration: ApplicationRuntimeConfiguration(
            runtimeMode: ApplicationRuntimeMode.ruleBased,
          ),
        ),
      );

      await result.dispose();
      await expectLater(result.dispose(), completes);
      await expectLater(bootstrap.dispose(), completes);
    });

    test('Calling bootstrap twice on same instance throws alreadyBootstrapped',
        () async {
      const factory = ApplicationBootstrapFactory();
      final bootstrap = factory.create();

      await bootstrap.bootstrap(
        const ApplicationBootstrapRequest(
          configuration: ApplicationRuntimeConfiguration(
            runtimeMode: ApplicationRuntimeMode.ruleBased,
          ),
        ),
      );

      expect(
        () => bootstrap.bootstrap(
          const ApplicationBootstrapRequest(
            configuration: ApplicationRuntimeConfiguration(
              runtimeMode: ApplicationRuntimeMode.ruleBased,
            ),
          ),
        ),
        throwsA(
          isA<ApplicationBootstrapException>().having(
            (e) => e.failure.code,
            'code',
            equals(ApplicationBootstrapFailureCode.alreadyBootstrapped),
          ),
        ),
      );

      await bootstrap.dispose();
    });

    test('Calling bootstrap after dispose throws alreadyDisposed', () async {
      const factory = ApplicationBootstrapFactory();
      final bootstrap = factory.create();

      await bootstrap.dispose();

      expect(
        () => bootstrap.bootstrap(
          const ApplicationBootstrapRequest(
            configuration: ApplicationRuntimeConfiguration(
              runtimeMode: ApplicationRuntimeMode.ruleBased,
            ),
          ),
        ),
        throwsA(
          isA<ApplicationBootstrapException>().having(
            (e) => e.failure.code,
            'code',
            equals(ApplicationBootstrapFailureCode.alreadyDisposed),
          ),
        ),
      );
    });
  });
}
