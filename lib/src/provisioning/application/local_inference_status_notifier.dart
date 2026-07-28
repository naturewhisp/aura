import 'dart:async';

import 'local_inference_facade.dart';
import 'local_inference_models.dart';

/// Listener per la notifica dei cambiamenti dello stato dell'inferenza locale.
typedef LocalInferenceStateListener = void Function(
    LocalInferenceSnapshot snapshot);

/// Notifier puro Dart per lo stato dell'inferenza locale (zero dipendenze da Flutter).
///
/// Protegge da corse critiche concorrenti out-of-order tramite token di sequenza monotono.
final class LocalInferenceStatusNotifier {
  final LocalInferenceFacade _facade;
  final List<LocalInferenceStateListener> _listeners;
  LocalInferenceSnapshot? _currentSnapshot;
  int _latestOperationSequence;

  LocalInferenceStatusNotifier({
    required LocalInferenceFacade facade,
  })  : _facade = facade,
        _listeners = [],
        _latestOperationSequence = 0;

  /// Snapshot corrente dello stato. Restituisce `null` se non ancora aggiornato.
  LocalInferenceSnapshot? get snapshot => _currentSnapshot;

  /// Registra un nuovo listener per ricevere aggiornamenti sullo stato.
  void addListener(LocalInferenceStateListener listener) {
    _listeners.add(listener);
  }

  /// Rimuove un listener registrato.
  void removeListener(LocalInferenceStateListener listener) {
    _listeners.remove(listener);
  }

  /// Aggiorna programmaticamente lo snapshot interrogando la facade in modo thread-safe.
  Future<LocalInferenceSnapshot> refresh() async {
    final opId = ++_latestOperationSequence;
    final newSnapshot = await _facade.getSnapshot();

    // Aggiorna lo stato e notifica i listener solo se l'operazione è l'ultima richiesta
    if (opId == _latestOperationSequence) {
      _currentSnapshot = newSnapshot;
      _notifyListeners(newSnapshot);
    }

    return newSnapshot;
  }

  void _notifyListeners(LocalInferenceSnapshot snapshot) {
    for (final listener in List.of(_listeners)) {
      try {
        listener(snapshot);
      } catch (_) {}
    }
  }
}
