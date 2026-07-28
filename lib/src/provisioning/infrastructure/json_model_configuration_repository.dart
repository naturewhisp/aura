import 'dart:convert';
import 'package:meta/meta.dart';

import '../domain/model_configuration_models.dart';
import '../domain/runtime_dependency_models.dart';
import 'provisioning_file_system.dart';
import 'provisioning_lock.dart';

/// Versione corrente dello schema JSON del file `model_configuration.json`.
const int kCurrentModelConfigurationSchemaVersion = 1;

/// Nome canonico del file di persistenza della configurazione runtime e modelli.
const String kModelConfigurationFileName = 'model_configuration.json';

/// Contenitore immutabile dello stato completo registrato in `model_configuration.json`.
@immutable
final class ModelConfigurationRecord {
  final int schemaVersion;
  final LlamaServerConfiguration? runtime;
  final ModelRoleConfiguration models;
  final ExternalModelConsent? externalModelConsent;

  const ModelConfigurationRecord({
    this.schemaVersion = kCurrentModelConfigurationSchemaVersion,
    this.runtime,
    this.models = const ModelRoleConfiguration(),
    this.externalModelConsent,
  });

  factory ModelConfigurationRecord.empty() {
    return const ModelConfigurationRecord(
      schemaVersion: kCurrentModelConfigurationSchemaVersion,
      runtime: null,
      models: ModelRoleConfiguration(),
      externalModelConsent: null,
    );
  }

  factory ModelConfigurationRecord.fromJson(Map<String, dynamic> json) {
    final version = json['schemaVersion'] as int?;
    if (version == null) {
      throw const FormatException(
        'Campo "schemaVersion" mancante nel file di configurazione modelli.',
      );
    }
    if (version > kCurrentModelConfigurationSchemaVersion) {
      throw FormatException(
        'Versione dello schema $version non supportata (versione massima supportata: $kCurrentModelConfigurationSchemaVersion).',
      );
    }

    final runtimeMap = json['runtime'] as Map<String, dynamic>?;
    final modelsMap = json['models'] as Map<String, dynamic>?;
    final consentMap = json['externalModelConsent'] as Map<String, dynamic>?;

    return ModelConfigurationRecord(
      schemaVersion: version,
      runtime: runtimeMap != null
          ? LlamaServerConfiguration.fromJson(runtimeMap)
          : null,
      models: modelsMap != null
          ? ModelRoleConfiguration.fromJson(modelsMap)
          : const ModelRoleConfiguration(),
      externalModelConsent:
          consentMap != null ? ExternalModelConsent.fromJson(consentMap) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'schemaVersion': schemaVersion,
      if (runtime != null) 'runtime': runtime!.toJson(),
      'models': models.toJson(),
      if (externalModelConsent != null)
        'externalModelConsent': externalModelConsent!.toJson(),
    };
  }

  ModelConfigurationRecord copyWith({
    int? schemaVersion,
    Object? runtime = _unset,
    ModelRoleConfiguration? models,
    Object? externalModelConsent = _unset,
  }) {
    return ModelConfigurationRecord(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      runtime: identical(runtime, _unset)
          ? this.runtime
          : runtime as LlamaServerConfiguration?,
      models: models ?? this.models,
      externalModelConsent: identical(externalModelConsent, _unset)
          ? this.externalModelConsent
          : externalModelConsent as ExternalModelConsent?,
    );
  }

  static const Object _unset = Object();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ModelConfigurationRecord &&
          runtimeType == other.runtimeType &&
          schemaVersion == other.schemaVersion &&
          runtime == other.runtime &&
          models == other.models &&
          externalModelConsent == other.externalModelConsent;

  @override
  int get hashCode => Object.hash(
        schemaVersion,
        runtime,
        models,
        externalModelConsent,
      );

  @override
  String toString() =>
      'ModelConfigurationRecord(schema: $schemaVersion, runtime: $runtime, models: $models)';
}

/// Repository per la lettura e scrittura atomica recoverable del file `model_configuration.json`.
final class JsonModelConfigurationRepository {
  final String storeDirectoryPath;
  final ProvisioningFileSystem _fileSystem;
  final ProvisioningLock _lock;
  final String _lockKey;

  JsonModelConfigurationRepository({
    required this.storeDirectoryPath,
    required ProvisioningFileSystem fileSystem,
    required ProvisioningLock lock,
    String? lockKey,
  })  : _fileSystem = fileSystem,
        _lock = lock,
        _lockKey = lockKey ?? 'model_configuration_repo_lock';

  String get _primaryFilePath =>
      '$storeDirectoryPath\\$kModelConfigurationFileName';
  String get _backupFilePath => '$_primaryFilePath.bak';

  /// Legge lo stato corrente della configurazione con fallback a `.bak` in caso di corruzione.
  Future<ModelConfigurationRecord> readRecord() async {
    return _lock.synchronized(_lockKey, () async {
      if (!await _fileSystem.fileExists(_primaryFilePath)) {
        if (await _fileSystem.fileExists(_backupFilePath)) {
          final backupRecord = await _tryReadRecordFromFile(_backupFilePath);
          if (backupRecord != null) {
            await _writeRecordInternal(backupRecord);
            return backupRecord;
          }
        }
        return ModelConfigurationRecord.empty();
      }

      final primaryRecord = await _tryReadRecordFromFile(_primaryFilePath);
      if (primaryRecord != null) {
        return primaryRecord;
      }

      // Tenta fallback a .bak
      if (await _fileSystem.fileExists(_backupFilePath)) {
        final backupRecord = await _tryReadRecordFromFile(_backupFilePath);
        if (backupRecord != null) {
          await _writeRecordInternal(backupRecord);
          return backupRecord;
        }
      }

      return ModelConfigurationRecord.empty();
    });
  }

  /// Sovrascrive interamente lo stato di configurazione tramite scrittura atomica recoverable.
  Future<ModelConfigurationRecord> replaceRecord(
      ModelConfigurationRecord record) async {
    return _lock.synchronized(_lockKey, () async {
      await _writeRecordInternal(record);
      return record;
    });
  }

  /// Applica una trasformazione atomica alla configurazione sotto lock.
  Future<ModelConfigurationRecord> updateRecord(
    ModelConfigurationRecord Function(ModelConfigurationRecord current)
        transform,
  ) async {
    return _lock.synchronized(_lockKey, () async {
      final current = await readRecord();
      final updated = transform(current);
      await _writeRecordInternal(updated);
      return updated;
    });
  }

  Future<ModelConfigurationRecord?> _tryReadRecordFromFile(String path) async {
    try {
      final content = await _fileSystem.readAsString(path);
      if (content.trim().isEmpty) return null;
      final jsonMap = jsonDecode(content) as Map<String, dynamic>;
      return ModelConfigurationRecord.fromJson(jsonMap);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeRecordInternal(ModelConfigurationRecord record) async {
    await _fileSystem.createDirectory(storeDirectoryPath);

    const encoder = JsonEncoder.withIndent('  ');
    final jsonStr = encoder.convert(record.toJson());

    await _fileSystem.writeStringRecoverably(
      _primaryFilePath,
      jsonStr,
    );
  }
}
