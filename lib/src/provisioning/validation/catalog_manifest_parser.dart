import 'dart:convert';
import '../domain/catalog_manifest.dart';
import '../domain/provisioning_options.dart';

/// Parser strict per i documenti di catalogo manifest.
abstract final class CatalogManifestParser {
  static const String supportedSchemaVersion = '1.0';

  /// Decodifica la stringa JSON ed effettua il parsing del [CatalogManifest].
  static CatalogManifest parse(String jsonString) {
    if (jsonString.trim().isEmpty) {
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.catalogMalformed,
        message: 'Il contenuto del catalogo JSON è vuoto.',
      );
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(jsonString);
    } catch (_) {
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.catalogMalformed,
        message: 'Sintassi JSON del catalogo non valida.',
      );
    }

    if (decoded is! Map) {
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.catalogMalformed,
        message: 'Il catalogo radice deve essere un oggetto JSON.',
      );
    }

    final jsonMap = Map<String, dynamic>.from(decoded);
    final rawSchema = jsonMap['schemaVersion'] as String?;

    if (rawSchema == null || rawSchema.trim().isEmpty) {
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.catalogMalformed,
        message: 'Campo obbligatorio mancante: schemaVersion.',
      );
    }

    if (rawSchema.trim() != supportedSchemaVersion) {
      throw ProvisioningException(
        reason: ProvisioningFailureReason.unsupportedSchemaVersion,
        message:
            'Versione di schema non supportata: "$rawSchema". Attesa: "$supportedSchemaVersion".',
      );
    }

    try {
      return CatalogManifest.fromJson(jsonMap);
    } on ProvisioningException {
      rethrow;
    } catch (_) {
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.catalogMalformed,
        message: 'Errore nella struttura dei campi del catalogo manifest.',
      );
    }
  }
}
