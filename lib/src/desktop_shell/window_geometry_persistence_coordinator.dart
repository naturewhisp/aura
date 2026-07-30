import 'dart:async';
import 'window_geometry.dart';
import 'window_preferences.dart';
import 'window_preferences_repository.dart';

/// Coordinatore con debounce per la persistenza asincrona della geometria e stato della finestra.
final class WindowGeometryPersistenceCoordinator {
  final WindowPreferencesRepository repository;
  final Duration debounceDuration;

  Timer? _debounceTimer;
  WindowPreferences _currentPreferences;
  bool _isDisposed = false;

  WindowGeometryPersistenceCoordinator({
    required this.repository,
    WindowPreferences initialPreferences = const WindowPreferences(),
    this.debounceDuration = const Duration(milliseconds: 300),
  }) : _currentPreferences = initialPreferences;

  WindowPreferences get currentPreferences => _currentPreferences;

  /// Aggiorna le preferenze in memoria e programma un salvataggio debouced su disco.
  void updatePreferences(WindowPreferences preferences) {
    if (_isDisposed) return;
    _currentPreferences = preferences;
    _scheduleSave();
  }

  /// Registra un cambio di geometria windowed.
  void onGeometryChanged(WindowGeometry geometry) {
    if (_isDisposed) return;
    _currentPreferences = _currentPreferences.copyWith(
      lastWindowedGeometry: geometry,
    );
    _scheduleSave();
  }

  void _scheduleSave() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounceDuration, () {
      _flushInternal();
    });
  }

  /// Forza il salvataggio immediato delle preferenze correnti su disco ed azzera i timer attivi.
  Future<void> flush() async {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    await _flushInternal();
  }

  Future<void> _flushInternal() async {
    if (_isDisposed) return;
    await repository.save(_currentPreferences);
  }

  void dispose() {
    _isDisposed = true;
    _debounceTimer?.cancel();
    _debounceTimer = null;
  }
}
