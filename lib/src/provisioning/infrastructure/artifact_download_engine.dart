import 'dart:async';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

import '../domain/download_cancellation_token.dart';
import '../domain/download_checkpoint.dart';
import '../domain/download_progress.dart';
import '../domain/download_request.dart';
import '../domain/download_result.dart';
import '../domain/staging_artifact.dart';
import 'download_checkpoint_repository.dart';
import 'download_concurrency_controller.dart';
import '../domain/provisioning_clock.dart';
import 'provisioning_file_system.dart';
import 'provisioning_path_resolver.dart';

/// Interfaccia pubblica del motore di download per artefatti di modello nello staging.
abstract class ArtifactDownloadEngine {
  /// Esegue il download o il resume via HTTP Range dell'artefatto specificato in [request].
  Future<DownloadResult> downloadArtifact({
    required DownloadRequest request,
    DownloadCancellationToken? cancellationToken,
    void Function(DownloadProgress progress)? onProgress,
  });
}

/// Implementazione concreta del motore di download resiliente con HTTP Range streaming, Strong ETag ed `If-Range`.
final class DefaultArtifactDownloadEngine implements ArtifactDownloadEngine {
  final http.Client _httpClient;
  final ProvisioningFileSystem _fileSystem;
  final ProvisioningPathResolver _pathResolver;
  final DownloadCheckpointRepository _checkpointRepository;
  final DownloadConcurrencyController _concurrencyController;
  final ProvisioningClock _clock;

  DefaultArtifactDownloadEngine({
    required http.Client httpClient,
    required ProvisioningFileSystem fileSystem,
    required ProvisioningPathResolver pathResolver,
    required DownloadCheckpointRepository checkpointRepository,
    required DownloadConcurrencyController concurrencyController,
    ProvisioningClock clock = const SystemProvisioningClock(),
  })  : _httpClient = httpClient,
        _fileSystem = fileSystem,
        _pathResolver = pathResolver,
        _checkpointRepository = checkpointRepository,
        _concurrencyController = concurrencyController,
        _clock = clock;

  @override
  Future<DownloadResult> downloadArtifact({
    required DownloadRequest request,
    DownloadCancellationToken? cancellationToken,
    void Function(DownloadProgress progress)? onProgress,
  }) async {
    // 1. Acquisizione lock esclusivo sulla destinazione per operationId
    if (!_concurrencyController.tryAcquireLock(request.operationId)) {
      return DownloadResult.failure(
        reason: DownloadFailureReason.destinationLocked,
        message:
            'Operazione di download gia in corso o limite di concorrenza raggiunto per operationId="${request.operationId}".',
        isRetryable: false,
      );
    }

    try {
      return await _executeDownload(
        request: request,
        cancellationToken: cancellationToken,
        onProgress: onProgress,
      );
    } finally {
      _concurrencyController.releaseLock(request.operationId);
    }
  }

