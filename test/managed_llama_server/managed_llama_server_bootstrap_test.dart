import 'package:aura_core/aura_offline.dart';
import 'package:aura_core/aura_testing.dart';
import 'package:test/test.dart';

void main() {
  group('DefaultApplicationBootstrap - ManagedLlamaServer Integration Tests',
      () {
    const managedConfig = ManagedLlamaServerConfiguration(
      executablePath: 'llama-server.exe',
      modelPath: 'model.gguf',
      modelAlias: 'test-model',
    );

    late DefaultApplicationBootstrap bootstrap;

    setUp(() {
      bootstrap = DefaultApplicationBootstrap();
    });

    tearDown(() async {
      await bootstrap.dispose();
    });

    test(
        'Bootstraps managedLlamaServer mode successfully offline with custom test injection',
        () async {
      final request = ApplicationBootstrapRequest(
        configuration: const ApplicationRuntimeConfiguration(
          runtimeMode: ApplicationRuntimeMode.managedLlamaServer,
          managedLlamaConfig: managedConfig,
        ),
        customProcessLauncher: FakeProcessLauncher(),
        customPortAllocator: const FakePortAllocator(allocatedPort: 8080),
        customHealthProbe:
            FakeLlamaServerHealthProbe(isResponsive: true, modelVisible: true),
        customDelegateFactory: (clientConfig) => ExternalOpenAiRuntime(
          configuration: clientConfig,
          client: FakeExternalOpenAiClient(healthy: true),
          bindings: const [
            ExternalOpenAiModelBinding(
              logicalModelId: 'aura.actor.primary',
              serverModelId: 'test-model',
              roles: {ModelRole.actor, ModelRole.evaluator},
            ),
            ExternalOpenAiModelBinding(
              logicalModelId: 'aura.evaluator.primary',
              serverModelId: 'test-model',
              roles: {ModelRole.actor, ModelRole.evaluator},
            ),
          ],
        ),
      );

      final result = await bootstrap.bootstrap(request);

      expect(result.runtimeMode,
          equals(ApplicationRuntimeMode.managedLlamaServer));
      expect(result.status.isHealthy, isTrue);
      expect(result.status.diagnostics['managed'], isTrue);
      expect(result.status.diagnostics['allocatedPort'], equals(8080));
    });

    test(
        'Triggers rule-based fallback when fallbackPolicy is ruleBased and managed runtime fails',
        () async {
      final request = ApplicationBootstrapRequest(
        configuration: const ApplicationRuntimeConfiguration(
          runtimeMode: ApplicationRuntimeMode.managedLlamaServer,
          managedLlamaConfig: managedConfig,
          fallbackPolicy: BootstrapFallbackPolicy.ruleBased,
        ),
        customProcessLauncher: FakeProcessLauncher(shouldFail: true),
        customPortAllocator: const FakePortAllocator(allocatedPort: 8080),
        customHealthProbe: FakeLlamaServerHealthProbe(isResponsive: false),
      );

      final result = await bootstrap.bootstrap(request);

      expect(result.runtimeMode, equals(ApplicationRuntimeMode.ruleBased));
      expect(result.status.isHealthy, isTrue);
      expect(result.status.diagnostics['fallbackCleanupPerformed'], isTrue);
    });

    test(
        'Throws ApplicationBootstrapException when fallbackPolicy is none and configuration is invalid',
        () async {
      const invalidConfig = ManagedLlamaServerConfiguration(
        executablePath: '',
        modelPath: '',
      );

      final request = ApplicationBootstrapRequest(
        configuration: const ApplicationRuntimeConfiguration(
          runtimeMode: ApplicationRuntimeMode.managedLlamaServer,
          managedLlamaConfig: invalidConfig,
          fallbackPolicy: BootstrapFallbackPolicy.none,
        ),
      );

      expect(
        () => bootstrap.bootstrap(request),
        throwsA(isA<ApplicationBootstrapException>()),
      );
    });
  });
}
