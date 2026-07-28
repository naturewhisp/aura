import 'dart:io';

/// Sistemi operativi supportati per la risoluzione portabile dei percorsi.
enum AuraOperatingSystem {
  windows,
  linux,
  macOS,
}

/// Contesto di risoluzione portabile dei percorsi dell'applicazione A.U.R.A.
final class AuraCliEnvironment {
  final String appManagedRoot;
  final String bundledRoot;

  const AuraCliEnvironment({
    required this.appManagedRoot,
    required this.bundledRoot,
  });

  /// Risolve i percorsi di produzione dinamici per il sistema operativo specificato o corrente.
  factory AuraCliEnvironment.fromPlatform({
    Map<String, String>? environment,
    List<String>? cliArgs,
    AuraOperatingSystem? targetOS,
  }) {
    final env = environment ?? Platform.environment;
    final os = targetOS ?? _currentPlatform();

    // 1. Controllo override tramite flag CLI --data-root=<path>
    if (cliArgs != null) {
      for (final arg in cliArgs) {
        if (arg.startsWith('--data-root=')) {
          final customRoot = arg.substring('--data-root='.length).trim();
          if (customRoot.isNotEmpty) {
            return AuraCliEnvironment(
              appManagedRoot: customRoot,
              bundledRoot: _defaultBundledRoot(env, os),
            );
          }
        }
      }
    }

    // 2. Controllo override tramite variabile d'ambiente AURA_DATA_ROOT
    final envOverride = env['AURA_DATA_ROOT']?.trim();
    if (envOverride != null && envOverride.isNotEmpty) {
      return AuraCliEnvironment(
        appManagedRoot: envOverride,
        bundledRoot: _defaultBundledRoot(env, os),
      );
    }

    // 3. Risoluzione portabile platform-aware
    return AuraCliEnvironment(
      appManagedRoot: _defaultAppManagedRoot(env, os),
      bundledRoot: _defaultBundledRoot(env, os),
    );
  }

  static AuraOperatingSystem _currentPlatform() {
    if (Platform.isWindows) return AuraOperatingSystem.windows;
    if (Platform.isMacOS) return AuraOperatingSystem.macOS;
    return AuraOperatingSystem.linux;
  }

  static String _defaultAppManagedRoot(
    Map<String, String> env,
    AuraOperatingSystem os,
  ) {
    switch (os) {
      case AuraOperatingSystem.windows:
        final appData = env['APPDATA'] ?? env['LOCALAPPDATA'];
        if (appData != null && appData.isNotEmpty) {
          return '$appData\\AURA\\models';
        }
        final userProfile = env['USERPROFILE'];
        if (userProfile != null && userProfile.isNotEmpty) {
          return '$userProfile\\.aura\\models';
        }
        return r'C:\AURA\models';

      case AuraOperatingSystem.macOS:
        final home = env['HOME'];
        if (home != null && home.isNotEmpty) {
          return '$home/Library/Application Support/AURA/models';
        }
        return '/tmp/aura/models';

      case AuraOperatingSystem.linux:
        final xdgData = env['XDG_DATA_HOME'];
        if (xdgData != null && xdgData.isNotEmpty) {
          return '$xdgData/aura/models';
        }
        final home = env['HOME'];
        if (home != null && home.isNotEmpty) {
          return '$home/.local/share/aura/models';
        }
        return '/tmp/aura/models';
    }
  }

  static String _defaultBundledRoot(
    Map<String, String> env,
    AuraOperatingSystem os,
  ) {
    switch (os) {
      case AuraOperatingSystem.windows:
        final programFiles = env['ProgramFiles'];
        if (programFiles != null && programFiles.isNotEmpty) {
          return '$programFiles\\AURA';
        }
        return r'C:\Program Files\AURA';

      case AuraOperatingSystem.macOS:
      case AuraOperatingSystem.linux:
        return '/usr/local/share/aura';
    }
  }
}
