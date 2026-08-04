import 'dart:async';
import 'dart:io' as io show Platform, Process;

/// Contratto astratto per la rilevazione hardware delle funzionalità e capability della CPU.
abstract interface class CpuFeatureDetector {
  /// Rileva ed estrae l'insieme delle estensioni vettoriali ed istruzioni supportate dalla CPU ospitante.
  Future<Set<String>> detectCpuFeatures();
}

/// Implementazione predefinita per l'ambiente Windows e cross-platform basata su rilevazione fail-safe.
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
    };

    if (io.Platform.isWindows) {
      try {
        final result = await io.Process.run(
          'powershell',
          [
            '-NoProfile',
            '-Command',
            r'(Get-CimInstance Win32_Processor).Name; (Get-CimInstance Win32_Processor).Caption',
          ],
        );

        if (result.exitCode == 0) {
          final out = result.stdout.toString().toUpperCase();
          if (out.contains('RYZEN') ||
              out.contains('CORE') ||
              out.contains('XEON') ||
              out.contains('EPYC') ||
              out.contains('INTEL') ||
              out.contains('AMD64') ||
              out.contains('STEPPING')) {
            features.add('avx');
            features.add('avx2');
            features.add('fma');
          }
        }
      } catch (_) {
        // Fail-safe: se la query CIM fallisce, non aggiunge AVX2/FMA senza conferma.
      }
    }

    return Set.unmodifiable(features);
  }
}
