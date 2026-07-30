import 'package:meta/meta.dart';
import 'window_geometry.dart';
import 'window_mode.dart';

/// Preferenze immutabili per il comportamento e la geometria della finestra desktop.
@immutable
final class WindowPreferences {
  static const int currentSchemaVersion = 1;

  final int schemaVersion;
  final WindowStartupMode startupMode;
  final ActiveWindowMode lastActiveMode;
  final WindowGeometry? lastWindowedGeometry;
  final bool audioDuckingOnUnfocus;
  final bool reduceAnimationsOnUnfocus;
  final bool musicEnabled;
  final bool sfxEnabled;
  final bool reduceGraphicEffects;

  const WindowPreferences({
    this.schemaVersion = currentSchemaVersion,
    this.startupMode = WindowStartupMode.restorePrevious,
    this.lastActiveMode = ActiveWindowMode.windowed,
    this.lastWindowedGeometry,
    this.audioDuckingOnUnfocus = true,
    this.reduceAnimationsOnUnfocus = true,
    this.musicEnabled = true,
    this.sfxEnabled = true,
    this.reduceGraphicEffects = false,
  });

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'startupMode': startupMode.name,
        'lastActiveMode': lastActiveMode.name,
        if (lastWindowedGeometry != null)
          'lastWindowedGeometry': lastWindowedGeometry!.toJson(),
        'audioDuckingOnUnfocus': audioDuckingOnUnfocus,
        'reduceAnimationsOnUnfocus': reduceAnimationsOnUnfocus,
        'musicEnabled': musicEnabled,
        'sfxEnabled': sfxEnabled,
        'reduceGraphicEffects': reduceGraphicEffects,
      };

  factory WindowPreferences.fromJson(Map<String, dynamic> json) {
    final rawStartup = json['startupMode'] as String?;
    final startupMode = WindowStartupMode.values.firstWhere(
      (e) => e.name == rawStartup,
      orElse: () => WindowStartupMode.restorePrevious,
    );

    final rawActive = json['lastActiveMode'] as String?;
    final lastActiveMode = ActiveWindowMode.values.firstWhere(
      (e) => e.name == rawActive,
      orElse: () => ActiveWindowMode.windowed,
    );

    WindowGeometry? geometry;
    if (json['lastWindowedGeometry'] is Map<String, dynamic>) {
      try {
        geometry = WindowGeometry.fromJson(
          json['lastWindowedGeometry'] as Map<String, dynamic>,
        );
      } catch (_) {
        geometry = null;
      }
    }

    final rawSchema = json['schemaVersion'];
    final schemaVersion = (rawSchema is num) ? rawSchema.toInt() : 1;

    return WindowPreferences(
      schemaVersion: schemaVersion,
      startupMode: startupMode,
      lastActiveMode: lastActiveMode,
      lastWindowedGeometry: geometry,
      audioDuckingOnUnfocus: json['audioDuckingOnUnfocus'] as bool? ?? true,
      reduceAnimationsOnUnfocus:
          json['reduceAnimationsOnUnfocus'] as bool? ?? true,
      musicEnabled: json['musicEnabled'] as bool? ?? true,
      sfxEnabled: json['sfxEnabled'] as bool? ?? true,
      reduceGraphicEffects: json['reduceGraphicEffects'] as bool? ?? false,
    );
  }

  WindowPreferences copyWith({
    int? schemaVersion,
    WindowStartupMode? startupMode,
    ActiveWindowMode? lastActiveMode,
    WindowGeometry? lastWindowedGeometry,
    bool? audioDuckingOnUnfocus,
    bool? reduceAnimationsOnUnfocus,
    bool? musicEnabled,
    bool? sfxEnabled,
    bool? reduceGraphicEffects,
  }) {
    return WindowPreferences(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      startupMode: startupMode ?? this.startupMode,
      lastActiveMode: lastActiveMode ?? this.lastActiveMode,
      lastWindowedGeometry: lastWindowedGeometry ?? this.lastWindowedGeometry,
      audioDuckingOnUnfocus:
          audioDuckingOnUnfocus ?? this.audioDuckingOnUnfocus,
      reduceAnimationsOnUnfocus:
          reduceAnimationsOnUnfocus ?? this.reduceAnimationsOnUnfocus,
      musicEnabled: musicEnabled ?? this.musicEnabled,
      sfxEnabled: sfxEnabled ?? this.sfxEnabled,
      reduceGraphicEffects: reduceGraphicEffects ?? this.reduceGraphicEffects,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WindowPreferences &&
          runtimeType == other.runtimeType &&
          schemaVersion == other.schemaVersion &&
          startupMode == other.startupMode &&
          lastActiveMode == other.lastActiveMode &&
          lastWindowedGeometry == other.lastWindowedGeometry &&
          audioDuckingOnUnfocus == other.audioDuckingOnUnfocus &&
          reduceAnimationsOnUnfocus == other.reduceAnimationsOnUnfocus &&
          musicEnabled == other.musicEnabled &&
          sfxEnabled == other.sfxEnabled &&
          reduceGraphicEffects == other.reduceGraphicEffects;

  @override
  int get hashCode => Object.hash(
        schemaVersion,
        startupMode,
        lastActiveMode,
        lastWindowedGeometry,
        audioDuckingOnUnfocus,
        reduceAnimationsOnUnfocus,
        musicEnabled,
        sfxEnabled,
        reduceGraphicEffects,
      );
}
