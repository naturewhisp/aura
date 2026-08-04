import 'dart:async';
import 'dart:io' as io show Platform, Process;

/// Contratto astratto per la rilevazione hardware delle funzionalità e capability della CPU.
abstract interface class CpuFeatureDetector {
  /// Rileva ed estrae l'insieme delle estensioni vettoriali ed istruzioni supportate dalla CPU ospitante.
  Future<Set<String>> detectCpuFeatures();
}

/// Implementazione predefinita per l'ambiente Windows e cross-platform.
final class DefaultCpuFeatureDetector implements CpuFeatureDetector {
  const DefaultCpuFeatureDetector();

  @override
  Future<Set<String>> detectCpuFeatures() async {
    final features = <String>{
      'x64',
      'sse',
      'sse2',
      'sse3',
      'ssse3',
      'sse41',
      'sse4.1',
      'sse42',
      'sse4.2',
      'avx',
      'avx2',
    };

    if (io.Platform.isWindows) {
      try {
        final result = await io.Process.run(
          'powershell',
          [
            '-NoProfile',
            '-Command',
            r'[System.Runtime.Intrinsics.X86.Avx2]::IsSupported',
          ],
        );
        if (result.exitCode == 0) {
          final out = result.stdout.toString().trim().toLowerCase();
          if (out == 'true') {
            features.add('avx2');
          } else if (out == 'false') {
            features.remove('avx2');
          }
        }
      } catch (_) {
        // Fallback conservativo: si presuppone AVX2 su architetture x64 moderne
      }
    }

    return Set.unmodifiable(features);
  }
}
