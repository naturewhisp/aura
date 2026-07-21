import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../domain/provisioning_cancellation_token.dart';
import '../domain/provisioning_options.dart';
import 'provisioning_io_exception.dart';

/// Policy applicativa per la gestione del cambio host durante i redirect HTTP.
enum RedirectHostPolicy {
  sameHostOnly,
  allowListedHosts;
}

/// Contratto astratto per il download HTTP/HTTPS di artefatti remoti.
abstract class ProvisioningHttpClient {
  /// Scarica un file dall'URL remoto specificato e lo salva su [targetPath].
  /// Ritorna il numero totale di byte scaricati.
  Future<int> downloadFile({
    required String uri,
    required String targetPath,
    required int expectedSizeBytes,
    ProvisioningCancellationToken? cancellationToken,
    RedirectHostPolicy redirectHostPolicy = RedirectHostPolicy.sameHostOnly,
    Duration timeout = const Duration(minutes: 5),
  });

  /// Chiude le risorse di rete sottostanti.
  Future<void> close();
}

/// Implementazione concreta basata su `package:http` con gestione sicura dei redirect HTTPS e verifica esatta delle dimensioni.
final class HttpProvisioningHttpClient implements ProvisioningHttpClient {
  static const int maxRedirects = 5;
  final http.Client _client;
  final bool _isOwnedClient;

  HttpProvisioningHttpClient({http.Client? client})
      : _client = client ?? http.Client(),
        _isOwnedClient = client == null;

  @override
  Future<void> close() async {
    if (_isOwnedClient) {
      _client.close();
    }
  }

  @override
  Future<int> downloadFile({
    required String uri,
    required String targetPath,
    required int expectedSizeBytes,
    ProvisioningCancellationToken? cancellationToken,
    RedirectHostPolicy redirectHostPolicy = RedirectHostPolicy.sameHostOnly,
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
          await response.stream
              .drain<void>()
              .timeout(const Duration(seconds: 2))
              .catchError((_) {});
          throw const ProvisioningException(
            reason: ProvisioningFailureReason.redirectRejected,
            message: 'Numero massimo di redirect HTTP superato.',
          );
        }

        final locationHeader = response.headers['location'];
        if (locationHeader == null || locationHeader.trim().isEmpty) {
          await response.stream
              .drain<void>()
              .timeout(const Duration(seconds: 2))
              .catchError((_) {});
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
          await response.stream
              .drain<void>()
              .timeout(const Duration(seconds: 2))
              .catchError((_) {});
          throw const ProvisioningException(
            reason: ProvisioningFailureReason.redirectRejected,
            message: 'Redirect rifiutato: URL non HTTPS o non sicura.',
          );
        }

        // Verifica Policy Cambio Host (Finding 6)
        if (redirectHostPolicy == RedirectHostPolicy.sameHostOnly &&
            redirectUri.host.toLowerCase() != parsedUri.host.toLowerCase()) {
          await response.stream
              .drain<void>()
              .timeout(const Duration(seconds: 2))
              .catchError((_) {});
          throw const ProvisioningException(
            reason: ProvisioningFailureReason.redirectRejected,
            message:
                'Redirect verso host esterno rifiutato dalla policy applicativa.',
          );
        }

        // Drena lo stream della risposta 3xx prima di proseguire (Finding 7)
        await response.stream
            .drain<void>()
            .timeout(const Duration(seconds: 2))
            .catchError((_) {});

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

    StreamSubscription<List<int>>? subscription;
    Completer<void> streamDone = Completer<void>();

    try {
      int bytesReceived = 0;

      subscription = finalResponse.stream.listen(
        (chunk) async {
          bytesReceived += chunk.length;

          if (bytesReceived > expectedSizeBytes) {
            subscription?.cancel();
            if (!streamDone.isCompleted) {
              streamDone.completeError(
                const ProvisioningException(
                  reason: ProvisioningFailureReason.sizeLimitExceeded,
                  message:
                      'La dimensione scaricata ha superato la dimensione dichiarata per l\'artefatto.',
                ),
              );
            }
            return;
          }
          sink.add(chunk);
        },
        onError: (e) {
          if (!streamDone.isCompleted) {
            streamDone.completeError(e);
          }
        },
        onDone: () {
          if (!streamDone.isCompleted) {
            streamDone.complete();
          }
        },
        cancelOnError: true,
      );

      // In ascolto concorrente di: streamDone, cancellationToken, timeout (Finding 5)
      final cancelFuture = cancellationToken?.whenCancelled.then((_) {
        subscription?.cancel();
        throw const ProvisioningException(
          reason: ProvisioningFailureReason.operationCancelled,
          message: 'Download annullato dall\'utente o dal sistema.',
        );
      });

      if (cancelFuture != null) {
        await Future.any([
          streamDone.future,
          cancelFuture,
        ]).timeout(timeout, onTimeout: () {
          subscription?.cancel();
          throw const ProvisioningException(
            reason: ProvisioningFailureReason.downloadTimeout,
            message: 'Timeout globale durante lo streaming del download.',
          );
        });
      } else {
        await streamDone.future.timeout(timeout, onTimeout: () {
          subscription?.cancel();
          throw const ProvisioningException(
            reason: ProvisioningFailureReason.downloadTimeout,
            message: 'Timeout globale durante lo streaming del download.',
          );
        });
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
      await subscription?.cancel();
      await sink.close();
      if (await targetFile.exists()) {
        try {
          await targetFile.delete();
        } catch (_) {}
      }
      rethrow;
    } catch (e) {
      await subscription?.cancel();
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
