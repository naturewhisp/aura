import 'dart:async';
import 'dart:io' as io show Platform, Process;

/// DTO contenente lo snapshot immutabile delle feature CPUID e dello stato XCR0.
final class NativeCpuCapabilitySnapshot {
  final bool avxBit;
  final bool avx2Bit;
  final bool fmaBit;
  final bool osxsaveBit;
  final int xcr0Low;

  const NativeCpuCapabilitySnapshot({
    required this.avxBit,
    required this.avx2Bit,
    required this.fmaBit,
    required this.osxsaveBit,
    required this.xcr0Low,
  });

  /// Factory baseline fail-closed in caso di detection indeterminata o fallita.
  factory NativeCpuCapabilitySnapshot.baseline() {
    return const NativeCpuCapabilitySnapshot(
      avxBit: false,
      avx2Bit: false,
      fmaBit: false,
      osxsaveBit: false,
      xcr0Low: 0,
    );
  }
}

/// Trasforma lo snapshot delle feature CPUID/XCR0 nell'insieme di tag identificativi.
Set<String> classifyCpuFeatures(NativeCpuCapabilitySnapshot snapshot) {
  final stateEnabled = snapshot.osxsaveBit && (snapshot.xcr0Low & 0x6) == 0x6;

  final avxUsable = snapshot.avxBit && stateEnabled;
  final avx2Usable = snapshot.avx2Bit && avxUsable;
  final fmaUsable = snapshot.fmaBit && avxUsable;

  return Set.unmodifiable({
    'x64',
    'sse',
    'sse2',
    'sse3',
    'ssse3',
    'sse41',
    'sse4.1',
    'sse42',
    'sse4.2',
    if (avxUsable) 'avx',
    if (avx2Usable) 'avx2',
    if (fmaUsable) 'fma',
  });
}

/// Contratto astratto per la rilevazione hardware delle funzionalità e capability della CPU.
abstract interface class CpuFeatureDetector {
  /// Rileva ed estrae l'insieme delle estensioni vettoriali ed istruzioni supportate dalla CPU ospitante.
  Future<Set<String>> detectCpuFeatures();
}

/// Implementazione predefinita per l'ambiente Windows basata su CPUID nativo ed XGETBV (Fail-Closed).
final class DefaultCpuFeatureDetector implements CpuFeatureDetector {
  const DefaultCpuFeatureDetector();

