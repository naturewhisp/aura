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
/// Misure congiunte (RTX 3060 12 GB, llama.cpp b10256, `-ngl 99`, 2026-11-24,
/// partendo da circa 1 GB occupato dal desktop):
/// - Gemma 4 12B 16k + Ministral 3B 8k, due processi: +10734 MiB;
/// - Gemma 4 12B 24k, un processo, 2 slot unificati: +8105 MiB.
///
/// Due modelli sono anche più veloci: il Valutatore dedicato genera a circa
/// 115 t/s contro 38 t/s di Gemma, e a parità di messaggi i turni condivisi
/// sono risultati più lenti del 20-40%. Il modello unico è quindi consigliato
/// solo quando due modelli non entrano nella VRAM.
///
/// Si usa la VRAM TOTALE: su Windows quella "libera" di `--list-devices` ignora
/// le altre applicazioni, che il driver sfratta quando serve.
abstract final class HardwareModelAdvisor {
  /// Overhead per processo (KV cache, buffer di calcolo, contesto CUDA).
  static const int perProcessOverheadMiB = 1100;

  /// Overhead del processo condiviso (contesto Actor + Evaluator su 2 slot).
  static const int sharedProcessOverheadMiB = 1500;

  /// VRAM che resta comunque al desktop e al driver.
  static const int desktopReserveMiB = 1024;

  static HardwareModelRecommendation recommend({
    required RuntimeAcceleration acceleration,
    required int? gpuTotalMiB,
    required int actorModelBytes,
    required int evaluatorModelBytes,
  }) {
    final actorMiB = _toMiB(actorModelBytes);
    final separate = actorMiB +
        _toMiB(evaluatorModelBytes) +
        2 * perProcessOverheadMiB; // due processi, due copie dei buffer
    final shared = actorMiB + sharedProcessOverheadMiB;

    if (acceleration == RuntimeAcceleration.cpu || gpuTotalMiB == null) {
      return HardwareModelRecommendation(
        topology: RecommendedModelTopology.separateModels,
        rationale: acceleration == RuntimeAcceleration.cpu
            ? 'Nessuna GPU compatibile: i modelli girano in RAM di sistema e '
                'ogni turno richiede più tempo. Il Valutatore dedicato, più '
                'leggero, resta la scelta più rapida.'
            : 'VRAM della GPU non rilevata: configurazione standard con due '
                'modelli distinti.',
        isEstimateUnavailable: true,
        estimatedSeparateMiB: separate,
        estimatedSharedMiB: shared,
      );
    }

    final available = gpuTotalMiB - desktopReserveMiB;
    if (separate <= available) {
      return HardwareModelRecommendation(
        topology: RecommendedModelTopology.separateModels,
        rationale: 'Due modelli distinti (circa ${_gb(separate)}) entrano nei '
            '${_gb(gpuTotalMiB)} della GPU: il Valutatore dedicato è più '
            'rapido. Con altre app che usano la GPU potrebbe rallentare.',
        estimatedSeparateMiB: separate,
        estimatedSharedMiB: shared,
        availableMiB: available,
      );
    }

    return HardwareModelRecommendation(
      topology: RecommendedModelTopology.sharedActorModel,
      rationale: 'Due modelli (circa ${_gb(separate)}) non entrano nei '
          '${_gb(gpuTotalMiB)} della GPU. Un solo modello per entrambi i ruoli '
          'richiede circa ${_gb(shared)}: la valutazione è più lenta, ma '
          'si evita di spostare i pesi in RAM.',
      exceedsAvailableMemory: shared > available,
      estimatedSeparateMiB: separate,
      estimatedSharedMiB: shared,
      availableMiB: available,
    );
  }

  static int _toMiB(int bytes) => (bytes / (1024 * 1024)).ceil();

  static String _gb(int mib) => '${(mib / 1024).toStringAsFixed(1)} GB';
}
