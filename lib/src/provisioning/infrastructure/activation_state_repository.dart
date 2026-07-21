import 'dart:async';
import 'dart:convert';
import '../domain/activation_state.dart';
import '../domain/provisioning_clock.dart';
import '../domain/provisioning_options.dart';
import 'provisioning_file_system.dart';
import 'provisioning_io_exception.dart';
import 'provisioning_lock.dart';
import 'provisioning_path_resolver.dart';

/// Contratto astratto I/O per la lettura e scrittura transazionale dell'ActivationState.
abstract class ActivationStateRepository {
  /// Legge l'ActivationState memorizzato sul filesystem.
  /// Se il file non esiste ancora, restituisce un [ActivationState.empty].
  Future<ActivationState> readState();

  /// Scrive l'ActivationState sul filesystem.
  Future<void> writeState(ActivationState state);

  /// Esegue un'operazione atomica serializzata read-modify-write per evitare lost update.
  Future<ActivationState> updateState(
    FutureOr<ActivationState> Function(ActivationState current) transform,
  );
}

/// Implementazione concreta basata su [ProvisioningFileSystem] ed isolata da I/O diretto.
final class JsonActivationStateRepository implements ActivationStateRepository {
  static const String _lockKey = 'active_state';

  final ProvisioningPathResolver _pathResolver;
  final ProvisioningFileSystem _fileSystem;
  final ProvisioningClock _clock;
  final ProvisioningLock _lock;

  JsonActivationStateRepository({
    required ProvisioningPathResolver pathResolver,
    ProvisioningFileSystem fileSystem = const LocalProvisioningFileSystem(),
    ProvisioningClock clock = const SystemProvisioningClock(),
    ProvisioningLock? lock,
  })  : _pathResolver = pathResolver,
        _fileSystem = fileSystem,
        _clock = clock,
        _lock = lock ?? InMemoryProvisioningLock();

  @override
  Future<ActivationState> readState() async {
    return _lock.synchronized(_lockKey, () async {
      return _internalReadState();
    });
  }

  Future<ActivationState> _internalReadState() async {
    final statePath = _pathResolver.activeStatePath;
    final backupPath = '$statePath.bak';

    if (!await _fileSystem.fileExists(statePath)) {
      if (await _fileSystem.fileExists(backupPath)) {
        return _tryRecoverFromBackup(backupPath);
      }
      return ActivationState.empty(
        updatedAt: _clock.nowUtc().toIso8601String(),
      );
    }

    try {
      final content = await _fileSystem.readAsString(statePath);
      if (content.trim().isEmpty) {
        // File vuoto: corruzione o truncate accidentale -> tenta recovery da .bak
        return _tryRecoverFromBackup(backupPath);
      }

      final jsonMap = jsonDecode(content);
      if (jsonMap is! Map<String, dynamic>) {
        return _tryRecoverFromBackup(backupPath);
      }
      return ActivationState.fromJson(jsonMap);
    } on ProvisioningException catch (e) {
      if (e.reason == ProvisioningFailureReason.unsupportedSchemaVersion) {
        // Schema non supportato: NON sovrascrivere o fare recovery da .bak
        rethrow;
      }
      return _tryRecoverFromBackup(backupPath);
    } on FormatException {
      return _tryRecoverFromBackup(backupPath);
    } on ProvisioningIoException {
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.activationStateReadFailed,
        message: 'Impossibile accedere al file active_state sul filesystem.',
      );
    } catch (_) {
      return _tryRecoverFromBackup(backupPath);
    }
  }

  Future<ActivationState> _tryRecoverFromBackup(String backupPath) async {
    if (!await _fileSystem.fileExists(backupPath)) {
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.activationStateReadFailed,
        message: 'File active_state corrotto ed introvabile backup valido.',
      );
    }

    try {
      final content = await _fileSystem.readAsString(backupPath);
      if (content.trim().isEmpty) {
        throw const ProvisioningException(
          reason: ProvisioningFailureReason.activationStateReadFailed,
          message: 'Anche il file di backup .bak risulta vuoto o corrotto.',
        );
      }

      final jsonMap = jsonDecode(content);
      if (jsonMap is! Map<String, dynamic>) {
        throw const ProvisioningException(
          reason: ProvisioningFailureReason.activationStateReadFailed,
          message: 'Struttura JSON non valida nel file di backup .bak.',
        );
      }

      final recovered = ActivationState.fromJson(jsonMap);

      // Ripristina il file primario senza distruggere il file di backup valido
      await _fileSystem.restoreFromBackup(
        _pathResolver.activeStatePath,
        backupPath,
      );
      return recovered;
    } on ProvisioningException {
      rethrow;
    } catch (_) {
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.activationStateReadFailed,
        message: 'Recovery da backup .bak dell\'active_state fallito.',
      );
    }
  }

  @override
  Future<void> writeState(ActivationState state) async {
    await _lock.synchronized(_lockKey, () async {
      await _internalWriteState(state);
    });
  }

  Future<void> _internalWriteState(ActivationState state) async {
    try {
      final updatedState = state.copyWith(
        updatedAt: _clock.nowUtc().toIso8601String(),
      );
      final jsonStr =
          const JsonEncoder.withIndent('  ').convert(updatedState.toJson());
      await _fileSystem.writeStringRecoverably(
        _pathResolver.activeStatePath,
        jsonStr,
      );
    } on ProvisioningException {
      rethrow;
    } on ProvisioningIoException {
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.activationStateWriteFailed,
        message: 'Scrittura del file active_state fallita.',
      );
    } catch (_) {
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.activationStateWriteFailed,
        message: 'Scrittura dell\'activation state fallita.',
      );
    }
  }

  @override
  Future<ActivationState> updateState(
    FutureOr<ActivationState> Function(ActivationState current) transform,
  ) async {
    return _lock.synchronized(_lockKey, () async {
      final current = await _internalReadState();
      final updated = await transform(current);
      await _internalWriteState(updated);
      return updated;
    });
  }
}