  @override
  Future<Set<String>> detectCpuFeatures() async {
    if (!io.Platform.isWindows) {
      return classifyCpuFeatures(NativeCpuCapabilitySnapshot.baseline());
    }

    try {
      const script = r'''
$code = @"
using System;
using System.Runtime.InteropServices;

public class NativeCpuCheck {
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate void CpuIdDelegate(int level, int subLevel, int[] output);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate void XGetBvDelegate(int index, int[] output);

    private static readonly byte[] CpuIdCode64 = new byte[] {
        0x53,                   // push rbx
        0x89, 0xC8,             // mov eax, ecx
        0x89, 0xD1,             // mov ecx, edx
        0x0F, 0xA2,             // cpuid
        0x41, 0x89, 0x00,       // mov [r8], eax
        0x41, 0x89, 0x58, 0x04, // mov [r8+4], ebx
        0x41, 0x89, 0x48, 0x08, // mov [r8+8], ecx
        0x41, 0x89, 0x50, 0x0C, // mov [r8+12], edx
        0x5B,                   // pop rbx
        0xC3                    // ret
    };

    private static readonly byte[] XGetBvCode64 = new byte[] {
        0x53,                   // push rbx
        0x49, 0x89, 0xD0,       // mov r8, rdx (salva il puntatore output prima che xgetbv sovrascriva rdx)
        0x31, 0xC9,             // xor ecx, ecx (ecx = 0 per XCR0)
        0x0F, 0x01, 0xD0,       // xgetbv (restituisce edx:eax)
        0x41, 0x89, 0x00,       // mov [r8], eax (XCR0 low 32 bit)
        0x41, 0x89, 0x50, 0x04, // mov [r8+4], edx (XCR0 high 32 bit)
        0x5B,                   // pop rbx
        0xC3                    // ret
    };

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr VirtualAlloc(IntPtr lpAddress, UIntPtr dwSize, uint flAllocationType, uint flProtect);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool VirtualFree(IntPtr lpAddress, UIntPtr dwSize, uint dwFreeType);

    public static string Probe() {
        IntPtr cpuidPtr = IntPtr.Zero;
        IntPtr xgetbvPtr = IntPtr.Zero;
        try {
            cpuidPtr = VirtualAlloc(IntPtr.Zero, (UIntPtr)CpuIdCode64.Length, 0x3000, 0x40);
            if (cpuidPtr == IntPtr.Zero) return "FAIL";
            Marshal.Copy(CpuIdCode64, 0, cpuidPtr, CpuIdCode64.Length);
            CpuIdDelegate cpuid = (CpuIdDelegate)Marshal.GetDelegateForFunctionPointer(cpuidPtr, typeof(CpuIdDelegate));

            int[] res1 = new int[4];
            cpuid(1, 0, res1);
            bool fma = (res1[2] & (1 << 12)) != 0;
            bool osxsave = (res1[2] & (1 << 27)) != 0;
            bool avx1 = (res1[2] & (1 << 28)) != 0;

            int[] res7 = new int[4];
            cpuid(7, 0, res7);
            bool avx2 = (res7[1] & (1 << 5)) != 0;

            int xcr0Low = 0;
            if (osxsave) {
                xgetbvPtr = VirtualAlloc(IntPtr.Zero, (UIntPtr)XGetBvCode64.Length, 0x3000, 0x40);
                if (xgetbvPtr != IntPtr.Zero) {
                    Marshal.Copy(XGetBvCode64, 0, xgetbvPtr, XGetBvCode64.Length);
                    XGetBvDelegate xgetbv = (XGetBvDelegate)Marshal.GetDelegateForFunctionPointer(xgetbvPtr, typeof(XGetBvDelegate));
                    int[] xcr0 = new int[2];
                    xgetbv(0, xcr0);
                    xcr0Low = xcr0[0];
                }
            }

            return string.Format("AVX1:{0},AVX2:{1},FMA:{2},OSXSAVE:{3},XCR0:{4}", avx1, avx2, fma, osxsave, xcr0Low);
        } catch {
            return "FAIL";
        } finally {
            if (xgetbvPtr != IntPtr.Zero) {
                VirtualFree(xgetbvPtr, UIntPtr.Zero, 0x8000);
            }
            if (cpuidPtr != IntPtr.Zero) {
                VirtualFree(cpuidPtr, UIntPtr.Zero, 0x8000);
            }
        }
    }
}
"@
Add-Type -TypeDefinition $code
[NativeCpuCheck]::Probe()
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
        final out = result.stdout.toString().trim();
        final snapshot = _parseProbeOutput(out);
        return classifyCpuFeatures(snapshot);
      }
    } catch (_) {
      // Fail-closed in caso di errore nell'esecuzione del processore
    }

    return classifyCpuFeatures(NativeCpuCapabilitySnapshot.baseline());
  }

  NativeCpuCapabilitySnapshot _parseProbeOutput(String output) {
    if (output.startsWith('FAIL') || !output.contains('AVX1:')) {
      return NativeCpuCapabilitySnapshot.baseline();
    }
    final parts = Map<String, String>.fromEntries(
      output.split(',').map((p) {
        final kv = p.split(':');
        return MapEntry(kv[0], kv.length > 1 ? kv[1] : '');
      }),
    );

    return NativeCpuCapabilitySnapshot(
      avxBit: parts['AVX1']?.toUpperCase() == 'TRUE',
      avx2Bit: parts['AVX2']?.toUpperCase() == 'TRUE',
      fmaBit: parts['FMA']?.toUpperCase() == 'TRUE',
      osxsaveBit: parts['OSXSAVE']?.toUpperCase() == 'TRUE',
      xcr0Low: int.tryParse(parts['XCR0'] ?? '0') ?? 0,
    );
  }
}
