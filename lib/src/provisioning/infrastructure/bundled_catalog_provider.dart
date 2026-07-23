import 'dart:convert';
import 'dart:typed_data';
import '../domain/catalog_acquisition_exceptions.dart';
import '../domain/catalog_acquisition_models.dart';
import '../domain/catalog_manifest.dart';
import '../domain/catalog_provider_contracts.dart';

/// Provider di catalogo integrato statico (Bundled Bootstrap).
final class BundledCatalogProvider implements CatalogProvider {
  final CatalogManifest _manifest;
  final int _catalogRevision;

  BundledCatalogProvider({
    CatalogManifest? manifest,
    int catalogRevision = 1,
  })  : _manifest = manifest ?? CatalogManifest.initialDefault(),
        _catalogRevision = catalogRevision;

  @override
  CatalogSource get source => CatalogSource.bundledBootstrap;

  @override
  Future<CatalogProviderResult> getCandidate(
    CatalogProviderContext context,
  ) async {
    try {
      final signedPayload = CatalogSignedPayload(
        schemaVersion: '1.0',
        signatureAlgorithm: 'ed25519-v1',
        keyId: 'aura-bootstrap-key',
        catalogId: _manifest.catalogId,
        catalogVersion: _manifest.schemaVersion,
        catalogRevision: _catalogRevision,
        issuedAt: '2026-01-01T00:00:00Z',
        expiresAt: '2099-12-31T23:59:59Z',
        manifest: _manifest,
      );

      final dummySig = base64.encode(Uint8List(64));
      final envelope = CatalogEnvelope(
        signedPayload: signedPayload,
        signature: dummySig,
      );

      final factoryResult = await context.candidateFactory.createCandidate(
        envelope: envelope,
        source: source,
        trustStore: context.trustStore,
        compatibilityEvaluator: context.compatibilityEvaluator,
        validationService: context.validationService,
        signatureVerifier: context.signatureVerifier,
        nowUtc: context.nowUtc,
        applicationVersion: context.applicationVersion,
      );

      if (factoryResult.isSuccess) {
        return CatalogProviderResult.success(factoryResult.candidate);
      } else {
        return CatalogProviderResult.failure(
          failureReason: factoryResult.failureReason,
          message: factoryResult.errorMessage ??
              'Fallita la creazione del candidato bootstrap.',
        );
      }
    } catch (e) {
      return CatalogProviderResult.failure(
        failureReason: CatalogAcquisitionFailureReason.malformedEnvelope,
        message: 'Errore nell\'inizializzazione del catalogo bootstrap: $e',
      );
    }
  }
}
