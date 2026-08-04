import 'dart:async';
import 'dart:io' as io show Platform, Process;

/// Contratto astratto per la rilevazione hardware delle funzionalità e capability della CPU.
abstract interface class CpuFeatureDetector {
  /// Rileva ed estrae l'insieme delle estensioni vettoriali ed istruzioni supportate dalla CPU ospitante.
  Future<Set<String>> detectCpuFeatures();
}

/// Implementazione predefinita per l'ambiente Windows basata su CPUID nativo e OSXSAVE (Fail-Closed).
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
        const script = r'''
$code = @"
using System;
using System.Runtime.InteropServices;

public class NativeCpuCheck {
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate void CpuIdDelegate(int level, int subLevel, int[] output);

    private static readonly byte[] CpuIdCode64 = new byte[] {
        0x53, 0x89, 0xC8, 0x89, 0xD1, 0x0F, 0xA2, 0x41, 0x89, 0x00, 0x41, 0x89, 0x58, 0x04, 0x41, 0x89, 0x48, 0x08, 0x41, 0x89, 0x58, 0x0C, 0x5B, 0xC3
    };

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr VirtualAlloc(IntPtr lpAddress, UIntPtr dwSize, uint flAllocationType, uint flProtect);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool VirtualFree(IntPtr lpAddress, UIntPtr dwSize, uint dwFreeType);

    public static string Check() {
        try {
            IntPtr codePtr = VirtualAlloc(IntPtr.Zero, (UIntPtr)CpuIdCode64.Length, 0x3000, 0x40);
            if (codePtr == IntPtr.Zero) return "FAIL";
            Marshal.Copy(CpuIdCode64, 0, codePtr, CpuIdCode64.Length);
            CpuIdDelegate cpuid = (CpuIdDelegate)Marshal.GetDelegateForFunctionPointer(codePtr, typeof(CpuIdDelegate));

            int[] res1 = new int[4];
            cpuid(1, 0, res1);
            bool fma = (res1[2] & (1 << 12)) != 0;
            bool osxsave = (res1[2] & (1 << 27)) != 0;
            bool avx1 = (res1[2] & (1 << 28)) != 0;

            int[] res7 = new int[4];
            cpuid(7, 0, res7);
            bool avx2 = (res7[1] & (1 << 5)) != 0;

            VirtualFree(codePtr, UIntPtr.Zero, 0x8000);

            return "AVX2:" + (avx2 && osxsave) + ",FMA:" + (fma && osxsave) + ",AVX:" + (avx1 && osxsave);
        } catch {
            return "FAIL";
        }
    }
}
"@
Add-Type -TypeDefinition $code
[NativeCpuCheck]::Check()
''';

        final result = await io.Process.run(
          'powershell',
          [
            '-NoProfile',
            '-Command',
            script,
          ],
        );

        if (result.exitCode == 0) {
          final out = result.stdout.toString().trim().toUpperCase();
          if (out.contains('AVX2:TRUE')) {
            features.add('avx2');
          }
          if (out.contains('AVX:TRUE')) {
            features.add('avx');
          }
          if (out.contains('FMA:TRUE')) {
            features.add('fma');
          }
        }
      } catch (_) {
        // Politica Fail-Closed: se la query CPUID/OSXSAVE nativa fallisce, nessun flag AVX2/FMA viene aggiunto senza certezza.
      }
    }

    return Set.unmodifiable(features);
  }
}
