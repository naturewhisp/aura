import 'dart:io';
import 'package:http/http.dart' as http;
import '../domain/provisioning_cancellation_token.dart';
import '../domain/provisioning_options.dart';
import 'provisioning_io_exception.dart';

/// Contratto astratto per il download HTTP/HTTPS di artefatti remoti.
abstract class ProvisioningHttpClient {
  /// Scarica un file dall'URL remoto specificato e lo salva su [targetPath].
  /// Ritorna il numero totale di byte scaricati.
  Future<int> downloadFile({
    required String uri,
    required String targetPath,
    required int expectedSizeBytes,
    ProvisioningCancellationToken? cancellationToken,
    Duration timeout = const Duration(minutes: 5),
  });
}

/// Implementazione concreta basata su `package:http` con gestione sicura dei redirect HTTPS e verifica esatta delle dimensioni.
final class HttpProvisioningHttpClient implements ProvisioningHttpClient {
  static const int maxRedirects = 5;
  final http.Client _client;

  HttpProvisioningHttpClient({http.Client? client})
      : _client = client ?? http.Client();

  @override
  Future<int> downloadFile({
    required String uri,
    required String targetPath,
    required int expectedSizeBytes,
    ProvisioningCancellationToken? cancellationToken,
    Duration timeout = const Duration(minutes: 5),
  }) async {
    cancellationToken?.throwIfCancelled();

    var currentUriStr = uri;
    var redirectCount = 0;
    http.StreamedResponse? finalResponse;

    while (redirectCount <= maxRedirects) {
      cancellationToken?.throwIfCancelled();

      final parsedUri = Uri.tryParse(currentUriStr);
      if (parsedUri == null ||
          !parsedUri.isAbsolute ||
          parsedUri.scheme != 'https' ||
          parsedUri.host.isEmpty ||
          parsedUri.userInfo.isNotEmpty) {
        throw const ProvisioningException(
          reason: ProvisioningFailureReason.invalidSourceUri,
          message: 'URI remota non valida, non HTTPS o contenente credenziali.',
        );
      }

      final request = http.Request('GET', parsedUri)..followRedirects = false;
      http.StreamedResponse response;

      try {
        response = await _client.send(request).timeout(timeout);
      } catch (_) {
        throw const ProvisioningException(
          reason: ProvisioningFailureReason.downloadFailed,
          message:
              'Connessione al server remoto per il download fallita o andata in timeout.',
        );
      }

      if (response.statusCode >= 300 && response.statusCode < 400) {
        redirectCount++;
        if (redirectCount > maxRedirects) {
          throw const ProvisioningException(
            reason: ProvisioningFailureReason.redirectRejected,
            message: 'Numero massimo di redirect HTTP superato.',
          );
        }

        final locationHeader = response.headers['location'];
        if (locationHeader == null || locationHeader.trim().isEmpty) {
          throw const ProvisioningException(
            reason: ProvisioningFailureReason.redirectRejected,
            message: 'Header Location di redirect mancante o vuoto.',
          );
        }

        final redirectUri = parsedUri.resolve(locationHeader.trim());
        if (!redirectUri.isAbsolute ||
            redirectUri.scheme != 'https' ||
            redirectUri.host.isEmpty ||
            redirectUri.userInfo.isNotEmpty) {
          throw const ProvisioningException(
            reason: ProvisioningFailureReason.redirectRejected,
            message: 'Redirect rifiutato: URL non HTTPS o non sicura.',
          );
        }

        currentUriStr = redirectUri.toString();
        continue;
      }

      if (response.statusCode == 200) {
        finalResponse = response;
        break;
      }

      throw ProvisioningException(
        reason: ProvisioningFailureReason.downloadFailed,
        message:
            'Download fallito con codice di stato HTTP: ${response.statusCode}.',
      );
    }

    if (finalResponse == null) {
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.downloadFailed,
        message: 'Download fallito a causa di troppi redirect.',
      );
    }

    final contentLength = finalResponse.contentLength;
    if (contentLength != null && contentLength != expectedSizeBytes) {
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.sizeMismatch,
        message:
            'La dimensione dichiarata dall\'header Content-Length non corrisponde a quella attesa.',
      );
    }

    final targetFile = File(targetPath);
    await targetFile.parent.create(recursive: true);
    final sink = targetFile.openWrite();

    try {
      int bytesReceived = 0;
      await for (final chunk in finalResponse.stream) {
        cancellationToken?.throwIfCancelled();
        bytesReceived += chunk.length;

        if (bytesReceived > expectedSizeBytes) {
          throw const ProvisioningException(
            reason: ProvisioningFailureReason.sizeLimitExceeded,
            message:
                'La dimensione scaricata ha superato la dimensione dichiarata per l\'artefatto.',
          );
        }
        sink.add(chunk);
      }

      await sink.flush();
      await sink.close();

      if (bytesReceived != expectedSizeBytes) {
        throw const ProvisioningException(
          reason: ProvisioningFailureReason.sizeMismatch,
          message:
              'La dimensione finale del file scaricato non corrisponde a quella del manifest.',
        );
      }

      return bytesReceived;
    } on ProvisioningException {
      await sink.close();
      if (await targetFile.exists()) {
        try {
          await targetFile.delete();
        } catch (_) {}
      }
      rethrow;
    } catch (_) {
      await sink.close();
      if (await targetFile.exists()) {
        try {
          await targetFile.delete();
        } catch (_) {}
      }
      throw const ProvisioningIoException(operation: 'downloadFile');
    }
  }
}
