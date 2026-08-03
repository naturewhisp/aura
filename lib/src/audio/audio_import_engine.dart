import 'package:meta/meta.dart';
import 'audio_manifest.dart';
import 'wav_header_verifier.dart';

/// Contratto astratto per la lettura di asset di bundle/distribuzione.
abstract interface class AudioAssetSource {
  Future<List<int>?> read(String filename);
}

/// Contratto astratto per la gestione dello store di runtime audio.
abstract interface class ManagedAudioStore {
  Future<List<int>?> read(String filename);
  Future<void> writeAtomically(String filename, List<int> bytes);
  Future<void> delete(String filename);
}

/// Contratto astratto per il fallback procedurale degradato.
abstract interface class ProceduralAudioFallback {
  Future<List<int>> generate(AudioTrackDescriptor descriptor);
}

/// Traccia audio risolta e verificata dall'engine.
@immutable
final class ResolvedAudioTrack {
  final AudioTrackDescriptor descriptor;
  final String sourcePath;
  final bool isProceduralFallback;
  final List<int> bytes;
  final AudioAssetFailureCode? failureCode;

  const ResolvedAudioTrack({
    required this.descriptor,
    required this.sourcePath,
    required this.isProceduralFallback,
    required this.bytes,
    this.failureCode,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ResolvedAudioTrack &&
          runtimeType == other.runtimeType &&
          descriptor == other.descriptor &&
          sourcePath == other.sourcePath &&
          isProceduralFallback == other.isProceduralFallback &&
          failureCode == other.failureCode;

  @override
  int get hashCode => Object.hash(
        descriptor,
        sourcePath,
        isProceduralFallback,
        failureCode,
      );
}

/// Engine di risoluzione, validazione, ripristino atomico da bundle e fallback per le tracce audio.
final class AudioImportEngine {
  final AudioAssetSource bundledSource;
  final ManagedAudioStore managedStore;
  final ProceduralAudioFallback proceduralFallback;
  final WavHeaderVerifier verifier;

  const AudioImportEngine({
    required this.bundledSource,
    required this.managedStore,
    required this.proceduralFallback,
    this.verifier = const WavHeaderVerifier(),
  });

  /// Risolve tutte le tracce definite nel manifest applicando la sequenza di priorità e validazione.
  Future<Map<String, ResolvedAudioTrack>> resolveAll(
      AudioManifest manifest) async {
    final results = <String, ResolvedAudioTrack>{};

    for (final track in manifest.tracks) {
      final resolved = await resolveTrack(track);
      results[track.id] = resolved;
    }

    return results;
  }

  /// Risolve ed individua la sorgente di una singola traccia audio.
  Future<ResolvedAudioTrack> resolveTrack(AudioTrackDescriptor track) async {
    // 1. Prova a leggere dallo store gestito di runtime
    try {
      final managedBytes = await managedStore.read(track.filename);
      if (managedBytes != null) {
        final validation = verifier.verify(managedBytes, track);
        if (validation.isValid) {
          return ResolvedAudioTrack(
            descriptor: track,
            sourcePath: 'managedStore:${track.filename}',
            isProceduralFallback: false,
            bytes: managedBytes,
          );
        } else {
          // File corrotto nello store: rimuovi dalla cache gestita
          await managedStore.delete(track.filename);
        }
      }
    } catch (_) {
      // Ignora errori di lettura dallo store gestito per passare al ripristino da bundle
    }

    // 2. Tenta il ripristino dal bundle di distribuzione
    try {
      final bundledBytes = await bundledSource.read(track.filename);
      if (bundledBytes != null) {
        final validation = verifier.verify(bundledBytes, track);
        if (validation.isValid) {
          // Copia atomica dallo store di bundle al managed store
          await managedStore.writeAtomically(track.filename, bundledBytes);

          return ResolvedAudioTrack(
            descriptor: track,
            sourcePath: 'bundledStore:${track.filename}',
            isProceduralFallback: false,
            bytes: bundledBytes,
          );
        }
      }
    } catch (_) {
      // Ignora errori dal bundle per procedere al fallback degradato
    }

    // 3. Fallback procedurale degradato (senza sovrascrivere il file nel managed store)
    final fallbackBytes = await proceduralFallback.generate(track);
    return ResolvedAudioTrack(
      descriptor: track,
      sourcePath: 'proceduralFallback:${track.filename}',
      isProceduralFallback: true,
      bytes: fallbackBytes,
      failureCode: AudioAssetFailureCode.proceduralFallbackUsed,
    );
  }
}
