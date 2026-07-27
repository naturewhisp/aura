import 'package:meta/meta.dart';
import 'provisioning_options.dart';

/// Rappresenta il checkpoint atomico persistito su disco per il resume di un download parziale.
@immutable
final class DownloadCheckpoint {
  static const String currentSchemaVersion = '1.0';

  /// Versione di schema della struttura del checkpoint (`'1.0'`).
  final String schemaVersion;

  /// Identificatore dell'operazione di download.
  final String operationId;

  /// Identificatore logico dell'artefatto.
  final String artifactId;

  /// URI sorgente da cui e iniziato il download.
  final String sourceUri;

  /// Strong ETag validato restituito dal server originario (`null` o debole `W/` se assente).
  final String? strongEtag;

  /// Numero di byte scaricati e salvati fisicamente su disco (file `.part`).
  final int downloadedBytes;

  /// Dimensione totale attesa in byte.
  final int expectedSizeBytes;

  /// Timestamp UTC di creazione del checkpoint.
  final DateTime createdAtUtc;

  /// Timestamp UTC dell'ultimo aggiornamento del checkpoint.
  final DateTime updatedAtUtc;

  /// Header `Last-Modified` salvato a scopo puramente diagnostico.
  final String? lastModified;

  DownloadCheckpoint({
    this.schemaVersion = currentSchemaVersion,
    required this.operationId,
    required this.artifactId,
    required this.sourceUri,
    this.strongEtag,
    required this.downloadedBytes,
    required this.expectedSizeBytes,
    required DateTime createdAtUtc,
    required DateTime updatedAtUtc,
    this.lastModified,
  })  : createdAtUtc = createdAtUtc.toUtc(),
        updatedAtUtc = updatedAtUtc.toUtc() {
    if (operationId.trim().isEmpty) {
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.invalidCatalog,
        message: 'operationId non puo essere vuoto nel checkpoint.',
      );
    }
    if (downloadedBytes < 0) {
      throw ProvisioningException(
        reason: ProvisioningFailureReason.invalidCatalog,
        message: 'downloadedBytes non puo essere negativo: $downloadedBytes.',
      );
    }
    if (expectedSizeBytes <= 0) {
      throw ProvisioningException(
        reason: ProvisioningFailureReason.invalidCatalog,
        message:
            'expectedSizeBytes deve essere maggiore di 0: $expectedSizeBytes.',
      );
    }
    if (downloadedBytes > expectedSizeBytes) {
      throw ProvisioningException(
        reason: ProvisioningFailureReason.invalidCatalog,
        message:
            'downloadedBytes ($downloadedBytes) non puo superare expectedSizeBytes ($expectedSizeBytes).',
      );
    }
  }

  static final RegExp _strongEtagRegex = RegExp(r'^"[^"]+"$');

  /// Indica se l'ETag fornito e un ETag forte sintatticamente valido (`^"[^"]+"$`).
  static bool isValidStrongEtag(String? tag) {
    if (tag == null || tag.trim().isEmpty) return false;
    final trimmed = tag.trim();
    if (trimmed.startsWith('W/') || trimmed.startsWith('w/')) return false;
    return _strongEtagRegex.hasMatch(trimmed);
  }

  /// Indica se il checkpoint possiede un ETag forte sintatticamente valido idoneo per il resume con `If-Range`.
  bool get hasValidStrongEtag => isValidStrongEtag(strongEtag);

  /// Converte l'istanza in una mappa JSON.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'schemaVersion': schemaVersion,
      'operationId': operationId,
      'artifactId': artifactId,
      'sourceUri': sourceUri,
      'strongEtag': strongEtag,
      'downloadedBytes': downloadedBytes,
      'expectedSizeBytes': expectedSizeBytes,
      'createdAtUtc': createdAtUtc.toIso8601String(),
      'updatedAtUtc': updatedAtUtc.toIso8601String(),
      if (lastModified != null) 'lastModified': lastModified,
    };
  }

  /// Deserializza una mappa JSON verificando l'integrità dei dati.
  factory DownloadCheckpoint.fromJson(Map<String, dynamic> json) {
    try {
      final schema = json['schemaVersion'] as String? ?? '1.0';
      final operationId = json['operationId'] as String;
      final artifactId = json['artifactId'] as String;
      final sourceUri = json['sourceUri'] as String;
      final strongEtag = json['strongEtag'] as String?;
      final downloadedBytes = (json['downloadedBytes'] as num).toInt();
      final expectedSizeBytes = (json['expectedSizeBytes'] as num).toInt();
      final createdAtUtc = DateTime.parse(json['createdAtUtc'] as String);
      final updatedAtUtc = DateTime.parse(json['updatedAtUtc'] as String);
      final lastModified = json['lastModified'] as String?;

      return DownloadCheckpoint(
        schemaVersion: schema,
        operationId: operationId,
        artifactId: artifactId,
        sourceUri: sourceUri,
        strongEtag: strongEtag,
        downloadedBytes: downloadedBytes,
        expectedSizeBytes: expectedSizeBytes,
        createdAtUtc: createdAtUtc,
        updatedAtUtc: updatedAtUtc,
        lastModified: lastModified,
      );
    } catch (e) {
      throw ProvisioningException(
        reason: ProvisioningFailureReason.invalidCatalog,
        message: 'JSON del DownloadCheckpoint non valido o malformato: $e',
      );
    }
  }

  /// Restituisce una nuova istanza aggiornata con i byte scaricati ed il timestamp.
  DownloadCheckpoint copyWithProgress({
    required int downloadedBytes,
    required DateTime updatedAtUtc,
    String? strongEtag,
  }) {
    return DownloadCheckpoint(
      schemaVersion: schemaVersion,
      operationId: operationId,
      artifactId: artifactId,
      sourceUri: sourceUri,
      strongEtag: strongEtag ?? this.strongEtag,
      downloadedBytes: downloadedBytes,
      expectedSizeBytes: expectedSizeBytes,
      createdAtUtc: createdAtUtc,
      updatedAtUtc: updatedAtUtc,
      lastModified: lastModified,
    );
  }
}
