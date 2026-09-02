import 'package:aura_core/aura_offline.dart';
import 'package:aura_core/aura_testing.dart';
import 'package:test/test.dart';

void main() {
  group('DefaultApplicationBootstrap - Dual Managed Mode', () {
    test(
        'bootstrap con managedInferenceTopology avvia due supervisor e produce DualModelInferenceBridge',
        () async {
      const topology = ManagedInferenceTopology(
        actor: ManagedRoleRuntimeConfiguration(
          role: InferenceModelRole.actor,
          modelId: 'aura.actor.primary',
          serverConfiguration: ManagedLlamaServerConfiguration(
            executablePath: 'llama-server.exe',
            modelPath: 'actor.gguf',
            modelAlias: 'aura.actor.primary',
          ),
        ),
        evaluator: ManagedRoleRuntimeConfiguration(
          role: InferenceModelRole.evaluator,
          modelId: 'aura.evaluator.primary',
          serverConfiguration: ManagedLlamaServerConfiguration(
            executablePath: 'llama-server.exe',
            modelPath: 'evaluator.gguf',
            modelAlias: 'aura.evaluator.primary',
          ),
        ),
      );

      final bootstrap = DefaultApplicationBootstrap();
      final launcher = FakeProcessLauncher();
      final portAllocator = const FakePortAllocator(allocatedPort: 30200);
      final healthProbe = FakeLlamaServerHealthProbe(
        isResponsive: true,
        modelVisible: true,
      );

      final request = ApplicationBootstrapRequest(
        appManagedRoot: r'C:\TestAura\store',
        bundledRoot: r'C:\TestAura\bundled',
        configuration: const ApplicationRuntimeConfiguration(
          runtimeMode: ApplicationRuntimeMode.managedLlamaServer,
          managedInferenceTopology: topology,
          actorModelId: 'aura.actor.primary',
          evaluatorModelId: 'aura.evaluator.primary',
          skipHealthCheck: true,
        ),
        customProcessLauncher: launcher,
        customPortAllocator: portAllocator,
        customHealthProbe: healthProbe,
        customFileSystem: const FakeFileSystem(
          existingFiles: {'llama-server.exe', 'actor.gguf', 'evaluator.gguf'},
        ),
        customDelegateFactory: (clientConfig) => ExternalOpenAiRuntime(
          configuration: clientConfig,
          client: FakeExternalOpenAiClient(
            healthy: true,
            availableModels: const [
              'aura.actor.primary',
              'aura.evaluator.primary'
            ],
          ),
          bindings: const [
            ExternalOpenAiModelBinding(
              logicalModelId: 'aura.actor.primary',
              serverModelId: 'aura.actor.primary',
              roles: {ModelRole.actor},
            ),
            ExternalOpenAiModelBinding(
              logicalModelId: 'aura.evaluator.primary',
              serverModelId: 'aura.evaluator.primary',
              roles: {ModelRole.evaluator},
            ),
          ],
        ),
      );

      try {
        final result = await bootstrap.bootstrap(request);

        expect(result.runtimeMode,
            equals(ApplicationRuntimeMode.managedLlamaServer));
        expect(result.activeBridge, isA<DualModelInferenceBridge>());
        expect(result.status.isHealthy, isTrue);
        expect(result.status.diagnostics['dualProcess'], isTrue);

        // Cleanup
        await result.dispose();
      } catch (e) {
        if (e is ApplicationBootstrapException) {
          print('BOOTSTRAP CAUSE: ${e.cause}');
        }
        rethrow;
      }
    });
  });
}
