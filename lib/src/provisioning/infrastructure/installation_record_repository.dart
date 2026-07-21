import 'dart:convert';
import '../domain/installation_record.dart';
import '../domain/provisioning_clock.dart';
import '../domain/provisioning_options.dart';
import 'provisioning_file_system.dart';
import 'provisioning_path_resolver.dart';

/// Contratto astratto I/O per la lettura e scrittura dell'InstallationRecord.
abstract class InstallationRecordRepository {
  /// Legge l'InstallationRecord memorizzato sul filesystem.
  /// Se il file non esiste ancora, restituisce un [InstallationRecord.empty].
  Future<InstallationRecord> readRecord();

  /// Scrive atomicamente l'InstallationRecord sul filesystem.
  Future<void> writeRecord(InstallationRecord record);
}

/// Implementazione concreta basata su [ProvisioningFileSystem] ed isolata da I/O diretto.
final class JsonInstallationRecordRepository
    implements InstallationRecordRepository {
  final ProvisioningPathResolver _pathResolver;
  final ProvisioningFileSystem _fileSystem;
  final ProvisioningClock _clock;

  JsonInstallationRecordRepository({
    required ProvisioningPathResolver pathResolver,
    ProvisioningFileSystem fileSystem = const LocalProvisioningFileSystem(),
    ProvisioningClock clock = const SystemProvisioningClock(),
  })  : _pathResolver = pathResolver,
        _fileSystem = fileSystem,
        _clock = clock;

  @override
  Future<InstallationRecord> readRecord() async {
    final recordPath = _pathResolver.installationRecordPath;
    final backupPath = '$recordPath.bak';

    if (!await _fileSystem.fileExists(recordPath)) {
      if (await _fileSystem.fileExists(backupPath)) {
        return _tryRecoverFromBackup(backupPath);
      }
      return InstallationRecord.empty(
        updatedAt: _clock.nowUtc().toIso8601String(),
      );
    }

    try {
      final content = await _fileSystem.readAsString(recordPath);
      if (content.trim().isEmpty) {
        // Un file vuoto indica corruzione o scrittura interrotta: tenta il recovery da .bak
        return _tryRecoverFromBackup(backupPath);
      }

      final jsonMap = jsonDecode(content);
      if (jsonMap is! Map<String, dynamic>) {
        return _tryRecoverFromBackup(backupPath);
      }
      return InstallationRecord.fromJson(jsonMap);
    } catch (_) {
      return _tryRecoverFromBackup(backupPath);
    }
  }

  Future<InstallationRecord> _tryRecoverFromBackup(String backupPath) async {
    if (!await _fileSystem.fileExists(backupPath)) {
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.installationRecordReadFailed,
        message:
            'File installation_record.json corrotto ed introvabile backup valido.',
      );
    }

    try {
      final content = await _fileSystem.readAsString(backupPath);
      if (content.trim().isEmpty) {
        throw const ProvisioningException(
          reason: ProvisioningFailureReason.installationRecordReadFailed,
          message: 'Anche il file di backup .bak risulta vuoto o corrotto.',
        );
      }

      final jsonMap = jsonDecode(content);
      if (jsonMap is! Map<String, dynamic>) {
        throw const ProvisioningException(
          reason: ProvisioningFailureReason.installationRecordReadFailed,
          message: 'Struttura JSON non valida nel file di backup .bak.',
        );
      }

      final recovered = InstallationRecord.fromJson(jsonMap);

      // Ripristina atomicamente il file primario dal backup valido
      await writeRecord(recovered);
      return recovered;
    } on ProvisioningException {
      rethrow;
    } catch (_) {
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.installationRecordReadFailed,
        message: 'Recovery da backup .bak dell\'installation_record fallito.',
      );
    }
  }

  @override
  Future<void> writeRecord(InstallationRecord record) async {
    try {
      final updatedRecord = record.copyWith(
        updatedAt: _clock.nowUtc().toIso8601String(),
      );
      final jsonStr =
          const JsonEncoder.withIndent('  ').convert(updatedRecord.toJson());
      await _fileSystem.writeStringAtomic(
        _pathResolver.installationRecordPath,
        jsonStr,
      );
    } on ProvisioningException {
      rethrow;
    } catch (_) {
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.installationRecordWriteFailed,
        message: 'Scrittura atomica dell\'installation record fallita.',
      );
    }
  }
}
