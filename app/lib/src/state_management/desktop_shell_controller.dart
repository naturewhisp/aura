import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:aura_core/aura_core.dart';
import 'package:aura_app/src/audio/audio_manager.dart';

/// Snapshot osservabile dello stato corrente della shell desktop.
@immutable
final class DesktopShellState {
  final ActiveWindowMode activeMode;
  final WindowStartupMode startupMode;
  final bool focused;
  final bool minimized;
  final DisplayDescriptor? activeDisplay;
  final WindowGeometry? geometry;
  final bool audioDuckingOnUnfocus;
  final bool reduceAnimationsOnUnfocus;
  final bool musicEnabled;
  final bool sfxEnabled;
  final bool reduceGraphicEffects;

  const DesktopShellState({
    this.activeMode = ActiveWindowMode.windowed,
    this.startupMode = WindowStartupMode.restorePrevious,
    this.focused = true,
    this.minimized = false,
    this.activeDisplay,
    this.geometry,
    this.audioDuckingOnUnfocus = true,
    this.reduceAnimationsOnUnfocus = true,
    this.musicEnabled = true,
    this.sfxEnabled = true,
    this.reduceGraphicEffects = false,
  });

  DesktopShellState copyWith({
    ActiveWindowMode? activeMode,
    WindowStartupMode? startupMode,
    bool? focused,
    bool? minimized,
    DisplayDescriptor? activeDisplay,
    WindowGeometry? geometry,
    bool? audioDuckingOnUnfocus,
    bool? reduceAnimationsOnUnfocus,
    bool? musicEnabled,
    bool? sfxEnabled,
    bool? reduceGraphicEffects,
  }) {
    return DesktopShellState(
      activeMode: activeMode ?? this.activeMode,
      startupMode: startupMode ?? this.startupMode,
      focused: focused ?? this.focused,
      minimized: minimized ?? this.minimized,
      activeDisplay: activeDisplay ?? this.activeDisplay,
      geometry: geometry ?? this.geometry,
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
      other is DesktopShellState &&
          runtimeType == other.runtimeType &&
          activeMode == other.activeMode &&
          startupMode == other.startupMode &&
          focused == other.focused &&
          minimized == other.minimized &&
          activeDisplay == other.activeDisplay &&
          geometry == other.geometry &&
          audioDuckingOnUnfocus == other.audioDuckingOnUnfocus &&
          reduceAnimationsOnUnfocus == other.reduceAnimationsOnUnfocus &&
          musicEnabled == other.musicEnabled &&
          sfxEnabled == other.sfxEnabled &&
          reduceGraphicEffects == other.reduceGraphicEffects;

  @override
  int get hashCode => Object.hash(
        activeMode,
        startupMode,
        focused,
        minimized,
        activeDisplay,
        geometry,
        audioDuckingOnUnfocus,
        reduceAnimationsOnUnfocus,
        musicEnabled,
        sfxEnabled,
        reduceGraphicEffects,
      );
}

/// Controller applicativo dello stato della finestra desktop e delle preferenze utente.
class DesktopShellController extends ChangeNotifier {
  final DesktopWindowController windowController;
  final WindowGeometryPersistenceCoordinator persistenceCoordinator;
  final WindowGeometryValidator _geometryValidator;

  StreamSubscription<DesktopWindowEvent>? _eventSub;
  DesktopShellState _state = const DesktopShellState();
  ActiveWindowMode? _preFullscreenMode;
  bool _isInitialized = false;

  DesktopShellController({
    required this.windowController,
    required this.persistenceCoordinator,
    WindowGeometryValidator geometryValidator = const WindowGeometryValidator(),
  }) : _geometryValidator = geometryValidator;

  DesktopShellState get state => _state;
  bool get isInitialized => _isInitialized;

  /// Inizializza il controller caricando le preferenze, applicando la geometria e impostando la modalità iniziale.
  Future<void> initialize() async {
    if (_isInitialized) return;
    await windowController.initialize();

    final prefs = persistenceCoordinator.currentPreferences;
    final displays = await windowController.getDisplays();

    // Valida la geometria salvata risetto ai display correnti
    final validatedGeometry = _geometryValidator.validateAndAdjust(
      saved: prefs.lastWindowedGeometry,
      displays: displays,
    );

    // Determina la modalità iniziale
    final targetMode = switch (prefs.startupMode) {
      WindowStartupMode.restorePrevious => prefs.lastActiveMode,
      WindowStartupMode.windowed => ActiveWindowMode.windowed,
      WindowStartupMode.maximized => ActiveWindowMode.maximized,
      WindowStartupMode.borderlessFullscreen =>
        ActiveWindowMode.borderlessFullscreen,
    };

    _state = DesktopShellState(
      activeMode: targetMode,
      startupMode: prefs.startupMode,
      focused: true,
      minimized: false,
      geometry: validatedGeometry,
      audioDuckingOnUnfocus: prefs.audioDuckingOnUnfocus,
      reduceAnimationsOnUnfocus: prefs.reduceAnimationsOnUnfocus,
      musicEnabled: prefs.musicEnabled,
      sfxEnabled: prefs.sfxEnabled,
      reduceGraphicEffects: prefs.reduceGraphicEffects,
    );

    // Applica le preferenze audio caricati da disco
    await AudioManager().setMusicEnabled(prefs.musicEnabled);
    await AudioManager().setSfxEnabled(prefs.sfxEnabled);

    // Applica geometria e modalità iniziale sulla finestra fisica
    await windowController.setGeometry(validatedGeometry);
    await _applyModeToWindow(targetMode);

    // Ascolta gli eventi del controller nativo della finestra
    _eventSub = windowController.events.listen(_handleWindowEvent);

    _isInitialized = true;
    notifyListeners();
  }

  Future<void> _applyModeToWindow(ActiveWindowMode mode) async {
    switch (mode) {
      case ActiveWindowMode.windowed:
        await windowController.setWindowed();
        break;
      case ActiveWindowMode.maximized:
        await windowController.maximize();
        break;
      case ActiveWindowMode.borderlessFullscreen:
        await windowController.enterBorderlessFullscreen();
        break;
    }
  }

  void _handleWindowEvent(DesktopWindowEvent event) {
    switch (event) {
      case DesktopWindowModeChanged(:final mode):
        _onModeChangedFromNative(mode);
        break;
      case DesktopWindowMovedResized(:final geometry):
        _onGeometryChangedFromNative(geometry);
        break;
      case DesktopWindowFocusChanged(:final focused):
        _state = _state.copyWith(focused: focused);
        notifyListeners();
        break;
      case DesktopWindowMinimizeChanged(:final minimized):
        _state = _state.copyWith(minimized: minimized);
        notifyListeners();
        break;
      case DesktopWindowCloseRequested():
        // Gli eventi di chiusura sono gestiti da ApplicationShutdownCoordinator
        break;
    }
  }

  void _onModeChangedFromNative(ActiveWindowMode mode) {
    if (_state.activeMode == mode) return;
    _state = _state.copyWith(activeMode: mode);

    // Persiste lastActiveMode aggiornato
    persistenceCoordinator.updatePreferences(
      persistenceCoordinator.currentPreferences.copyWith(
        lastActiveMode: mode,
      ),
    );

    notifyListeners();
  }

  void _onGeometryChangedFromNative(WindowGeometry geometry) {
    // La geometria windowed viene salvata solo quando la finestra è in modalità windowed.
    // Il resize mentre è massimizzata o in fullscreen non deve sovrascrivere la lastWindowedGeometry!
    if (_state.activeMode == ActiveWindowMode.windowed) {
      _state = _state.copyWith(geometry: geometry);
      persistenceCoordinator.onGeometryChanged(geometry);
      notifyListeners();
    }
  }

  bool _isTransitioning = false;

  Future<void> setWindowed() async {
    if (_isTransitioning) return;
    _isTransitioning = true;
    try {
      _preFullscreenMode = null;
      await windowController.setWindowed();
      _state = _state.copyWith(activeMode: ActiveWindowMode.windowed);
      persistenceCoordinator.updatePreferences(
        persistenceCoordinator.currentPreferences.copyWith(
          lastActiveMode: ActiveWindowMode.windowed,
        ),
      );
      notifyListeners();
    } finally {
      _isTransitioning = false;
    }
  }

  Future<void> maximize() async {
    if (_isTransitioning) return;
    _isTransitioning = true;
    try {
      _preFullscreenMode = null;
      await windowController.maximize();
      _state = _state.copyWith(activeMode: ActiveWindowMode.maximized);
      persistenceCoordinator.updatePreferences(
        persistenceCoordinator.currentPreferences.copyWith(
          lastActiveMode: ActiveWindowMode.maximized,
        ),
      );
      notifyListeners();
    } finally {
      _isTransitioning = false;
    }
  }

  Future<void> enterBorderlessFullscreen() async {
    if (_isTransitioning) return;
    _isTransitioning = true;
    try {
      if (_state.activeMode != ActiveWindowMode.borderlessFullscreen) {
        _preFullscreenMode = _state.activeMode;
      }
      await windowController.enterBorderlessFullscreen();
      _state =
          _state.copyWith(activeMode: ActiveWindowMode.borderlessFullscreen);
      persistenceCoordinator.updatePreferences(
        persistenceCoordinator.currentPreferences.copyWith(
          lastActiveMode: ActiveWindowMode.borderlessFullscreen,
        ),
      );
      notifyListeners();
    } finally {
      _isTransitioning = false;
    }
  }

  Future<void> exitBorderlessFullscreen() async {
    if (_isTransitioning) return;
    if (_state.activeMode != ActiveWindowMode.borderlessFullscreen) return;

    _isTransitioning = true;
    try {
      final targetMode = _preFullscreenMode ?? ActiveWindowMode.windowed;
      _preFullscreenMode = null;

      if (targetMode == ActiveWindowMode.maximized) {
        await windowController.maximize();
        _state = _state.copyWith(activeMode: ActiveWindowMode.maximized);
      } else {
        await windowController.setWindowed();
        _state = _state.copyWith(activeMode: ActiveWindowMode.windowed);
        if (_state.geometry != null) {
          await windowController.setGeometry(_state.geometry!);
        }
      }
      persistenceCoordinator.updatePreferences(
        persistenceCoordinator.currentPreferences.copyWith(
          lastActiveMode: _state.activeMode,
        ),
      );
      notifyListeners();
    } finally {
      _isTransitioning = false;
    }
  }

  Future<void> toggleBorderlessFullscreen() async {
    if (_isTransitioning) return;
    if (_state.activeMode == ActiveWindowMode.borderlessFullscreen) {
      await exitBorderlessFullscreen();
    } else {
      await enterBorderlessFullscreen();
    }
  }

  void setStartupMode(WindowStartupMode mode) {
    if (_state.startupMode == mode) return;
    _state = _state.copyWith(startupMode: mode);
    persistenceCoordinator.updatePreferences(
      persistenceCoordinator.currentPreferences.copyWith(startupMode: mode),
    );
    notifyListeners();
  }

  void setAudioDuckingOnUnfocus(bool enable) {
    if (_state.audioDuckingOnUnfocus == enable) return;
    _state = _state.copyWith(audioDuckingOnUnfocus: enable);
    persistenceCoordinator.updatePreferences(
      persistenceCoordinator.currentPreferences
          .copyWith(audioDuckingOnUnfocus: enable),
    );
    notifyListeners();
  }

  void setReduceAnimationsOnUnfocus(bool enable) {
    if (_state.reduceAnimationsOnUnfocus == enable) return;
    _state = _state.copyWith(reduceAnimationsOnUnfocus: enable);
    persistenceCoordinator.updatePreferences(
      persistenceCoordinator.currentPreferences
          .copyWith(reduceAnimationsOnUnfocus: enable),
    );
    notifyListeners();
  }

  void setMusicEnabled(bool enable) {
    if (_state.musicEnabled == enable) return;
    _state = _state.copyWith(musicEnabled: enable);
    persistenceCoordinator.updatePreferences(
      persistenceCoordinator.currentPreferences.copyWith(musicEnabled: enable),
    );
    AudioManager().setMusicEnabled(enable);
    notifyListeners();
  }

  void setSfxEnabled(bool enable) {
    if (_state.sfxEnabled == enable) return;
    _state = _state.copyWith(sfxEnabled: enable);
    persistenceCoordinator.updatePreferences(
      persistenceCoordinator.currentPreferences.copyWith(sfxEnabled: enable),
    );
    AudioManager().setSfxEnabled(enable);
    notifyListeners();
  }

  void setReduceGraphicEffects(bool enable) {
    if (_state.reduceGraphicEffects == enable) return;
    _state = _state.copyWith(reduceGraphicEffects: enable);
    persistenceCoordinator.updatePreferences(
      persistenceCoordinator.currentPreferences
          .copyWith(reduceGraphicEffects: enable),
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _eventSub = null;
    super.dispose();
  }
}