  Future<DownloadResult> _executeDownload({
    required DownloadRequest request,
    DownloadCancellationToken? cancellationToken,
    void Function(DownloadProgress progress)? onProgress,
    bool allowFallbackRestart = true,
  }) async {
    final stagingPartPath = _pathResolver.stagingPartPath(request.operationId);
    final stagingDir = _pathResolver.stagingDirectory;

    if (!await _fileSystem.directoryExists(stagingDir)) {
      await _fileSystem.createDirectory(stagingDir);
    }

    // 2. Controllo preventivo spazio libero su disco
    var currentPartSize = 0;
    if (await _fileSystem.fileExists(stagingPartPath)) {
      currentPartSize = await _fileSystem.getFileSize(stagingPartPath);
    }

    final availableSpace = await _fileSystem.getAvailableFreeSpace(stagingDir);
    final neededSpace = request.expectedSizeBytes - currentPartSize;
    if (availableSpace != null && availableSpace < neededSpace) {
      return DownloadResult.failure(
        reason: DownloadFailureReason.insufficientStorage,
        message:
            'Spazio su disco insufficiente nella directory di staging: necessari $neededSpace byte, disponibili $availableSpace byte.',
        isRetryable: false,
      );
    }

    // 3. Riconciliazione tra checkpoint su disco e dimensione reale del file .part
    DownloadCheckpoint? activeCheckpoint =
        await _checkpointRepository.readCheckpoint(request.operationId);
    var downloadedBytes = 0;

    if (activeCheckpoint == null) {
      // Checkpoint assente: crea/resetta il file .part a 0 byte
      await _fileSystem.truncateFile(stagingPartPath, 0);
      currentPartSize = 0;
      downloadedBytes = 0;
    } else {
      // Verifica coerenza tra il checkpoint ed la richiesta corrente
      final isTargetMatching =
          activeCheckpoint.operationId == request.operationId &&
              activeCheckpoint.artifactId == request.artifactId &&
              activeCheckpoint.sourceUri == request.sourceUri.toString() &&
              activeCheckpoint.expectedSizeBytes == request.expectedSizeBytes;

      if (!isTargetMatching) {
        await _fileSystem.truncateFile(stagingPartPath, 0);
        await _checkpointRepository.deleteCheckpoint(request.operationId);
        activeCheckpoint = null;
        downloadedBytes = 0;
      } else {
        if (activeCheckpoint.downloadedBytes > currentPartSize) {
          // Checkpoint dichiara piu byte del file su disco -> invalido, reset
          await _fileSystem.truncateFile(stagingPartPath, 0);
          await _checkpointRepository.deleteCheckpoint(request.operationId);
          activeCheckpoint = null;
          downloadedBytes = 0;
        } else if (activeCheckpoint.downloadedBytes < currentPartSize) {
          // File su disco ha byte non flushati dal checkpoint -> tronca a checkpoint
          await _fileSystem.truncateFile(
              stagingPartPath, activeCheckpoint.downloadedBytes);
          downloadedBytes = activeCheckpoint.downloadedBytes;
        } else {
          // downloadedBytes == currentPartSize -> candidato idoneo al resume
          downloadedBytes = activeCheckpoint.downloadedBytes;
        }
      }
    }

    // 4. Se il file e gia stato completato ed e coerente prima della rete
    if (downloadedBytes == request.expectedSizeBytes &&
        activeCheckpoint != null) {
      await _checkpointRepository.deleteCheckpoint(request.operationId);
      final artifact = StagingArtifact(
        operationId: request.operationId,
        artifactId: request.artifactId,
        stagingPath: stagingPartPath,
        sizeBytes: downloadedBytes,
        strongEtag: activeCheckpoint.strongEtag,
        completedAtUtc: _clock.nowUtc(),
      );
      return DownloadResult.success(artifact);
    }

    // 5. Esecuzione richiesta HTTP con gestione dei Redirect ed header Range/If-Range
    Uri currentUri = request.sourceUri;
    var redirectCount = 0;
    var forwardedHeaders =
        Map<String, String>.from(request.sanitizedExtraHeaders);
    http.StreamedResponse? response;

    while (redirectCount <= 5) {
      if (cancellationToken != null && cancellationToken.isCancelled) {
        return DownloadResult.cancelled(
          message: cancellationToken.cancelReason ?? 'Download annullato.',
          checkpoint: activeCheckpoint,
        );
      }

      final headers = Map<String, String>.from(forwardedHeaders);

      // Invia Range ed If-Range solo se e presente un checkpoint valido con ETag forte
      final canUseRange = downloadedBytes > 0 &&
          activeCheckpoint != null &&
          activeCheckpoint.hasValidStrongEtag;

      if (canUseRange) {
        headers['Range'] = 'bytes=$downloadedBytes-';
        headers['If-Range'] = activeCheckpoint.strongEtag!;
      }

      final httpRequest = http.Request('GET', currentUri);
      httpRequest.headers.addAll(headers);

      try {
        final Future<http.StreamedResponse> sendFuture =
            _httpClient.send(httpRequest);
        final timeoutDuration = request.timeout;
        final sentResponse = timeoutDuration != null
            ? await sendFuture.timeout(
                timeoutDuration,
                onTimeout: () => throw TimeoutException(
                  'Timeout durante la connessione HTTP (${timeoutDuration.inSeconds}s).',
                ),
              )
            : await sendFuture;

        // Gestione dei redirect HTTP (301, 302, 303, 307, 308)
        if (sentResponse.statusCode >= 300 &&
            sentResponse.statusCode < 400 &&
            sentResponse.headers.containsKey('location')) {
          final location = sentResponse.headers['location']!;
          final redirectUri = currentUri.resolve(location);

          // Divieto di downgrade da HTTPS a HTTP
          if (currentUri.scheme == 'https' && redirectUri.scheme == 'http') {
            return DownloadResult.failure(
              reason: DownloadFailureReason.insecureRedirect,
              message:
                  'Tentativo di redirect non sicuro da HTTPS a HTTP intercettato per "$redirectUri".',
              checkpoint: activeCheckpoint,
              isRetryable: false,
            );
          }

          // Cross-Origin redirect (scheme + host + port): rimozione degli header sensibili (es. Authorization)
          if (_isCrossOrigin(currentUri, redirectUri)) {
            forwardedHeaders.removeWhere(
              (k, v) => k.toLowerCase() == 'authorization',
            );
          }

          currentUri = redirectUri;
          redirectCount++;
          continue;
        }

        response = sentResponse;
        break;
      } on TimeoutException catch (e) {
        return DownloadResult.failure(
          reason: DownloadFailureReason.networkTimeout,
          message: e.message ?? 'Timeout durante la connessione HTTP.',
          checkpoint: activeCheckpoint,
          isRetryable: true,
        );
      } catch (e) {
        return DownloadResult.failure(
          reason: DownloadFailureReason.networkDisconnected,
          message: 'Errore di connessione durante la richiesta HTTP: $e',
          checkpoint: activeCheckpoint,
          isRetryable: true,
        );
      }
    }

    if (redirectCount > 5) {
      return DownloadResult.failure(
        reason: DownloadFailureReason.tooManyRedirects,
        message: 'Superato il limite massimo di 5 redirect HTTP.',
        checkpoint: activeCheckpoint,
        isRetryable: false,
      );
    }

    if (response == null) {
      return DownloadResult.failure(
        reason: DownloadFailureReason.networkDisconnected,
        message: 'Nessuna risposta dal server remoto.',
        checkpoint: activeCheckpoint,
        isRetryable: true,
      );
    }

    // 6. Validazione status code HTTP ed ETag / Content-Range
    final responseStatusCode = response.statusCode;
    final responseRawEtag = response.headers['etag'];
    final responseStrongEtag = _extractStrongEtag(responseRawEtag);

    if (responseStatusCode == 206) {
      // Validazione stringente della risposta 206 Partial Content
      final is206Valid = _validate206Response(
        responseHeaders: response.headers,
        downloadedBytes: downloadedBytes,
        expectedSizeBytes: request.expectedSizeBytes,
        activeCheckpoint: activeCheckpoint,
        responseStrongEtag: responseStrongEtag,
      );

      if (!is206Valid) {
        // Rifiuto 206 non valida: reset a 0 byte e retry GET incondizionato (singolo tentativo di fallback)
        await _fileSystem.truncateFile(stagingPartPath, 0);
        await _checkpointRepository.deleteCheckpoint(request.operationId);
        activeCheckpoint = null;
        downloadedBytes = 0;

        if (!allowFallbackRestart) {
          return DownloadResult.failure(
            reason: DownloadFailureReason.httpStatusError,
            message:
                'Risposta HTTP 206 non valida ricevuta. Ricorsione di fallback interrotta.',
            checkpoint: activeCheckpoint,
            isRetryable: false,
          );
        }

        return _executeUnconditionalGet(
          request: request,
          stagingPartPath: stagingPartPath,
          cancellationToken: cancellationToken,
          onProgress: onProgress,
        );
      }
    } else if (responseStatusCode == 416) {
      // Gestione restrittiva HTTP 416 Range Not Satisfiable con validazione ETag della risposta
      final contentRangeHeader = response.headers['content-range'];
      final remoteTotal = _parse416RemoteTotal(contentRangeHeader);

      final is416Valid = downloadedBytes == request.expectedSizeBytes &&
          remoteTotal == request.expectedSizeBytes &&
          activeCheckpoint != null &&
          responseStrongEtag != null &&
          responseStrongEtag == activeCheckpoint.strongEtag;

      if (is416Valid) {
        await _checkpointRepository.deleteCheckpoint(request.operationId);
        final artifact = StagingArtifact(
          operationId: request.operationId,
          artifactId: request.artifactId,
          stagingPath: stagingPartPath,
          sizeBytes: downloadedBytes,
          strongEtag: activeCheckpoint.strongEtag,
          completedAtUtc: _clock.nowUtc(),
        );
        return DownloadResult.success(artifact);
      } else {
        // 416 non riconciliabile o ETag difforme -> reset e singolo tentativo di fallback
        await _fileSystem.truncateFile(stagingPartPath, 0);
        await _checkpointRepository.deleteCheckpoint(request.operationId);
        activeCheckpoint = null;
        downloadedBytes = 0;

        if (!allowFallbackRestart) {
          return DownloadResult.failure(
            reason: DownloadFailureReason.httpStatusError,
            message:
                'Risposta HTTP 416 non riconciliabile o ETag difforme ricevuta. Ricorsione di fallback interrotta.',
            checkpoint: activeCheckpoint,
            isRetryable: false,
          );
        }

        return _executeUnconditionalGet(
          request: request,
          stagingPartPath: stagingPartPath,
          cancellationToken: cancellationToken,
          onProgress: onProgress,
        );
      }
    } else if (responseStatusCode == 200) {
      // Server ha risposto 200 (Range ignorato o download da byte 0)
      if (downloadedBytes > 0) {
        await _fileSystem.truncateFile(stagingPartPath, 0);
        downloadedBytes = 0;
      }
      activeCheckpoint = DownloadCheckpoint(
        operationId: request.operationId,
        artifactId: request.artifactId,
        sourceUri: request.sourceUri.toString(),
        strongEtag: responseStrongEtag,
        downloadedBytes: 0,
        expectedSizeBytes: request.expectedSizeBytes,
        createdAtUtc: _clock.nowUtc(),
        updatedAtUtc: _clock.nowUtc(),
        lastModified: response.headers['last-modified'],
      );
      await _checkpointRepository.saveCheckpoint(activeCheckpoint);
    } else {
      return DownloadResult.failure(
        reason: DownloadFailureReason.httpStatusError,
        message:
            'Risposta HTTP fallita con codice di errore $responseStatusCode per "${request.sourceUri}".',
        checkpoint: activeCheckpoint,
        isRetryable: responseStatusCode >= 500,
      );
    }

    // 7. Streaming dei chunk su file .part e salvataggio atomico del checkpoint con applicazione del timeout di inattivita
    final stopwatch = Stopwatch()..start();
    var bytesSinceLastCheckpoint = 0;

    try {
      final timeoutDuration = request.timeout;
      final timedStream = timeoutDuration != null
          ? response.stream.timeout(
              timeoutDuration,
              onTimeout: (sink) => sink.addError(
                TimeoutException(
                  'Inattivita dello stream HTTP oltre ${timeoutDuration.inSeconds} secondi.',
                ),
              ),
            )
          : response.stream;

      final writeBuffer = BytesBuilder(copy: false);
      const writeThresholdBytes = 1 * 1024 * 1024;
      const checkpointThresholdBytes = 4 * 1024 * 1024;
      var lastProgressNotifyMs = 0;

      await for (final chunk in timedStream) {
        if (cancellationToken != null && cancellationToken.isCancelled) {
          if (writeBuffer.isNotEmpty) {
            await _fileSystem.appendBytes(
                stagingPartPath, writeBuffer.takeBytes());
          }
          if (activeCheckpoint != null) {
            await _checkpointRepository.saveCheckpoint(activeCheckpoint);
          }
          return DownloadResult.cancelled(
            message: cancellationToken.cancelReason ?? 'Download annullato.',
            checkpoint: activeCheckpoint,
          );
        }

        if (downloadedBytes + chunk.length > request.expectedSizeBytes) {
          if (writeBuffer.isNotEmpty) {
            await _fileSystem.appendBytes(
                stagingPartPath, writeBuffer.takeBytes());
          }
          return DownloadResult.failure(
            reason: DownloadFailureReason.ioFailure,
            message:
                'I byte ricevuti (${downloadedBytes + chunk.length}) superano la dimensione attesa (${request.expectedSizeBytes}).',
            checkpoint: activeCheckpoint,
            isRetryable: false,
          );
        }

        // Bufferizzazione chunk ed avanzamento
        writeBuffer.add(chunk);
        downloadedBytes += chunk.length;
        bytesSinceLastCheckpoint += chunk.length;

        // Scrittura batch su disco ogni ~1 MB o a fine download
        if (writeBuffer.length >= writeThresholdBytes ||
            downloadedBytes == request.expectedSizeBytes) {
          await _fileSystem.appendBytes(
              stagingPartPath, writeBuffer.takeBytes());
        }

        // Scrittura atomica del checkpoint periodica (ogni ~4 MB)
        if (bytesSinceLastCheckpoint >= checkpointThresholdBytes ||
            downloadedBytes == request.expectedSizeBytes) {
          activeCheckpoint = (activeCheckpoint ??
                  DownloadCheckpoint(
                    operationId: request.operationId,
                    artifactId: request.artifactId,
                    sourceUri: request.sourceUri.toString(),
                    strongEtag: responseStrongEtag,
                    downloadedBytes: downloadedBytes,
                    expectedSizeBytes: request.expectedSizeBytes,
                    createdAtUtc: _clock.nowUtc(),
                    updatedAtUtc: _clock.nowUtc(),
                  ))
              .copyWithProgress(
            downloadedBytes: downloadedBytes,
            updatedAtUtc: _clock.nowUtc(),
            strongEtag: responseStrongEtag,
          );

          await _checkpointRepository.saveCheckpoint(activeCheckpoint);
          bytesSinceLastCheckpoint = 0;
        }

        // Notifica avanzamento in tempo reale throttled (~100ms)
        final nowMs = stopwatch.elapsedMilliseconds;
        if (onProgress != null &&
            (nowMs - lastProgressNotifyMs >= 100 ||
                downloadedBytes == request.expectedSizeBytes)) {
          lastProgressNotifyMs = nowMs;
          final elapsedSec = nowMs / 1000.0;
          final speed = elapsedSec > 0 ? (downloadedBytes / elapsedSec) : 0.0;
          final fraction =
              (downloadedBytes / request.expectedSizeBytes).clamp(0.0, 1.0);
          final remainingBytes = request.expectedSizeBytes - downloadedBytes;
          final eta = speed > 0
              ? Duration(seconds: (remainingBytes / speed).ceil())
              : null;

          onProgress(DownloadProgress(
            operationId: request.operationId,
            downloadedBytes: downloadedBytes,
            totalBytes: request.expectedSizeBytes,
            bytesPerSecond: speed,
            fraction: fraction,
            estimatedRemaining: eta,
          ));
        }
      }

      if (writeBuffer.isNotEmpty) {
        await _fileSystem.appendBytes(stagingPartPath, writeBuffer.takeBytes());
      }

      // 8. Chiusura sessione, controllo finale size ed eliminazione checkpoint
      if (cancellationToken != null && cancellationToken.isCancelled) {
        if (activeCheckpoint != null) {
          await _checkpointRepository.saveCheckpoint(activeCheckpoint);
        }
        return DownloadResult.cancelled(
          message: cancellationToken.cancelReason ?? 'Download annullato.',
          checkpoint: activeCheckpoint,
        );
      }

      if (downloadedBytes == request.expectedSizeBytes) {
        await _checkpointRepository.deleteCheckpoint(request.operationId);
        final artifact = StagingArtifact(
          operationId: request.operationId,
          artifactId: request.artifactId,
          stagingPath: stagingPartPath,
          sizeBytes: downloadedBytes,
          strongEtag: responseStrongEtag ?? activeCheckpoint?.strongEtag,
          completedAtUtc: _clock.nowUtc(),
        );
        return DownloadResult.success(artifact);
      } else {
        return DownloadResult.failure(
          reason: DownloadFailureReason.ioFailure,
          message:
              'Stream terminato ma i byte scaricati ($downloadedBytes) non corrispondono a expectedSizeBytes (${request.expectedSizeBytes}).',
          checkpoint: activeCheckpoint,
          isRetryable: true,
        );
      }
    } on TimeoutException catch (e) {
      return DownloadResult.failure(
        reason: DownloadFailureReason.networkTimeout,
        message:
            'Timeout per inattivita dello stream HTTP (${request.timeout?.inSeconds ?? 0}s): ${e.message ?? ''}',
        checkpoint: activeCheckpoint,
        isRetryable: true,
      );
    } catch (e) {
      return DownloadResult.failure(
        reason: DownloadFailureReason.networkDisconnected,
        message: 'Interruzione durante lo streaming del download: $e',
        checkpoint: activeCheckpoint,
        isRetryable: true,
      );
    }
  }

