import 'package:aura_core/aura_offline.dart';
import 'package:test/test.dart';

void main() {
  // Dimensioni reali dei modelli predefiniti del catalogo bootstrap.
  const gemmaBytes = 6975879008; // Gemma 4 12B Q4_0
  const ministralBytes = 2146498240; // Ministral 3B Q4_K_M

  group('HardwareModelAdvisor', () {
    test('RTX 3060 12 GB con VRAM libera misurata consiglia il modello unico',
        () {
      // Valore riportato da `--list-devices` sulla macchina di collaudo:
      // CUDA0: NVIDIA GeForce RTX 3060 (12287 MiB, 11253 MiB free).
      final rec = HardwareModelAdvisor.recommend(
        acceleration: RuntimeAcceleration.cuda,
        gpuFreeMiB: 11253,
        actorModelBytes: gemmaBytes,
        evaluatorModelBytes: ministralBytes,
      );

      expect(rec.topology, RecommendedModelTopology.sharedActorModel);
      expect(rec.exceedsAvailableMemory, isFalse);
      // Coerente con le misure: due processi ~10.7 GB, condiviso ~8.3 GB.
      expect(rec.estimatedSeparateMiB, greaterThanOrEqualTo(10747));
      expect(rec.estimatedSharedMiB, greaterThanOrEqualTo(8253));
    });

    test('GPU da 24 GB consiglia due modelli distinti', () {
      final rec = HardwareModelAdvisor.recommend(
        acceleration: RuntimeAcceleration.cuda,
        gpuFreeMiB: 22000,
        actorModelBytes: gemmaBytes,
        evaluatorModelBytes: ministralBytes,
      );

      expect(rec.topology, RecommendedModelTopology.separateModels);
      expect(rec.isEstimateUnavailable, isFalse);
    });

    test('GPU da 8 GB segnala che anche il modello unico è al limite', () {
      final rec = HardwareModelAdvisor.recommend(
        acceleration: RuntimeAcceleration.vulkan,
        gpuFreeMiB: 7000,
        actorModelBytes: gemmaBytes,
        evaluatorModelBytes: ministralBytes,
      );

      expect(rec.topology, RecommendedModelTopology.sharedActorModel);
      expect(rec.exceedsAvailableMemory, isTrue);
    });

    test('senza GPU resta su due modelli e dichiara la stima non disponibile',
        () {
      final rec = HardwareModelAdvisor.recommend(
        acceleration: RuntimeAcceleration.cpu,
        gpuFreeMiB: null,
        actorModelBytes: gemmaBytes,
        evaluatorModelBytes: ministralBytes,
      );

      expect(rec.topology, RecommendedModelTopology.separateModels);
      expect(rec.isEstimateUnavailable, isTrue);
    });

    test('VRAM non rilevata non produce una raccomandazione presunta', () {
      final rec = HardwareModelAdvisor.recommend(
        acceleration: RuntimeAcceleration.cuda,
        gpuFreeMiB: null,
        actorModelBytes: gemmaBytes,
        evaluatorModelBytes: ministralBytes,
      );

      expect(rec.topology, RecommendedModelTopology.separateModels);
      expect(rec.isEstimateUnavailable, isTrue);
      expect(rec.availableMiB, isNull);
    });
  });

  group('DefaultLlamaServerDependencyService.parseGpuMemory', () {
    test('estrae totale e libera dal formato CUDA', () {
      final mem = DefaultLlamaServerDependencyService.parseGpuMemory(
        'Available devices:\n'
        '  CUDA0: NVIDIA GeForce RTX 3060 (12287 MiB, 11253 MiB free)\n',
      );
      expect(mem?.totalMiB, 12287);
      expect(mem?.freeMiB, 11253);
    });

    test('accetta il formato Vulkan con solo il totale', () {
      final mem = DefaultLlamaServerDependencyService.parseGpuMemory(
        'Available devices:\n  Vulkan0: AMD Radeon RX 6700 XT (12272 MiB)\n',
      );
      expect(mem?.totalMiB, 12272);
      expect(mem?.freeMiB, isNull);
    });

    test('nessun dispositivo restituisce null', () {
      expect(
        DefaultLlamaServerDependencyService.parseGpuMemory(
          'Available devices:\n  (none)\n',
        ),
        isNull,
      );
    });
  });

  group('ManagedInferenceTopology.sharesModelFile', () {
    ManagedInferenceTopology topology(String actorPath, String evalPath) =>
        ManagedInferenceTopology(
          actor: ManagedRoleRuntimeConfiguration(
            role: InferenceModelRole.actor,
            modelId: 'aura.actor.primary',
            serverConfiguration: ManagedLlamaServerConfiguration(
              executablePath: r'C:\AURA\llama-server.exe',
              modelPath: actorPath,
              modelAlias: 'actor',
            ),
          ),
          evaluator: ManagedRoleRuntimeConfiguration(
            role: InferenceModelRole.evaluator,
            modelId: 'aura.evaluator.primary',
            serverConfiguration: ManagedLlamaServerConfiguration(
              executablePath: r'C:\AURA\llama-server.exe',
              modelPath: evalPath,
              modelAlias: 'evaluator',
            ),
          ),
        );

    test('riconosce lo stesso file Windows con maiuscole e separatori diversi',
        () {
      expect(
        topology(r'C:\Models\Gemma.gguf', 'c:/models/gemma.gguf')
            .sharesModelFile,
        isTrue,
      );
    });

    test('file diversi non sono condivisi', () {
      expect(
        topology(r'C:\Models\gemma.gguf', r'C:\Models\ministral.gguf')
            .sharesModelFile,
        isFalse,
      );
    });

    test('su POSIX le maiuscole distinguono i file', () {
      expect(
        topology('/models/Gemma.gguf', '/models/gemma.gguf').sharesModelFile,
        isFalse,
      );
    });
  });
}
