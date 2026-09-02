import 'dart:io';

/// Sistemi operativi supportati per la risoluzione portabile dei percorsi.
enum AuraOperatingSystem {
  windows,
  linux,
  macOS,
}

/// Modello immutabile che racchiude il percorso canonico e i percorsi legacy candidati dello store.
final class AppManagedStoreCandidates {
  /// Percorso canonico dello store (%LOCALAPPDATA%\AURA\store su Windows).
  final String canonical;

  /// Percorsi legacy alternativi (%APPDATA%\AURA\models su Windows) per retrocompatibilità.
  final List<String> legacy;

  const AppManagedStoreCandidates({
    required this.canonical,
    this.legacy = const [],
  });
}

/// Contesto di risoluzione portabile dei percorsi dell'applicazione A.U.R.A.
final class AuraCliEnvironment {
  final String appManagedRoot;
  final String bundledRoot;
  final AppManagedStoreCandidates? candidates;

  const AuraCliEnvironment({
    required this.appManagedRoot,
    required this.bundledRoot,
    this.candidates,
  });

  /// Risolve i percorsi di produzione dinamici per il sistema operativo specificato o corrente.
  ///
  /// Precedenza risoluzione [bundledRoot]:
  /// 1. Iniezione/override esplicito ([explicitBundledRoot] o flag CLI `--bundled-root=<path>`);
  /// 2. Variabile d'ambiente [AURA_BUNDLED_ROOT];
  /// 3. Fallback legacy per ambienti non-desktop/CLI ([_defaultBundledRoot]).
  ///
  /// Precedenza risoluzione [appManagedRoot]:
  /// 1. Override esplicito ([explicitAppManagedRoot] o flag CLI `--data-root=<path>`);
  /// 2. Variabile d'ambiente [AURA_DATA_ROOT] o [AURA_APP_MANAGED_ROOT];
  /// 3. Percorso canonico platform-aware derivato da [computeStoreCandidates].
  factory AuraCliEnvironment.fromPlatform({
    Map<String, String>? environment,
    List<String>? cliArgs,
    AuraOperatingSystem? targetOS,
    String? explicitBundledRoot,
    String? explicitAppManagedRoot,
  }) {
    final env = environment ?? Platform.environment;
    final os = targetOS ?? _currentPlatform();

    // 1. Risoluzione bundledRoot
    String? resolvedBundled = explicitBundledRoot?.trim();
    if (resolvedBundled == null || resolvedBundled.isEmpty) {
      if (cliArgs != null) {
        for (final arg in cliArgs) {
          if (arg.startsWith('--bundled-root=')) {
            final customBundled =
                arg.substring('--bundled-root='.length).trim();
            if (customBundled.isNotEmpty) {
              resolvedBundled = customBundled;
              break;
            }
          }
        }
      }
    }

    if (resolvedBundled == null || resolvedBundled.isEmpty) {
      final envBundled = env['AURA_BUNDLED_ROOT']?.trim();
      if (envBundled != null && envBundled.isNotEmpty) {
        resolvedBundled = envBundled;
      }
    }

    resolvedBundled ??= _defaultBundledRoot(env, os);

    // 2. Risoluzione appManagedRoot
    final storeCandidates = computeStoreCandidates(env: env, os: os);

    String? resolvedAppManaged = explicitAppManagedRoot?.trim();
    if (resolvedAppManaged == null || resolvedAppManaged.isEmpty) {
      if (cliArgs != null) {
        for (final arg in cliArgs) {
          if (arg.startsWith('--data-root=')) {
            final customRoot = arg.substring('--data-root='.length).trim();
            if (customRoot.isNotEmpty) {
              resolvedAppManaged = customRoot;
              break;
            }
          }
        }
      }
    }

    if (resolvedAppManaged == null || resolvedAppManaged.isEmpty) {
      final envOverride =
          env['AURA_DATA_ROOT']?.trim() ?? env['AURA_APP_MANAGED_ROOT']?.trim();
      if (envOverride != null && envOverride.isNotEmpty) {
        resolvedAppManaged = envOverride;
      }
    }

    resolvedAppManaged ??= storeCandidates.canonical;

    return AuraCliEnvironment(
      appManagedRoot: resolvedAppManaged,
      bundledRoot: resolvedBundled,
      candidates: storeCandidates,
    );
  }

  /// Calcola i candidati canonico e legacy dello store gestito senza interagire con il filesystem.
  static AppManagedStoreCandidates computeStoreCandidates({
    Map<String, String>? env,
    AuraOperatingSystem? os,
  }) {
    final environment = env ?? Platform.environment;
    final operatingSystem = os ?? _currentPlatform();

    switch (operatingSystem) {
      case AuraOperatingSystem.windows:
        final localAppData = environment['LOCALAPPDATA'];
        final appData = environment['APPDATA'];
        final userProfile = environment['USERPROFILE'];

        final String canonical;
        if (localAppData != null && localAppData.isNotEmpty) {
          canonical = '$localAppData\\AURA\\store';
        } else if (appData != null && appData.isNotEmpty) {
          canonical = '$appData\\AURA\\store';
        } else if (userProfile != null && userProfile.isNotEmpty) {
          canonical = '$userProfile\\.aura\\store';
        } else {
          canonical = r'C:\AURA\store';
        }

        final legacy = <String>[
          if (appData != null && appData.isNotEmpty) '$appData\\AURA\\models',
          if (localAppData != null && localAppData.isNotEmpty)
            '$localAppData\\AURA\\models',
          if (userProfile != null && userProfile.isNotEmpty)
            '$userProfile\\.aura\\models',
          r'C:\AURA\models',
        ];

        return AppManagedStoreCandidates(
          canonical: canonical,
          legacy: legacy,
        );

      case AuraOperatingSystem.macOS:
        final home = environment['HOME'];
        final canonical = (home != null && home.isNotEmpty)
            ? '$home/Library/Application Support/AURA/store'
            : '/tmp/aura/store';
        final legacy = [
          if (home != null && home.isNotEmpty)
            '$home/Library/Application Support/AURA/models',
          '/tmp/aura/models',
        ];
        return AppManagedStoreCandidates(
          canonical: canonical,
          legacy: legacy,
        );

      case AuraOperatingSystem.linux:
        final xdgData = environment['XDG_DATA_HOME'];
        final home = environment['HOME'];
        final String canonical;
        if (xdgData != null && xdgData.isNotEmpty) {
          canonical = '$xdgData/aura/store';
        } else if (home != null && home.isNotEmpty) {
          canonical = '$home/.local/share/aura/store';
        } else {
          canonical = '/tmp/aura/store';
        }
        final legacy = [
          if (xdgData != null && xdgData.isNotEmpty) '$xdgData/aura/models',
          if (home != null && home.isNotEmpty) '$home/.local/share/aura/models',
          '/tmp/aura/models',
        ];
        return AppManagedStoreCandidates(
          canonical: canonical,
          legacy: legacy,
        );
    }
  }

  static AuraOperatingSystem _currentPlatform() {
    if (Platform.isWindows) return AuraOperatingSystem.windows;
    if (Platform.isMacOS) return AuraOperatingSystem.macOS;
    return AuraOperatingSystem.linux;
  }

  static String _defaultBundledRoot(
    Map<String, String> env,
    AuraOperatingSystem os,
  ) {
    switch (os) {
      case AuraOperatingSystem.windows:
        final localAppData = env['LOCALAPPDATA'];
        if (localAppData != null && localAppData.isNotEmpty) {
          return '$localAppData\\Programs\\AURA';
        }
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
