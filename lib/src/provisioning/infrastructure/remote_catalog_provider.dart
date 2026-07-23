import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../domain/catalog_acquisition_exceptions.dart';
import '../domain/catalog_acquisition_models.dart';
import '../domain/catalog_provider_contracts.dart';

/// Provider di catalogo basato sul recupero dell'envelope firmata via HTTPS.
final class RemoteCatalogProvider implements CatalogProvider {
  final String _catalogUrl;
  final http.Client _httpClient;

  RemoteCatalogProvider({
    required String catalogUrl,
    http.Client? httpClient,
  })  : _catalogUrl = catalogUrl.trim(),
        _httpClient = httpClient ?? http.Client();

  @override
  CatalogSource get source => CatalogSource.remoteSigned;

  @override
  Future<CatalogProviderResult> getCandidate(
    CatalogProviderContext context,
  ) async {
    if (_catalogUrl.isEmpty) {
      return const CatalogProviderResult.failure(
        failureReason: CatalogAcquisitionFailureReason.invalidCatalogUrl,
        message: 'URL del catalogo remoto non specificato o vuoto.',
      );
    }

    Uri uri;
    try {
      uri = Uri.parse(_catalogUrl);
      if (!uri.isAbsolute || uri.scheme != 'https' || uri.host.isEmpty) {
        return const CatalogProviderResult.failure(
          failureReason: CatalogAcquisitionFailureReason.invalidCatalogUrl,
          message: 'URL del catalogo remoto non è un endpoint HTTPS valido.',
        );
      }
    } catch (_) {
      return const CatalogProviderResult.failure(
        failureReason: CatalogAcquisitionFailureReason.invalidCatalogUrl,
        message:
            'Impossibile effettuare il parsing dell\'URL di catalogo remoto.',
      );
    }

    try {
      final response = await _httpClient.get(uri).timeout(
            const Duration(seconds: 15),
          );

      if (response.statusCode != 200) {
        return CatalogProviderResult.failure(
          failureReason: CatalogAcquisitionFailureReason.remoteFetchFailed,
          message:
              'Risposta HTTP remota non valida: ${response.statusCode} ${response.reasonPhrase}',
        );
      }

      final bodyText = response.body.trim();
      if (bodyText.isEmpty) {
        return const CatalogProviderResult.failure(
          failureReason: CatalogAcquisitionFailureReason.malformedEnvelope,
          message: 'Risposta HTTP remota vuota.',
        );
      }

      final jsonMap = jsonDecode(bodyText);
      if (jsonMap is! Map<String, dynamic>) {
        return const CatalogProviderResult.failure(
          failureReason: CatalogAcquisitionFailureReason.malformedEnvelope,
          message: 'Il JSON restituito dal server remoto non è una mappa.',
        );
      }

      final envelope = CatalogEnvelope.fromJson(jsonMap);

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
              'Validazione del catalogo remoto fallita.',
        );
      }
    } on TimeoutException {
      return const CatalogProviderResult.failure(
        failureReason: CatalogAcquisitionFailureReason.networkTimeout,
        message: 'Timeout di rete durante il recupero del catalogo remoto.',
      );
    } catch (e) {
      return CatalogProviderResult.failure(
        failureReason: CatalogAcquisitionFailureReason.remoteFetchFailed,
        message: 'Errore di rete durante il recupero del catalogo remoto: $e',
      );
    }
  }
}
