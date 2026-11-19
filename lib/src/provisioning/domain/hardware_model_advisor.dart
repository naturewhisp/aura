import 'package:meta/meta.dart';

import 'runtime_dependency_models.dart';

/// Topologia di modelli consigliata per l'hardware rilevato.
enum RecommendedModelTopology {
  /// Due modelli distinti (Actor + Evaluator) su due processi.
  separateModels,

  /// Un solo modello (quello dell'Actor) usato da entrambi i ruoli su un processo.
  sharedActorModel,
}

/// Raccomandazione hardware per la configurazione dei modelli.
@immutable
final class HardwareModelRecommendation {
  final RecommendedModelTopology topology;

  /// Motivazione in italiano, pronta per la UI.
  final String rationale;

  /// `true` se nemmeno la configurazione consigliata entra interamente in VRAM.
  final bool exceedsAvailableMemory;

  /// `true` se la raccomandazione non si basa su una misura di VRAM.
  final bool isEstimateUnavailable;

  final int? estimatedSeparateMiB;
  final int? estimatedSharedMiB;
  final int? availableMiB;

  const HardwareModelRecommendation({
    required this.topology,
    required this.rationale,
    this.exceedsAvailableMemory = false,
    this.isEstimateUnavailable = false,
    this.estimatedSeparateMiB,
    this.estimatedSharedMiB,
    this.availableMiB,
  });
}

/// Stima la VRAM necessaria e consiglia se usare due modelli o uno condiviso.
///
/// Le stime sono tarate su misure reali (`nvidia-smi`, RTX 3060, llama.cpp b10256,
/// `-ngl 99`, novembre 2026):
/// - Ministral 3B Q4_K_M (2047 MiB su disco), contesto 8k: +3092 MiB;
/// - Gemma 4 12B Q4_0 (6653 MiB su disco), contesto 16k: +7655 MiB;
/// - Gemma 4 12B Q4_0, contesto 24k su 2 slot (modello condiviso): +8253 MiB.
///
/// Due processi sullo stesso file NON condividono la VRAM (+3086 MiB misurati per
/// il secondo processo): il risparmio si ottiene solo con un processo unico.
abstract final class HardwareModelAdvisor {
  /// Overhead per processo (KV cache, buffer di calcolo, contesto CUDA) al
  /// contesto di gioco, arrotondato per eccesso dalle misure.
  static const int perProcessOverheadMiB = 1100;

  /// Overhead del processo condiviso (contesto Actor + Evaluator su 2 slot).
  static const int sharedProcessOverheadMiB = 1700;

  /// Margine lasciato libero per desktop, driver e picchi di allocazione.
  static const int safetyMarginMiB = 512;

  static HardwareModelRecommendation recommend({
    required RuntimeAcceleration acceleration,
    required int? gpuFreeMiB,
    required int actorModelBytes,
    required int evaluatorModelBytes,
  }) {
    final actorMiB = _toMiB(actorModelBytes);
    final evaluatorMiB = _toMiB(evaluatorModelBytes);
    final separate = actorMiB +
        evaluatorMiB +
        2 * perProcessOverheadMiB; // due processi, due copie dei buffer
    final shared = actorMiB + sharedProcessOverheadMiB;

    if (acceleration == RuntimeAcceleration.cpu) {
      return HardwareModelRecommendation(
        topology: RecommendedModelTopology.separateModels,
        rationale:
            'Nessuna GPU compatibile: i modelli girano in RAM di sistema, '
            'dove due processi condividono le pagine dello stesso file. Restano '
            'consigliati due modelli distinti, ma ogni turno richiederà più tempo.',
        isEstimateUnavailable: true,
        estimatedSeparateMiB: separate,
        estimatedSharedMiB: shared,
      );
    }

    if (gpuFreeMiB == null) {
      return HardwareModelRecommendation(
        topology: RecommendedModelTopology.separateModels,
        rationale: 'VRAM disponibile non rilevata: configurazione standard con '
            'due modelli distinti. Se il gioco risulta lento, prova un solo '
            'modello per entrambi i ruoli.',
        isEstimateUnavailable: true,
        estimatedSeparateMiB: separate,
        estimatedSharedMiB: shared,
      );
    }

    final available = gpuFreeMiB - safetyMarginMiB;
    if (separate <= available) {
      return HardwareModelRecommendation(
        topology: RecommendedModelTopology.separateModels,
        rationale: 'VRAM sufficiente per due modelli distinti '
            '(stima ${_gb(separate)} su ${_gb(gpuFreeMiB)} liberi): '
            'Attore e Valutatore specializzati, la scelta migliore.',
        estimatedSeparateMiB: separate,
        estimatedSharedMiB: shared,
        availableMiB: gpuFreeMiB,
      );
    }

    return HardwareModelRecommendation(
      topology: RecommendedModelTopology.sharedActorModel,
      rationale: 'Due modelli richiederebbero circa ${_gb(separate)} di VRAM, '
          'ma ne sono liberi ${_gb(gpuFreeMiB)}: il driver sposterebbe parte dei '
          'pesi in RAM, rallentando ogni turno. Usare il modello dell\'Attore '
          'anche come Valutatore richiede circa ${_gb(shared)} su un solo processo.',
      exceedsAvailableMemory: shared > available,
      estimatedSeparateMiB: separate,
      estimatedSharedMiB: shared,
      availableMiB: gpuFreeMiB,
    );
  }

  static int _toMiB(int bytes) => (bytes / (1024 * 1024)).ceil();

  static String _gb(int mib) => '${(mib / 1024).toStringAsFixed(1)} GB';
}
