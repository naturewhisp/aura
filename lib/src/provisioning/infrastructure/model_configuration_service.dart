import 'dart:async';

import '../domain/catalog_manifest.dart';
import '../domain/configured_model_reference.dart';
import '../domain/installation_record.dart';
import '../domain/model_configuration_models.dart';
import 'installation_record_repository.dart';
import 'json_model_configuration_repository.dart';
import 'provisioning_file_system.dart';
import 'provisioning_path_resolver.dart';

/// Contratto astratto per la gestione dei binding dei modelli (Actor ed Evaluator),
/// la registrazione del consenso informato e la scansione di file GGUF esterni.
abstract interface class ModelConfigurationService {
  /// Associa un riferimento di modello (managed o external) al ruolo Actor.
  Future<ModelBindingValidationResult> bindActorModel(
    ConfiguredModelReference reference,
  );

  /// Associa un riferimento di modello (managed o external) al ruolo Evaluator.
  Future<ModelBindingValidationResult> bindEvaluatorModel(
    ConfiguredModelReference reference,
  );

  /// Rimuove il binding per il ruolo Actor.
  Future<void> clearActorBinding();

  /// Rimuove il binding per il ruolo Evaluator.
  Future<void> clearEvaluatorBinding();

  /// Registra ed attesta l'accettazione del consenso informato per l'uso di modelli GGUF esterni.
  Future<ExternalModelConsent> recordExternalModelConsent();

  /// Rileva se il consenso informato attuale è valido e registrato.
  Future<bool> isExternalModelConsentValid();

  /// Esegue la scansione non ricorsiva di primo livello di una directory per individuare candidati `.gguf`.
  Future<List<ExternalModelCandidate>> scanExternalModelCandidates({
    String? customDirectoryPath,
  });

  /// Legge la configurazione dei ruoli e il consenso attuale.
  Future<ModelConfigurationRecord> readRecord();
}

