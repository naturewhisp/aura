import 'dart:async';
import 'dart:convert';
import '../domain/installation_record.dart';
import '../domain/provisioning_clock.dart';
import '../domain/provisioning_options.dart';
import 'provisioning_file_system.dart';
import 'provisioning_io_exception.dart';
import 'provisioning_lock.dart';
import 'provisioning_path_resolver.dart';

/// Contratto astratto I/O per la lettura e scrittura transazionale dell'InstallationRecord.
abstract class InstallationRecordRepository {
  /// Legge l'InstallationRecord memorizzato sul filesystem.
  /// Se il file non esiste ancora, restituisce un [InstallationRecord.empty].
  Future<InstallationRecord> readRecord();

  /// Sostituisce completamente l'InstallationRecord memorizzato (es. seeding iniziale o ripristino).
  /// Restituisce l'istanza di [InstallationRecord] effettivamente persistita sul disco (con timestamp aggiornato).
  Future<InstallationRecord> replaceRecord(InstallationRecord record);

  /// Deprecated alias per [replaceRecord].
  Future<InstallationRecord> writeRecord(InstallationRecord record);

  /// Esegue un'operazione atomica serializzata read-modify-write per evitare lost update.
  /// Restituisce l'istanza di [InstallationRecord] effettivamente persistita sul disco.
  Future<InstallationRecord> updateRecord(
    FutureOr<InstallationRecord> Function(InstallationRecord current) transform,
  );
}

/// Implementazione concreta basata su [ProvisioningFileSystem] ed isolata da I/O diretto.
final class JsonInstallationRecordRepository
    implements InstallationRecordRepository {
  static const String _lockKey = 'installation_record';

  final ProvisioningPathResolver _pathResolver;
  final ProvisioningFileSystem _fileSystem;
  final ProvisioningClock _clock;
  final ProvisioningLock _lock;

  JsonInstallationRecordRepository({
    required ProvisioningPathResolver pathResolver,
    required ProvisioningLock lock,
    ProvisioningFileSystem fileSystem = const LocalProvisioningFileSystem(),
    ProvisioningClock clock = const SystemProvisioningClock(),
  })  : _pathResolver = pathResolver,
        _fileSystem = fileSystem,
        _clock = clock,
        _lock = lock;

  @override
  Future<InstallationRecord> readRecord() async {
    return _lock.synchronized(_lockKey, () async {
      return _internalReadRecord();
    });
  }

  Future<InstallationRecord> _internalReadRecord() async {
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
        // File vuoto: corruzione o truncate accidentale -> tenta recovery da .bak
        return _tryRecoverFromBackup(backupPath);
      }

      final jsonMap = jsonDecode(content);
      if (jsonMap is! Map<String, dynamic>) {
        return _tryRecoverFromBackup(backupPath);
      }
      return InstallationRecord.fromJson(jsonMap);
    } on ProvisioningException catch (e) {
      // Recovery ammesso unicamente per corruzione/parsing JSON o sintassi del documento
      if (e.reason == ProvisioningFailureReason.catalogMalformed ||
          e.reason == ProvisioningFailureReason.installationRecordReadFailed) {
        return _tryRecoverFromBackup(backupPath);
      }
      // Schema version non supportata o altri errori di dominio: rilancia senza recovery
      rethrow;
    } on FormatException {
      return _tryRecoverFromBackup(backupPath);
    } on ProvisioningIoException {
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.installationRecordReadFailed,
        message:
            'Impossibile accedere al file installation_record sul filesystem.',
      );
    }
  }

  Future<InstallationRecord> _tryRecoverFromBackup(String backupPath) async {
    if (!await _fileSystem.fileExists(backupPath)) {
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.installationRecordReadFailed,
        message:
            'File installation_record corrotto ed introvabile backup valido.',
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

      // Ripristina il file primario senza distruggere il file di backup valido
      await _fileSystem.restoreFromBackup(
        _pathResolver.installationRecordPath,
        backupPath,
      );
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
  Future<InstallationRecord> writeRecord(InstallationRecord record) async {
    return replaceRecord(record);
  }

  @override
  Future<InstallationRecord> replaceRecord(InstallationRecord record) async {
    return _lock.synchronized(_lockKey, () async {
      return _internalWriteRecord(record);
    });
  }

  Future<InstallationRecord> _internalWriteRecord(
      InstallationRecord record) async {
    try {
      final updatedRecord = record.copyWith(
        updatedAt: _clock.nowUtc().toIso8601String(),
      );
      final jsonStr =
          const JsonEncoder.withIndent('  ').convert(updatedRecord.toJson());
      await _fileSystem.writeStringRecoverably(
        _pathResolver.installationRecordPath,
        jsonStr,
      );
      return updatedRecord;
    } on ProvisioningException {
      rethrow;
    } on ProvisioningIoException {
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.installationRecordWriteFailed,
        message: 'Scrittura del file installation_record fallita.',
      );
    } catch (_) {
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.installationRecordWriteFailed,
        message: 'Scrittura dell\'installation record fallita.',
      );
    }
  }

  @override
  Future<InstallationRecord> updateRecord(
    FutureOr<InstallationRecord> Function(InstallationRecord current) transform,
  ) async {
    return _lock.synchronized(_lockKey, () async {
      final current = await _internalReadRecord();
      final updated = await transform(current);
      return _internalWriteRecord(updated);
    });
  }
}
