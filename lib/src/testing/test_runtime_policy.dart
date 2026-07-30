/// Defines execution policies for test runtimes in A.U.R.A.
enum TestRuntimePolicy {
  /// Standard test profile (default for `dart test` and `flutter test`).
  /// Completely offline: no native processes, no external network calls, no downloads, no real GGUF models.
  neverNative,

  /// Diagnostic native smoke test profile.
  /// Allows executing local `llama-server.exe` on loopback (127.0.0.1) with a minimal test model.
  /// External network access and remote downloads are strictly prohibited.
  nativeSmoke,

  /// Integration test profile with real installed models.
  /// Allows executing local `llama-server.exe` on loopback (127.0.0.1) using pre-installed GGUF models.
  /// External network access and remote downloads are strictly prohibited.
  requireInstalledModels;

  /// Whether native process launcher execution is permitted under this policy.
  bool get allowsNativeProcesses =>
      this == nativeSmoke || this == requireInstalledModels;

  /// Whether local loopback (127.0.0.1) network connections are permitted.
  bool get allowsLocalhost =>
      this == nativeSmoke || this == requireInstalledModels;

  /// Whether external (non-loopback) internet access is permitted (Always false in A.U.R.A. tests).
  bool get allowsExternalNetwork => false;

  /// Whether remote artifact downloads are permitted (Always false in A.U.R.A. tests).
  bool get allowsDownloads => false;

  /// Whether pre-installed real production models can be loaded.
  bool get allowsInstalledModels => this == requireInstalledModels;
}
