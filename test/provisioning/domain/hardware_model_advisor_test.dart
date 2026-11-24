import 'package:aura_core/aura_offline.dart';
import 'package:test/test.dart';

void main() {
  // Dimensioni reali dei modelli predefiniti del catalogo bootstrap.
  const gemmaBytes = 6975879008; // Gemma 4 12B Q4_0
  const ministralBytes = 2146498240; // Ministral 3B Q4_K_M

  group('HardwareModelAdvisor', () {
    HardwareModelRecommendation forTotal(int? totalMiB) =>
        HardwareModelAdvisor.recommend(
          acceleration: RuntimeAcceleration.cuda,
          gpuTotalMiB: totalMiB,
          actorModelBytes: gemmaBytes,
          evaluatorModelBytes: ministralBytes,
        );

    test('RTX 3060 12 GB: due modelli, come misurato sulla scheda', () {
      final rec = forTotal(12287);
      expect(rec.topology, RecommendedModelTopology.separateModels);
      // Le stime coprono le misure congiunte senza eccedere oltre 300 MiB.
      expect(rec.estimatedSeparateMiB, inInclusiveRange(10734, 11034));
      expect(rec.estimatedSharedMiB, inInclusiveRange(8105, 8405));
    });

    test('GPU da 10 GB: solo il modello unico entra in VRAM', () {
      final rec = forTotal(10240);
      expect(rec.topology, RecommendedModelTopology.sharedActorModel);
      expect(rec.exceedsAvailableMemory, isFalse);
    });

    test('GPU da 8 GB: segnala che nemmeno il modello unico entra', () {
      final rec = forTotal(8192);
      expect(rec.topology, RecommendedModelTopology.sharedActorModel);
      expect(rec.exceedsAvailableMemory, isTrue);
    });

    test('GPU da 24 GB: due modelli', () {
      expect(forTotal(24576).topology, RecommendedModelTopology.separateModels);
    });

    test('senza GPU resta su due modelli e dichiara la stima non disponibile',
        () {
      final rec = HardwareModelAdvisor.recommend(
        acceleration: RuntimeAcceleration.cpu,
        gpuTotalMiB: null,
        actorModelBytes: gemmaBytes,
        evaluatorModelBytes: ministralBytes,
      );

      expect(rec.topology, RecommendedModelTopology.separateModels);
      expect(rec.isEstimateUnavailable, isTrue);
    });

    test('VRAM non rilevata non produce una raccomandazione presunta', () {
      final rec = HardwareModelAdvisor.recommend(
        acceleration: RuntimeAcceleration.cuda,
        gpuTotalMiB: null,
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
