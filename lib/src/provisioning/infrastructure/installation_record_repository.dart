import 'dart:convert';
import 'dart:io';
import '../domain/installation_record.dart';
import '../domain/provisioning_options.dart';
import 'provisioning_path_resolver.dart';

/// Contratto astratto I/O per la lettura e scrittura dell'InstallationRecord.
abstract class InstallationRecordRepository {
  /// Legge l'InstallationRecord memorizzato sul filesystem.
  /// Se il file non esiste ancora, restituisce un [InstallationRecord.empty].
  Future<InstallationRecord> readRecord();

  /// Scrive atomicamente l'InstallationRecord sul filesystem.
  Future<void> writeRecord(InstallationRecord record);
}

/// Implementazione concreta basata su file JSON atomico.
final class JsonInstallationRecordRepository
    implements InstallationRecordRepository {
  final ProvisioningPathResolver _pathResolver;

  JsonInstallationRecordRepository({
    required ProvisioningPathResolver pathResolver,
  }) : _pathResolver = pathResolver;

  @override
  Future<InstallationRecord> readRecord() async {
    final file = File(_pathResolver.installationRecordPath);
    if (!await file.exists()) {
      return InstallationRecord.empty();
    }

    try {
      final content = await file.readAsString();
      if (content.trim().isEmpty) {
        return InstallationRecord.empty();
      }
      final jsonMap = jsonDecode(content);
      if (jsonMap is! Map<String, dynamic>) {
        throw const ProvisioningException(
          reason: ProvisioningFailureReason.installationRecordReadFailed,
          message:
              'Il contenuto di installation_record.json non è un oggetto JSON.',
        );
      }
      return InstallationRecord.fromJson(jsonMap);
    } on ProvisioningException {
      rethrow;
    } catch (_) {
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.installationRecordReadFailed,
        message:
            'Impossibile leggere o decodificare il file installation_record.json.',
      );
    }
  }

  @override
  Future<void> writeRecord(InstallationRecord record) async {
    final targetFile = File(_pathResolver.installationRecordPath);
    final tempFile = File(
        '${_pathResolver.installationRecordPath}.tmp_${DateTime.now().microsecondsSinceEpoch}');

    try {
      final parentDir = targetFile.parent;
      if (!await parentDir.exists()) {
        await parentDir.create(recursive: true);
      }

      final jsonStr =
          const JsonEncoder.withIndent('  ').convert(record.toJson());
      await tempFile.writeAsString(jsonStr, flush: true);

      if (await targetFile.exists()) {
        await targetFile.delete();
      }
      await tempFile.rename(targetFile.path);
    } catch (_) {
      if (await tempFile.exists()) {
        try {
          await tempFile.delete();
        } catch (_) {}
      }
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.installationRecordWriteFailed,
        message: 'Scrittura atomica di installation_record.json fallita.',
      );
    }
  }
}