  /// Esegue un tentativo GET incondizionato da byte 0 dopo il rifiuto di una risposta 206 o 416.
  Future<DownloadResult> _executeUnconditionalGet({
    required DownloadRequest request,
    required String stagingPartPath,
    DownloadCancellationToken? cancellationToken,
    void Function(DownloadProgress progress)? onProgress,
  }) async {
    final unconditionalRequest = DownloadRequest(
      operationId: request.operationId,
      artifactId: request.artifactId,
      sourceUri: request.sourceUri,
      expectedSizeBytes: request.expectedSizeBytes,
      extraHeaders: request.extraHeaders,
      timeout: request.timeout,
    );

    return _executeDownload(
      request: unconditionalRequest,
      cancellationToken: cancellationToken,
      onProgress: onProgress,
      allowFallbackRestart: false,
    );
  }

  /// Estrae un ETag forte garantendo la conformita al pattern ^"[^"]+"$.
  String? _extractStrongEtag(String? rawEtag) {
    if (!DownloadCheckpoint.isValidStrongEtag(rawEtag)) return null;
    return rawEtag!.trim();
  }

  /// Verifica se due URI costituiscono una richiesta Cross-Origin (schema, host o porta differenti).
  bool _isCrossOrigin(Uri current, Uri target) {
    return current.scheme.toLowerCase() != target.scheme.toLowerCase() ||
        current.host.toLowerCase() != target.host.toLowerCase() ||
        current.port != target.port;
  }

