import 'dart:async';
import 'package:meta/meta.dart';
import '../domain/provisioning_options.dart';

/// Contratto astratto per il lock e la serializzazione delle operazioni di provisioning.
@immutable
abstract interface class ProvisioningLock {
  /// Esegue l'azione specificata serializzando l'accesso per la chiave fornita.
  Future<T> synchronized<T>(
    String key,
    Future<T> Function() action,
  );
}

/// Implementazione in-memory basata su accodamento asincrono deterministico per chiave.
final class InMemoryProvisioningLock implements ProvisioningLock {
  final Map<String, Future<dynamic>> _keyLocks;

  InMemoryProvisioningLock() : _keyLocks = {};

  @override
  Future<T> synchronized<T>(
    String key,
    Future<T> Function() action,
  ) async {
    final cleanKey = key.trim().toLowerCase();
    if (cleanKey.isEmpty) {
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.installationConflict,
        message: 'La chiave di lock non può essere vuota.',
      );
    }

    final previousLock = _keyLocks[cleanKey];
    final completer = Completer<void>();
    _keyLocks[cleanKey] = completer.future;

    if (previousLock != null) {
      try {
        await previousLock;
      } catch (_) {}
    }

    try {
      return await action();
    } finally {
      completer.complete();
      if (identical(_keyLocks[cleanKey], completer.future)) {
        _keyLocks.remove(cleanKey);
      }
    }
  }
}
