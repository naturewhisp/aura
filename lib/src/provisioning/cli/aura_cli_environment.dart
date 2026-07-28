import 'dart:io';

/// Contesto di risoluzione portabile dei percorsi dell'applicazione A.U.R.A.
final class AuraCliEnvironment {
  final String appManagedRoot;
  final String bundledRoot;

  const AuraCliEnvironment({
    required this.appManagedRoot,
    required this.bundledRoot,
  });

  /// Risolve i percorsi di produzione dinamici per il sistema operativo corrente.
  factory AuraCliEnvironment.fromPlatform({
    Map<String, String>? environment,
    List<String>? cliArgs,
  }) {
    final env = environment ?? Platform.environment;

    // 1. Controllo override tramite flag CLI --data-root=<path>
    if (cliArgs != null) {
      for (final arg in cliArgs) {
        if (arg.startsWith('--data-root=')) {
          final customRoot = arg.substring('--data-root='.length).trim();
          if (customRoot.isNotEmpty) {
            return AuraCliEnvironment(
              appManagedRoot: customRoot,
              bundledRoot: _defaultBundledRoot(env),
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
        bundledRoot: _defaultBundledRoot(env),
      );
    }

    // 3. Risoluzione portabile platform-aware
    return AuraCliEnvironment(
      appManagedRoot: _defaultAppManagedRoot(env),
      bundledRoot: _defaultBundledRoot(env),
    );
  }

  static String _defaultAppManagedRoot(Map<String, String> env) {
    if (Platform.isWindows) {
      final appData = env['APPDATA'] ?? env['LOCALAPPDATA'];
      if (appData != null && appData.isNotEmpty) {
        return '$appData\\AURA\\models';
      }
      final userProfile = env['USERPROFILE'];
      if (userProfile != null && userProfile.isNotEmpty) {
        return '$userProfile\\.aura\\models';
      }
      return r'C:\AURA\models';
    } else if (Platform.isMacOS) {
      final home = env['HOME'];
      if (home != null && home.isNotEmpty) {
        return '$home/Library/Application Support/AURA/models';
      }
      return '/tmp/aura/models';
    } else {
      // Linux / Unix / POSIX (XDG Data Home)
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

  static String _defaultBundledRoot(Map<String, String> env) {
    if (Platform.isWindows) {
      final programFiles = env['ProgramFiles'];
      if (programFiles != null && programFiles.isNotEmpty) {
        return '$programFiles\\AURA';
      }
      return r'C:\Program Files\AURA';
    } else {
      return '/usr/local/share/aura';
    }
  }
}