  /// Valida le condizioni rigorose per l'accettazione di una risposta HTTP 206 Partial Content.
  bool _validate206Response({
    required Map<String, String> responseHeaders,
    required int downloadedBytes,
    required int expectedSizeBytes,
    required DownloadCheckpoint? activeCheckpoint,
    required String? responseStrongEtag,
  }) {
    // Un 206 da byte zero puo essere valido soltanto se e stata effettivamente inviata una richiesta Range!
    if (downloadedBytes <= 0) return false;

    if (activeCheckpoint == null || !activeCheckpoint.hasValidStrongEtag) {
      return false;
    }

    // La risposta 206 DEVE contenere un ETag forte corrispondente a quello del checkpoint
    if (responseStrongEtag == null ||
        responseStrongEtag != activeCheckpoint.strongEtag) {
      return false;
    }

    final contentRange = responseHeaders['content-range'];
    if (contentRange == null || contentRange.trim().isEmpty) return false;

    // Content-Range: bytes <start>-<end>/<total> (ancorata, totale '*' non accettato)
    final match = RegExp(r'^bytes\s+(\d+)-(\d+)\/(\d+)$', caseSensitive: false)
        .firstMatch(contentRange.trim());
    if (match == null) return false;

    final start = int.parse(match.group(1)!);
    final end = int.parse(match.group(2)!);
    final total = int.parse(match.group(3)!);

    if (end < start) return false;
    if (end >= total) return false;
    if (start != downloadedBytes) return false;
    if (total != expectedSizeBytes) return false;

    final contentLengthStr = responseHeaders['content-length'];
    if (contentLengthStr != null) {
      final contentLength = int.tryParse(contentLengthStr.trim());
      // Se Content-Length e presente, deve essere parsabile e corrispondere esattamente a (end - start + 1)
      if (contentLength == null || contentLength != (end - start + 1)) {
        return false;
      }
    }

    return true;
  }

  /// Estrae la dimensione totale da un header `Content-Range: bytes */<total>` per HTTP 416.
  int? _parse416RemoteTotal(String? contentRangeHeader) {
    if (contentRangeHeader == null || contentRangeHeader.trim().isEmpty) {
      return null;
    }
    final match = RegExp(r'^bytes\s+\*\/(\d+)$', caseSensitive: false)
        .firstMatch(contentRangeHeader.trim());
    if (match == null) return null;
    return int.parse(match.group(1)!);
  }
}
