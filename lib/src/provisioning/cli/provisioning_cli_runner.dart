import 'dart:convert';
import 'package:meta/meta.dart';
import '../bootstrap/provisioning_bootstrap_service.dart';
import '../domain/catalog_manifest.dart';
import '../domain/installation_record.dart';
import '../domain/provisioning_options.dart';
import '../infrastructure/installation_record_repository.dart';
import '../infrastructure/provisioning_coordinator.dart';

/// DTO per la risposta formattata dei comandi CLI di provisioning.
@immutable
final class CliCommandResult {
  final bool success;
  final String command;
  final String message;
  final Map<String, dynamic> payload;

  const CliCommandResult({
    required this.success,
    required this.command,
    required this.message,
    this.payload = const {},
  });

  String toFormattedJson() {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert({
      'success': success,
      'command': command,
      'message': message,
      'payload': payload,
    });
  }
}

/// Utility CLI per la diagnosi, l'ispezione ed il controllo operativo del sistema di provisioning di A.U.R.A.
final class ProvisioningCliRunner {
  final ProvisioningBootstrapService _bootstrapService;
  final ProvisioningCoordinator _coordinator;
  final InstallationRecordRepository _recordRepository;

  ProvisioningCliRunner({
    required ProvisioningBootstrapService bootstrapService,
    required ProvisioningCoordinator coordinator,
    required InstallationRecordRepository recordRepository,
  })  : _bootstrapService = bootstrapService,
        _coordinator = coordinator,
        _recordRepository = recordRepository;

  /// Esegue un controllo dello stato di salute del provisioning e restituisce l'esito diagnostico.
  Future<CliCommandResult> status() async {
    final bootRes = await _bootstrapService.bootstrap();
    return CliCommandResult(
      success: bootRes.status != ProvisioningBootstrapStatus.failed,
      command: 'status',
      message: 'Bootstrap status: ${bootRes.status.name}',
      payload: bootRes.toJson(),
    );
  }

  /// Elenca gli artefatti presenti in un [CatalogManifest].
  CliCommandResult listCatalog(CatalogManifest manifest) {
    final artifacts = manifest.artifacts
        .map((a) => {
              'artifactId': a.artifactId,
              'artifactType': a.artifactType.name,
              'displayName': a.displayName,
              'version': a.version,
              'buildId': a.buildId,
              'platform': a.platform,
              'architecture': a.architecture,
              'sizeBytes': a.sizeBytes,
              'sha256': a.sha256,
              'sourceKind': a.sourceKind.name,
            })
        .toList();

    return CliCommandResult(
      success: true,
      command: 'list-catalog',
      message: 'Trovati ${artifacts.length} artefatti nel catalogo.',
      payload: {
        'catalogId': manifest.catalogId,
        'artifacts': artifacts,
      },
    );
  }

  /// Elenca gli artefatti registrati come installati nell'[InstallationRecord].
  Future<CliCommandResult> listInstalled() async {
    final record = await _recordRepository.readRecord();
    final installed = record.installedArtifacts
        .map((i) => {
              'installationId': i.installationId,
              'artifactId': i.artifactId,
              'artifactType': i.artifactType.name,
              'version': i.version,
              'buildId': i.buildId,
              'status': i.status.name,
              'installedAt': i.installedAt,
              'sizeBytes': i.sizeBytes,
              'relativeInstallPath': i.relativeInstallPath,
            })
        .toList();

    return CliCommandResult(
      success: true,
      command: 'list-installed',
      message: 'Trovate ${installed.length} installazioni registrate.',
      payload: {
        'schemaVersion': record.schemaVersion,
        'updatedAt': record.updatedAt,
        'installedArtifacts': installed,
      },
    );
  }

  /// Attiva un'installazione specifica tramite il suo `installationId`.
  Future<CliCommandResult> activate({
    required String installationId,
    required String operationId,
  }) async {
    final res = await _coordinator.activateInstallation(
      installationId: installationId,
      operationId: operationId,
    );

    return CliCommandResult(
      success: res.isSuccess,
      command: 'activate',
      message: res.isSuccess
          ? 'Attivazione completata con successo per "$installationId".'
          : (res.sanitizedMessage ?? 'Attivazione fallita.'),
      payload: res.toJson(),
    );
  }

  /// Rimuove un'installazione specifica dal disco e dal registro tramite il suo `installationId`.
  Future<CliCommandResult> remove({
    required String installationId,
    required String operationId,
  }) async {
    final res = await _coordinator.removeInstallation(
      installationId: installationId,
      operationId: operationId,
    );

    return CliCommandResult(
      success: res.isSuccess,
      command: 'remove',
      message: res.isSuccess
          ? 'Rimozione completata con successo per "$installationId".'
          : (res.sanitizedMessage ?? 'Rimozione fallita.'),
      payload: res.toJson(),
    );
  }

  /// Esegue il provisioning di un artefatto del catalogo.
  Future<CliCommandResult> provision({
    required ProvisioningRequest request,
    required CatalogManifest manifest,
  }) async {
    final res = await _coordinator.provisionArtifact(
      request: request,
      manifest: manifest,
    );

    return CliCommandResult(
      success: res.isSuccess,
      command: 'provision',
      message: res.isSuccess
          ? 'Provisioning completato per "${request.artifactId}".'
          : (res.sanitizedMessage ?? 'Provisioning fallito.'),
      payload: res.toJson(),
    );
  }
}
