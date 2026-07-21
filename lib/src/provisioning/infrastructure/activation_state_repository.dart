import 'dart:convert';
import '../domain/activation_state.dart';
import '../domain/provisioning_clock.dart';
import '../domain/provisioning_options.dart';
import 'provisioning_file_system.dart';
import 'provisioning_path_resolver.dart';

/// Contratto astratto I/O per la lettura e scrittura dell'ActivationState.
abstract class ActivationStateRepository {
  /// Legge l'ActivationState memorizzato sul filesystem.
  /// Se il file non esiste ancora, restituisce un [ActivationState.empty].
  Future<ActivationState> readState();

  /// Scrive atomicamente l'ActivationState sul filesystem.
  Future<void> writeState(ActivationState state);
}

/// Implementazione concreta basata su [ProvisioningFileSystem] ed isolata da I/O diretto.
final class JsonActivationStateRepository implements ActivationStateRepository {
  final ProvisioningPathResolver _pathResolver;
  final ProvisioningFileSystem _fileSystem;
  final ProvisioningClock _clock;

  JsonActivationStateRepository({
    required ProvisioningPathResolver pathResolver,
    ProvisioningFileSystem fileSystem = const LocalProvisioningFileSystem(),
    ProvisioningClock clock = const SystemProvisioningClock(),
  })  : _pathResolver = pathResolver,
        _fileSystem = fileSystem,
        _clock = clock;

  @override
  Future<ActivationState> readState() async {
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
        // Un file vuoto indica corruzione o scrittura interrotta: tenta il recovery da .bak
        return _tryRecoverFromBackup(backupPath);
      }

      final jsonMap = jsonDecode(content);
      if (jsonMap is! Map<String, dynamic>) {
        return _tryRecoverFromBackup(backupPath);
      }
      return ActivationState.fromJson(jsonMap);
    } catch (_) {
      return _tryRecoverFromBackup(backupPath);
    }
  }

  Future<ActivationState> _tryRecoverFromBackup(String backupPath) async {
    if (!await _fileSystem.fileExists(backupPath)) {
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.activationStateReadFailed,
        message:
            'File active_state.json corrotto ed introvabile backup valido.',
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

      // Ripristina atomicamente il file primario dal backup valido
      await writeState(recovered);
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
    try {
      final updatedState = state.copyWith(
        updatedAt: _clock.nowUtc().toIso8601String(),
      );
      final jsonStr =
          const JsonEncoder.withIndent('  ').convert(updatedState.toJson());
      await _fileSystem.writeStringAtomic(
        _pathResolver.activeStatePath,
        jsonStr,
      );
    } on ProvisioningException {
      rethrow;
    } catch (_) {
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.activationStateWriteFailed,
        message: 'Scrittura atomica dell\'activation state fallita.',
      );
    }
  }
}
