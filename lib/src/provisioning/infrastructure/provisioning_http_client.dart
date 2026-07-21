import 'dart:io';
import 'package:http/http.dart' as http;
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
    Duration timeout = const Duration(minutes: 5),
  });
}

/// Implementazione concreta basata su `package:http`.
final class HttpProvisioningHttpClient implements ProvisioningHttpClient {
  final http.Client _client;

  HttpProvisioningHttpClient({http.Client? client})
      : _client = client ?? http.Client();

  @override
  Future<int> downloadFile({
    required String uri,
    required String targetPath,
    required int expectedSizeBytes,
    Duration timeout = const Duration(minutes: 5),
  }) async {
    final parsedUri = Uri.tryParse(uri);
    if (parsedUri == null ||
        !parsedUri.isAbsolute ||
        parsedUri.scheme != 'https' ||
        parsedUri.host.isEmpty) {
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.invalidSourceUri,
        message: 'URI remota non valida o non HTTPS.',
      );
    }

    final targetFile = File(targetPath);
    await targetFile.parent.create(recursive: true);
    final sink = targetFile.openWrite();

    try {
      final request = http.Request('GET', parsedUri);
      final response = await _client.send(request).timeout(timeout);

      if (response.statusCode != 200) {
        throw ProvisioningException(
          reason: ProvisioningFailureReason.downloadFailed,
          message:
              'Download fallito con codice di stato HTTP: ${response.statusCode}.',
        );
      }

      final contentLength = response.contentLength;
      if (contentLength != null && contentLength > expectedSizeBytes) {
        throw const ProvisioningException(
          reason: ProvisioningFailureReason.sizeLimitExceeded,
          message:
              'La dimensione dichiarata dall\'header HTTP supera il limite.',
        );
      }

      int bytesReceived = 0;
      await for (final chunk in response.stream) {
        bytesReceived += chunk.length;
        if (bytesReceived > expectedSizeBytes * 2) {
          throw const ProvisioningException(
            reason: ProvisioningFailureReason.sizeLimitExceeded,
            message:
                'Il download ha superato il limite di dimensione consentito.',
          );
        }
        sink.add(chunk);
      }

      await sink.flush();
      await sink.close();

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