/// Implementazione predefinita basata sui repository JSON e filesystem astratto.
final class DefaultModelConfigurationService
    implements ModelConfigurationService {
  final JsonModelConfigurationRepository _configurationRepository;
  final InstallationRecordRepository _installationRecordRepository;
  final ProvisioningFileSystem _fileSystem;
  final ProvisioningPathResolver _pathResolver;

  DefaultModelConfigurationService({
    required JsonModelConfigurationRepository configurationRepository,
    required InstallationRecordRepository installationRecordRepository,
    required ProvisioningFileSystem fileSystem,
    required ProvisioningPathResolver pathResolver,
  })  : _configurationRepository = configurationRepository,
        _installationRecordRepository = installationRecordRepository,
        _fileSystem = fileSystem,
        _pathResolver = pathResolver;

  @override
  Future<ModelConfigurationRecord> readRecord() async {
    return _configurationRepository.readRecord();
  }

  @override
  Future<bool> isExternalModelConsentValid() async {
    final record = await _configurationRepository.readRecord();
    return record.externalModelConsent?.isValidCurrent == true;
  }

  @override
  Future<ExternalModelConsent> recordExternalModelConsent() async {
    final consent = ExternalModelConsent.now();
    await _configurationRepository.updateRecord((current) {
      return current.copyWith(externalModelConsent: consent);
    });
    return consent;
  }

  @override
  Future<void> clearActorBinding() async {
    await _configurationRepository.updateRecord((current) {
      final newModels = ModelRoleConfiguration(
        actor: null,
        evaluator: current.models.evaluator,
      );
      return current.copyWith(models: newModels);
    });
  }

  @override
  Future<void> clearEvaluatorBinding() async {
    await _configurationRepository.updateRecord((current) {
      final newModels = ModelRoleConfiguration(
        actor: current.models.actor,
        evaluator: null,
      );
      return current.copyWith(models: newModels);
    });
  }

  @override
  Future<ModelBindingValidationResult> bindActorModel(
    ConfiguredModelReference reference,
  ) async {
    final validation = await _validateReference(reference);
    if (!validation.isValid) {
      return validation;
    }

    await _configurationRepository.updateRecord((current) {
      final newModels = ModelRoleConfiguration(
        actor: reference,
        evaluator: current.models.evaluator,
      );
      return current.copyWith(models: newModels);
    });

    return validation;
  }

  @override
  Future<ModelBindingValidationResult> bindEvaluatorModel(
    ConfiguredModelReference reference,
  ) async {
    final validation = await _validateReference(reference);
    if (!validation.isValid) {
      return validation;
    }

    await _configurationRepository.updateRecord((current) {
      final newModels = ModelRoleConfiguration(
        actor: current.models.actor,
        evaluator: reference,
      );
      return current.copyWith(models: newModels);
    });

    return validation;
  }

  Future<ModelBindingValidationResult> _validateReference(
    ConfiguredModelReference reference,
  ) async {
    switch (reference) {
      case ManagedModelReference(:final installationId):
        return _validateManagedReference(installationId);
      case ExternalModelReference(:final absolutePath):
        return _validateExternalReference(absolutePath);
    }
  }

  Future<ModelBindingValidationResult> _validateManagedReference(
    String installationId,
  ) async {
    final record = await _installationRecordRepository.readRecord();
    final descriptor = record.findInstallation(installationId);

    if (descriptor == null) {
      return ModelBindingValidationResult(
        isValid: false,
        reference: ManagedModelReference(installationId: installationId),
        errorMessage:
            'Nessuna installazione gestita trovata con id "$installationId".',
      );
    }

    if (descriptor.status != InstallationStatus.verified) {
      return ModelBindingValidationResult(
        isValid: false,
        reference: ManagedModelReference(installationId: installationId),
        errorMessage:
            'L\'installazione gestita "$installationId" si trova nello stato non valido "${descriptor.status.name}".',
      );
    }

    if (descriptor.artifactType != CatalogArtifactType.model) {
      return ModelBindingValidationResult(
        isValid: false,
        reference: ManagedModelReference(installationId: installationId),
        errorMessage:
            'L\'installazione gestita "$installationId" ha tipo "${descriptor.artifactType.name}" e non è un modello.',
      );
    }

    // Verifica la presenza fisica della directory e del file eseguibile entry point
    final installDir = _pathResolver.resolveAppManagedRelativePath(
      descriptor.relativeInstallPath,
    );
    if (!await _fileSystem.directoryExists(installDir)) {
      return ModelBindingValidationResult(
        isValid: false,
        reference: ManagedModelReference(installationId: installationId),
        errorMessage:
            'La directory dell\'installazione gestita ("$installDir") non esiste più sul disco.',
      );
    }

    final entryFilePath = '$installDir\\${descriptor.entryFileName ?? ''}';
    if (!await _fileSystem.fileExists(entryFilePath)) {
      return ModelBindingValidationResult(
        isValid: false,
        reference: ManagedModelReference(installationId: installationId),
        errorMessage:
            'Il file payload dell\'installazione ("$entryFilePath") non esiste sul disco.',
      );
    }

    return ModelBindingValidationResult(
      isValid: true,
      reference: ManagedModelReference(installationId: installationId),
    );
  }

  Future<ModelBindingValidationResult> _validateExternalReference(
    String absolutePath,
  ) async {
    final ref = ExternalModelReference(absolutePath: absolutePath);

    // Verifica il consenso informato
    final consentValid = await isExternalModelConsentValid();
    if (!consentValid) {
      return ModelBindingValidationResult(
        isValid: false,
        reference: ref,
        errorMessage:
            'L\'utilizzo di modelli GGUF esterni richiede l\'accettazione del consenso informato.',
      );
    }

    final cleanPath = absolutePath.trim();
    if (!cleanPath.toLowerCase().endsWith('.gguf')) {
      return ModelBindingValidationResult(
        isValid: false,
        reference: ref,
        errorMessage:
            'Il file specificato non ha estensione ".gguf": "$cleanPath".',
      );
    }

    if (await _fileSystem.directoryExists(cleanPath)) {
      return ModelBindingValidationResult(
        isValid: false,
        reference: ref,
        errorMessage:
            'Il percorso specificato indica una directory, non un file GGUF.',
      );
    }

    if (!await _fileSystem.fileExists(cleanPath)) {
      return ModelBindingValidationResult(
        isValid: false,
        reference: ref,
        errorMessage: 'Il file GGUF esterno non esiste: "$cleanPath".',
      );
    }

    try {
      final size = await _fileSystem.getFileSize(cleanPath);
      if (size <= 0) {
        return ModelBindingValidationResult(
          isValid: false,
          reference: ref,
          errorMessage:
              'Il file GGUF esterno ha dimensione non valida (0 byte).',
        );
      }
    } catch (e) {
      return ModelBindingValidationResult(
        isValid: false,
        reference: ref,
        errorMessage: 'Impossibile accedere al file GGUF esterno: $e',
      );
    }

    return ModelBindingValidationResult(
      isValid: true,
      reference: ref,
    );
  }

  @override
  Future<List<ExternalModelCandidate>> scanExternalModelCandidates({
    String? customDirectoryPath,
  }) async {
    final searchDir = customDirectoryPath?.trim().isNotEmpty == true
        ? customDirectoryPath!.trim()
        : _pathResolver.appManagedRoot;

    if (!await _fileSystem.directoryExists(searchDir)) {
      return const [];
    }

    final entries = await _fileSystem.listDirectory(searchDir);
    final candidates = <ExternalModelCandidate>[];

    for (final entry in entries) {
      final fullPath = '$searchDir\\$entry';
      if (entry.toLowerCase().endsWith('.gguf') &&
          await _fileSystem.fileExists(fullPath)) {
        try {
          final size = await _fileSystem.getFileSize(fullPath);
          candidates.add(
            ExternalModelCandidate(
              absolutePath: fullPath,
              fileName: entry,
              sizeBytes: size,
              modifiedAtUtc: DateTime.now().toUtc(),
            ),
          );
        } catch (_) {}
      }
    }

    candidates.sort((a, b) => a.fileName.compareTo(b.fileName));
    return candidates;
  }
}
